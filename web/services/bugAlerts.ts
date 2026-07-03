const MAX_ALERT_PROPERTIES = 32;
const MAX_KEY_LENGTH = 64;
const MAX_STRING_LENGTH = 160;

const ALLOWED_SEVERITIES = new Set(["info", "warning", "error", "critical"]);
const BLOCKED_KEY_FRAGMENTS = [
  "body",
  "command",
  "email",
  "file",
  "path",
  "prompt",
  "secret",
  "subtitle",
  "text",
  "title",
  "token",
  "url",
];

export type BugAlert = {
  readonly event: string;
  readonly severity: "info" | "warning" | "error" | "critical";
  readonly source: string;
  readonly errorKind: string;
  readonly properties: Record<string, string | number | boolean>;
};

export type BugAlertParseResult =
  | { readonly ok: true; readonly alert: BugAlert }
  | { readonly ok: false; readonly error: string };

export function parseBugAlert(payload: Record<string, unknown>): BugAlertParseResult {
  const event = boundedIdentifier(payload.event, 80);
  const source = boundedIdentifier(payload.source, 80);
  const errorKind = boundedIdentifier(payload.error_kind, 80);
  const severity = typeof payload.severity === "string" ? payload.severity : "";

  if (!event) return { ok: false, error: "missing_event" };
  if (!source) return { ok: false, error: "missing_source" };
  if (!errorKind) return { ok: false, error: "missing_error_kind" };
  if (!ALLOWED_SEVERITIES.has(severity)) return { ok: false, error: "invalid_severity" };

  const rawProperties =
    payload.properties && typeof payload.properties === "object" && !Array.isArray(payload.properties)
      ? (payload.properties as Record<string, unknown>)
      : {};

  return {
    ok: true,
    alert: {
      event,
      severity: severity as BugAlert["severity"],
      source,
      errorKind,
      properties: sanitizeProperties(rawProperties),
    },
  };
}

export function bugAlertSlackPayload(alert: BugAlert): { readonly text: string } {
  const propertyLines = Object.entries(alert.properties)
    .slice(0, 12)
    .map(([key, value]) => `- ${escapeSlack(key)}: \`${escapeSlack(String(value))}\``);
  const properties = propertyLines.length > 0 ? `\n${propertyLines.join("\n")}` : "";
  return {
    text:
      `:rotating_light: cmux ${escapeSlack(alert.severity)} bug alert\n` +
      `*Event:* \`${escapeSlack(alert.event)}\`\n` +
      `*Kind:* \`${escapeSlack(alert.errorKind)}\`\n` +
      `*Source:* \`${escapeSlack(alert.source)}\`` +
      properties,
  };
}

function sanitizeProperties(input: Record<string, unknown>): Record<string, string | number | boolean> {
  const output: Record<string, string | number | boolean> = {};
  for (const key of Object.keys(input).sort()) {
    if (Object.keys(output).length >= MAX_ALERT_PROPERTIES) break;
    if (!isSafeKey(key)) continue;
    const value = sanitizeValue(input[key]);
    if (value === null) continue;
    output[key] = value;
  }
  return output;
}

function boundedIdentifier(value: unknown, maxChars: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maxChars) return null;
  if (!/^[a-zA-Z0-9_.:-]+$/.test(trimmed)) return null;
  return trimmed;
}

function isSafeKey(key: string): boolean {
  if (!key || key.length > MAX_KEY_LENGTH) return false;
  const lower = key.toLowerCase();
  if (BLOCKED_KEY_FRAGMENTS.some((fragment) => lower.includes(fragment))) return false;
  return /^[a-zA-Z0-9_.$-]+$/.test(key);
}

function sanitizeValue(value: unknown): string | number | boolean | null {
  if (typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length <= MAX_STRING_LENGTH ? trimmed : trimmed.slice(0, MAX_STRING_LENGTH);
}

function escapeSlack(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
