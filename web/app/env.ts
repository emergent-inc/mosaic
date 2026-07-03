import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

// Trim at the runtimeEnv source so every consumer — including paths that
// run when validation is skipped (VERCEL_ENV === "preview") — sees clean
// values. A trailing newline in Vercel env vars has tripped Stack Auth's
// UUID parser and malformed the stack-refresh-<project-id> cookie key.
const trimEnv = (value: string | undefined): string | undefined =>
  typeof value === "string" ? value.trim() : value;

const skipEnvValidation =
  process.env.SKIP_ENV_VALIDATION === "1" ||
  process.env.VERCEL_ENV === "preview";
const allowPreviewStackPlaceholders = process.env.VERCEL_ENV === "preview";

const stackEnv = (
  value: string | undefined,
  fallback: string
): string | undefined => {
  const trimmed = trimEnv(value);
  if (trimmed) return trimmed;
  return allowPreviewStackPlaceholders ? fallback : undefined;
};

const clerkEnv = (
  value: string | undefined,
  fallback: string
): string | undefined => {
  const trimmed = trimEnv(value);
  if (trimmed) return trimmed;
  return allowPreviewStackPlaceholders ? fallback : undefined;
};

export const env = createEnv({
  server: {
    RESEND_API_KEY: z.string().min(1),
    CMUX_FEEDBACK_FROM_EMAIL: z.string().email(),
    CMUX_FEEDBACK_RATE_LIMIT_ID: z.string().min(1),
    STACK_SECRET_SERVER_KEY: z.string().min(1).optional(),
    CLERK_SECRET_KEY: z.string().min(1),
    CMUX_NATIVE_AUTH_SECRET: z.string().min(32).optional(),
    // APNs push (iOS notifications). Optional: the app boots without them; the
    // push route returns a clear "not configured" error until they are set.
    // CMUX_APNS_KEY_P8 holds the .p8 PEM (literal "\n" escapes are normalized
    // by the sender).
    CMUX_APNS_KEY_P8: z.string().min(1).optional(),
    CMUX_APNS_KEY_ID: z.string().min(1).optional(),
    CMUX_APNS_TEAM_ID: z.string().min(1).optional(),
    CMUX_PUSH_RATE_LIMIT_ID: z.string().min(1).optional(),
    // cmux Founder's Edition welcome email (Stripe webhook -> Resend). Optional:
    // the /api/stripe/founders-welcome route returns "not configured" until the
    // webhook signing secret is set. CMUX_FOUNDERS_FROM_EMAIL overrides the
    // sender (defaults to austin@emergent.inc) so the verified Resend domain can
    // change without a code edit.
    STRIPE_FOUNDERS_WEBHOOK_SECRET: z.string().min(1).optional(),
    CMUX_FOUNDERS_FROM_EMAIL: z.string().email().optional(),
    // Slack Incoming Webhook for the #website-waitlist channel. Optional: the
    // /api/waitlist route silently skips the Slack ping when it is unset.
    SLACK_WAITLIST_WEBHOOK_URL: z.string().url().optional(),
    // Slack-compatible webhook for high-signal app bug/error notifications.
    // Optional: /api/bug-alerts accepts and records the event but skips fan-out.
    CMUX_BUG_ALERTS_WEBHOOK_URL: z.string().url().optional(),
    // Optional shared secret required by /api/bug-alerts when configured.
    CMUX_BUG_ALERTS_SHARED_SECRET: z.string().min(1).optional(),
    // Public R2 base used by Mosaic download/update proxy routes. Example:
    // https://pub-xxxxxxxx.r2.dev
    MOSAIC_R2_PUBLIC_BASE_URL: z.string().url().optional(),
  },
  client: {
    NEXT_PUBLIC_STACK_PROJECT_ID: z.string().min(1).optional(),
    NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY: z.string().min(1).optional(),
    NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY: z.string().min(1),
    NEXT_PUBLIC_POSTHOG_KEY: z.string().min(1).optional(),
    NEXT_PUBLIC_POSTHOG_HOST: z.string().url().optional(),
    NEXT_PUBLIC_POSTHOG_UI_HOST: z.string().url().optional(),
  },
  runtimeEnv: {
    RESEND_API_KEY: trimEnv(process.env.RESEND_API_KEY),
    CMUX_FEEDBACK_FROM_EMAIL: trimEnv(process.env.CMUX_FEEDBACK_FROM_EMAIL),
    CMUX_FEEDBACK_RATE_LIMIT_ID: trimEnv(process.env.CMUX_FEEDBACK_RATE_LIMIT_ID),
    CMUX_APNS_KEY_P8: trimEnv(process.env.CMUX_APNS_KEY_P8),
    CMUX_APNS_KEY_ID: trimEnv(process.env.CMUX_APNS_KEY_ID),
    CMUX_APNS_TEAM_ID: trimEnv(process.env.CMUX_APNS_TEAM_ID),
    CMUX_PUSH_RATE_LIMIT_ID: trimEnv(process.env.CMUX_PUSH_RATE_LIMIT_ID),
    CLERK_SECRET_KEY: clerkEnv(
      process.env.CLERK_SECRET_KEY,
      "sk_test_preview_clerk_secret_key"
    ),
    CMUX_NATIVE_AUTH_SECRET: trimEnv(process.env.CMUX_NATIVE_AUTH_SECRET),
    STRIPE_FOUNDERS_WEBHOOK_SECRET: trimEnv(process.env.STRIPE_FOUNDERS_WEBHOOK_SECRET),
    CMUX_FOUNDERS_FROM_EMAIL: trimEnv(process.env.CMUX_FOUNDERS_FROM_EMAIL),
    SLACK_WAITLIST_WEBHOOK_URL: trimEnv(process.env.SLACK_WAITLIST_WEBHOOK_URL),
    CMUX_BUG_ALERTS_WEBHOOK_URL: trimEnv(process.env.CMUX_BUG_ALERTS_WEBHOOK_URL),
    CMUX_BUG_ALERTS_SHARED_SECRET: trimEnv(process.env.CMUX_BUG_ALERTS_SHARED_SECRET),
    MOSAIC_R2_PUBLIC_BASE_URL: trimEnv(process.env.MOSAIC_R2_PUBLIC_BASE_URL),
    NEXT_PUBLIC_STACK_PROJECT_ID: stackEnv(
      process.env.NEXT_PUBLIC_STACK_PROJECT_ID,
      "00000000-0000-4000-8000-000000000000"
    ),
    NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY: stackEnv(
      process.env.NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY,
      "preview-publishable-client-key"
    ),
    NEXT_PUBLIC_POSTHOG_KEY: trimEnv(process.env.NEXT_PUBLIC_POSTHOG_KEY),
    NEXT_PUBLIC_POSTHOG_HOST: trimEnv(process.env.NEXT_PUBLIC_POSTHOG_HOST),
    NEXT_PUBLIC_POSTHOG_UI_HOST: trimEnv(process.env.NEXT_PUBLIC_POSTHOG_UI_HOST),
    STACK_SECRET_SERVER_KEY: stackEnv(
      process.env.STACK_SECRET_SERVER_KEY,
      "preview-secret-server-key"
    ),
    NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY: clerkEnv(
      process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY,
      "pk_test_preview_clerk_publishable_key"
    ),
  },
  skipValidation: skipEnvValidation,
});
