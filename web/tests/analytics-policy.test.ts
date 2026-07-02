import { describe, expect, test } from "bun:test";

import { isAllowedAnalyticsEvent } from "../services/analytics/iosEventPolicy";

describe("analytics event policy", () => {
  test("allows iOS and macOS native events", () => {
    expect(isAllowedAnalyticsEvent("ios_app_launched")).toBe(true);
    expect(isAllowedAnalyticsEvent("mac_action_performed")).toBe(true);
    expect(isAllowedAnalyticsEvent("mac_error_notification_shown")).toBe(true);
  });

  test("rejects arbitrary analytics event names", () => {
    expect(isAllowedAnalyticsEvent("desktop_clicked_everything")).toBe(false);
    expect(isAllowedAnalyticsEvent("mac_raw_terminal_text")).toBe(false);
    expect(isAllowedAnalyticsEvent(null)).toBe(false);
  });
});
