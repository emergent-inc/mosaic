import { afterAll, beforeEach, describe, expect, mock, test } from "bun:test";

let authenticatedUser: { readonly id: string } | null = { id: "user-123" };
const verifyRequest = mock(async () => authenticatedUser);
const unauthorized = () => new Response(JSON.stringify({ error: "unauthorized" }), {
  headers: { "Content-Type": "application/json" },
  status: 401,
});

mock.module("../services/vms/auth", () => ({
  unauthorized,
  verifyRequest,
}));

const route = await import("../app/api/analytics/events/route");

const originalFetch = globalThis.fetch;
let nextFetchResponse: Response | null = null;
const fetchMock = mock(async () => {
  const response = nextFetchResponse ?? new Response("{}", { status: 200 });
  nextFetchResponse = null;
  return response;
});

beforeEach(() => {
  authenticatedUser = { id: "user-123" };
  nextFetchResponse = null;
  verifyRequest.mockClear();
  fetchMock.mockClear();
  globalThis.fetch = fetchMock as unknown as typeof fetch;
});

afterAll(() => {
  globalThis.fetch = originalFetch;
});

function analyticsRequest(body: unknown): Request {
  return new Request("https://cmux.test/api/analytics/events", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("analytics route", () => {
  test("accepts mac events and forwards them to PostHog with authenticated distinct id", async () => {
    const response = await route.POST(analyticsRequest({
      batch: [
        {
          event: "mac_button_clicked",
          distinct_id: "client-anon",
          properties: {
            action_id: "settings.send_feedback",
            surface: "settings",
            count: 2,
            nested: { ignored: true },
          },
        },
      ],
    }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, forwarded: 1 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const calls = (fetchMock as unknown as {
      mock: { calls: Array<[string, RequestInit]> };
    }).mock.calls;
    expect(calls[0]?.[0]).toBe("https://us.i.posthog.com/batch/");
    const body = JSON.parse(String(calls[0]?.[1].body));
    expect(body.batch).toEqual([
      {
        event: "mac_button_clicked",
        distinct_id: "user-123",
        properties: {
          action_id: "settings.send_feedback",
          surface: "settings",
          count: 2,
        },
      },
    ]);
  });

  test("forwards DAU with client anonymous id when no authenticated user is present", async () => {
    authenticatedUser = null;

    const response = await route.POST(analyticsRequest({
      batch: [
        {
          event: "cmux_daily_active",
          distinct_id: "mac_anon_install_123",
          properties: {
            day_utc: "2026-07-02",
            reason: "didBecomeActive",
          },
        },
      ],
    }));

    expect(response.status).toBe(200);
    const calls = (fetchMock as unknown as {
      mock: { calls: Array<[string, RequestInit]> };
    }).mock.calls;
    const body = JSON.parse(String(calls[0]?.[1].body));
    expect(body.batch[0]).toEqual({
      event: "cmux_daily_active",
      distinct_id: "mac_anon_install_123",
      properties: {
        day_utc: "2026-07-02",
        reason: "didBecomeActive",
      },
    });
  });

  test("forwards linking and sharing events to PostHog", async () => {
    authenticatedUser = null;

    const response = await route.POST(analyticsRequest({
      batch: [
        {
          event: "mac_linking_completed",
          distinct_id: "mac_anon_feature_user",
          properties: {
            link_kind: "ssh",
            entrypoint: "external_url",
            result: "completed",
            has_port: true,
          },
        },
        {
          event: "mac_collaboration_terminal_shared",
          distinct_id: "mac_anon_feature_user",
          properties: {
            share_kind: "terminal",
            entrypoint: "socket_share_selected",
            result: "completed",
            terminal_count: 1,
          },
        },
      ],
    }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, forwarded: 2 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const calls = (fetchMock as unknown as {
      mock: { calls: Array<[string, RequestInit]> };
    }).mock.calls;
    const body = JSON.parse(String(calls[0]?.[1].body));
    expect(body.batch).toEqual([
      {
        event: "mac_linking_completed",
        distinct_id: "mac_anon_feature_user",
        properties: {
          link_kind: "ssh",
          entrypoint: "external_url",
          result: "completed",
          has_port: true,
        },
      },
      {
        event: "mac_collaboration_terminal_shared",
        distinct_id: "mac_anon_feature_user",
        properties: {
          share_kind: "terminal",
          entrypoint: "socket_share_selected",
          result: "completed",
          terminal_count: 1,
        },
      },
    ]);
  });

  test("rejects batches containing only disallowed events before forwarding", async () => {
    const response = await route.POST(analyticsRequest({
      batch: [
        {
          event: "mac_raw_terminal_text",
          properties: { text: "do not ship" },
        },
      ],
    }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "no_valid_events" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("returns forward_failed when PostHog forwarding fails", async () => {
    nextFetchResponse = new Response("bad", { status: 503 });

    const response = await route.POST(analyticsRequest({
      batch: [
        {
          event: "mac_error_captured",
          properties: { error_kind: "modal_alert.critical" },
        },
      ],
    }));

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "forward_failed" });
  });
});
