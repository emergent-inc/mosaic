import { readBoundedJsonObject } from "../../../services/apns/routePolicy";
import { bugAlertSlackPayload, parseBugAlert } from "../../../services/bugAlerts";
import { recordSpanError, setSpanAttributes, withApiRouteSpan } from "../../../services/telemetry";
import { jsonResponse } from "../../../services/vms/routeHelpers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_BUG_ALERT_REQUEST_BYTES = 16 * 1024;
const BUG_ALERTS_SECRET_HEADER = "X-Cmux-Bug-Alerts-Secret";
const SLACK_NOTIFY_SEVERITIES = new Set(["error", "critical"]);

export async function POST(request: Request): Promise<Response> {
  return withApiRouteSpan(
    request,
    "/api/bug-alerts",
    { "cmux.subsystem": "bug-alerts", "cmux.bug_alert.operation": "notify" },
    async (span): Promise<Response> => {
      const secret = runtimeEnv("CMUX_BUG_ALERTS_SHARED_SECRET");
      if (secret && request.headers.get(BUG_ALERTS_SECRET_HEADER) !== secret) {
        return jsonResponse({ error: "unauthorized" }, 401);
      }

      const body = await readBoundedJsonObject(request, MAX_BUG_ALERT_REQUEST_BYTES);
      if (!body.ok) {
        return jsonResponse({ error: body.error }, body.error === "request_too_large" ? 413 : 400);
      }

      const parsed = parseBugAlert(body.value);
      if (!parsed.ok) {
        return jsonResponse({ error: parsed.error }, 400);
      }

      setSpanAttributes(span, {
        "cmux.bug_alert.event": parsed.alert.event,
        "cmux.bug_alert.severity": parsed.alert.severity,
        "cmux.bug_alert.source": parsed.alert.source,
        "cmux.bug_alert.error_kind": parsed.alert.errorKind,
      });

      if (!SLACK_NOTIFY_SEVERITIES.has(parsed.alert.severity)) {
        return jsonResponse({ ok: true, notified: false });
      }

      const webhookUrl = runtimeEnv("CMUX_BUG_ALERTS_WEBHOOK_URL");
      if (!webhookUrl) {
        return jsonResponse({ ok: true, notified: false });
      }

      try {
        const response = await fetch(webhookUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(bugAlertSlackPayload(parsed.alert)),
        });
        if (!response.ok) {
          recordSpanError(span, new Error(`bug alert webhook ${response.status}`));
          return jsonResponse({ error: "webhook_failed" }, 502);
        }
      } catch (error) {
        recordSpanError(span, error);
        return jsonResponse({ error: "webhook_failed" }, 502);
      }

      return jsonResponse({ ok: true, notified: true });
    },
  );
}

function runtimeEnv(name: "CMUX_BUG_ALERTS_SHARED_SECRET" | "CMUX_BUG_ALERTS_WEBHOOK_URL"): string | undefined {
  return process.env[name]?.trim() || undefined;
}
