import { describe, expect, test } from "bun:test";

import { bugAlertSlackPayload, parseBugAlert } from "../services/bugAlerts";

describe("bug alerts", () => {
  test("parses and scrubs safe bug alert payloads", () => {
    const parsed = parseBugAlert({
      event: "mac_error_captured",
      severity: "error",
      source: "TerminalNotificationStore",
      error_kind: "notification.error",
      properties: {
        app_version: "0.31.0",
        count: 2,
        has_surface: true,
        body: "private terminal output",
        path: "/Users/example/private",
        nested: { bad: true },
      },
    });

    expect(parsed.ok).toBe(true);
    if (!parsed.ok) return;
    expect(parsed.alert.properties).toEqual({
      app_version: "0.31.0",
      count: 2,
      has_surface: true,
    });
  });

  test("rejects invalid severity and identifiers", () => {
    expect(parseBugAlert({
      event: "mac_error_captured",
      severity: "fatal",
      source: "TerminalNotificationStore",
      error_kind: "notification.error",
    })).toEqual({ ok: false, error: "invalid_severity" });

    expect(parseBugAlert({
      event: "mac_error_captured",
      severity: "error",
      source: "Terminal Notification Store",
      error_kind: "notification.error",
    })).toEqual({ ok: false, error: "missing_source" });
  });

  test("escapes Slack payload fields", () => {
    const payload = bugAlertSlackPayload({
      event: "mac_error_captured",
      severity: "error",
      source: "source",
      errorKind: "kind",
      properties: { action_id: "<!channel>" },
    });

    expect(payload.text).toContain("&lt;!channel&gt;");
    expect(payload.text).not.toContain("<!channel>");
  });
});
