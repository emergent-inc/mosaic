const originalSkipEnvValidation = process.env.SKIP_ENV_VALIDATION;
const originalWebhook = process.env.CMUX_BUG_ALERTS_WEBHOOK_URL;
const originalSharedSecret = process.env.CMUX_BUG_ALERTS_SHARED_SECRET;
process.env.SKIP_ENV_VALIDATION = "1";
process.env.CMUX_BUG_ALERTS_WEBHOOK_URL = "https://hooks.test/cmux-bugs";
process.env.CMUX_BUG_ALERTS_SHARED_SECRET = "test-secret";

import { afterAll, beforeEach, describe, expect, mock, test } from "bun:test";

const route = await import("../app/api/bug-alerts/route");

const originalFetch = globalThis.fetch;
let nextFetchResponse: Response | null = null;
const fetchMock = mock(async () => {
  const response = nextFetchResponse ?? new Response("ok", { status: 200 });
  nextFetchResponse = null;
  return response;
});

beforeEach(() => {
  nextFetchResponse = null;
  fetchMock.mockClear();
  globalThis.fetch = fetchMock as unknown as typeof fetch;
});

afterAll(() => {
  globalThis.fetch = originalFetch;
  if (originalSkipEnvValidation === undefined) {
    delete process.env.SKIP_ENV_VALIDATION;
  } else {
    process.env.SKIP_ENV_VALIDATION = originalSkipEnvValidation;
  }
  if (originalWebhook === undefined) {
    delete process.env.CMUX_BUG_ALERTS_WEBHOOK_URL;
  } else {
    process.env.CMUX_BUG_ALERTS_WEBHOOK_URL = originalWebhook;
  }
  if (originalSharedSecret === undefined) {
    delete process.env.CMUX_BUG_ALERTS_SHARED_SECRET;
  } else {
    process.env.CMUX_BUG_ALERTS_SHARED_SECRET = originalSharedSecret;
  }
});

function bugAlertRequest(body: unknown, secret = "test-secret"): Request {
  return new Request("https://cmux.test/api/bug-alerts", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Cmux-Bug-Alerts-Secret": secret,
    },
    body: JSON.stringify(body),
  });
}

describe("bug alerts route", () => {
  test("posts sanitized high-signal bug alerts to the configured webhook", async () => {
    const response = await route.POST(bugAlertRequest({
      event: "mac_error_notification_shown",
      severity: "critical",
      source: "TerminalNotificationStore",
      error_kind: "notification.crash",
      properties: {
        app_version: "0.31.0",
        has_surface: true,
        body: "private terminal output",
        path: "/Users/example/private",
        action_id: "<!channel>",
      },
    }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, notified: true });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const calls = (fetchMock as unknown as {
      mock: { calls: Array<[string, RequestInit]> };
    }).mock.calls;
    expect(calls[0]?.[0]).toBe("https://hooks.test/cmux-bugs");
    const body = JSON.parse(String(calls[0]?.[1].body));
    expect(body.text).toContain("mac_error_notification_shown");
    expect(body.text).toContain("notification.crash");
    expect(body.text).toContain("app_version");
    expect(body.text).toContain("has_surface");
    expect(body.text).toContain("&lt;!channel&gt;");
    expect(body.text).not.toContain("private terminal output");
    expect(body.text).not.toContain("/Users/example/private");
    expect(body.text).not.toContain("<!channel>");
  });

  test("rejects invalid bug alert payloads before webhook fan-out", async () => {
    const response = await route.POST(bugAlertRequest({
      event: "mac_error_notification_shown",
      severity: "fatal",
      source: "TerminalNotificationStore",
      error_kind: "notification.crash",
    }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_severity" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("rejects requests without the configured shared secret", async () => {
    const response = await route.POST(bugAlertRequest({
      event: "mac_error_notification_shown",
      severity: "critical",
      source: "TerminalNotificationStore",
      error_kind: "notification.crash",
    }, "wrong-secret"));

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("accepts warning alerts without Slack fan-out", async () => {
    const response = await route.POST(bugAlertRequest({
      event: "mac_error_captured",
      severity: "warning",
      source: "CollaborationRuntime",
      error_kind: "collaboration.join_failed",
    }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, notified: false });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("accepts high-signal alerts without notification when webhook is unset", async () => {
    const previousWebhook = process.env.CMUX_BUG_ALERTS_WEBHOOK_URL;
    delete process.env.CMUX_BUG_ALERTS_WEBHOOK_URL;
    try {
      const response = await route.POST(bugAlertRequest({
        event: "mac_error_captured",
        severity: "error",
        source: "CollaborationRuntime",
        error_kind: "collaboration.share_failed",
      }));

      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ ok: true, notified: false });
      expect(fetchMock).not.toHaveBeenCalled();
    } finally {
      if (previousWebhook === undefined) {
        delete process.env.CMUX_BUG_ALERTS_WEBHOOK_URL;
      } else {
        process.env.CMUX_BUG_ALERTS_WEBHOOK_URL = previousWebhook;
      }
    }
  });

  test("returns webhook_failed when the configured webhook rejects the alert", async () => {
    nextFetchResponse = new Response("nope", { status: 500 });

    const response = await route.POST(bugAlertRequest({
      event: "mac_error_captured",
      severity: "error",
      source: "runCmuxModalAlert",
      error_kind: "modal_alert.critical",
    }));

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "webhook_failed" });
  });
});
