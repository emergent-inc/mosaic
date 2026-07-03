"use client";

import posthog from "posthog-js";

type WebAnalyticsProperties = Record<string, string | number | boolean | null | undefined>;

const blockedPropertyKeyFragments = [
  "body",
  "command",
  "content",
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

export function captureWebAcquisitionEvent(
  event: string,
  properties: WebAnalyticsProperties = {},
) {
  posthog.capture(event, sanitizeWebAnalyticsProperties({
    feature_area: "web",
    platform: "web",
    ...properties,
  }));
}

function sanitizeWebAnalyticsProperties(properties: WebAnalyticsProperties) {
  const sanitized: Record<string, string | number | boolean | null> = {};
  for (const [key, value] of Object.entries(properties)) {
    if (!isSafePropertyKey(key) || value === undefined) continue;
    sanitized[key] = typeof value === "string" && value.length > 256
      ? value.slice(0, 256)
      : value;
  }
  return sanitized;
}

function isSafePropertyKey(key: string) {
  if (!key || key.length > 72) return false;
  const lowerKey = key.toLowerCase();
  if (blockedPropertyKeyFragments.some((fragment) => lowerKey.includes(fragment))) {
    return false;
  }
  return /^[A-Za-z0-9_$.-]+$/.test(key);
}
