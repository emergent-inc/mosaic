"use client";

import posthog from "posthog-js";
import { PostHogProvider as PHProvider } from "posthog-js/react";

const posthogProjectKey = process.env.NEXT_PUBLIC_POSTHOG_KEY
  ?? "phc_rRRqoNMdWb5ikbnHwC7EXWKBmYY7VvKJVCLaDqTm97ep";

if (typeof window !== "undefined") {
  posthog.init(posthogProjectKey, {
    api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com",
    ui_host: process.env.NEXT_PUBLIC_POSTHOG_UI_HOST ?? "https://us.posthog.com",
    person_profiles: "identified_only",
    capture_pageview: true,
    capture_pageleave: true,
    autocapture: true,
    capture_exceptions: true,
    capture_dead_clicks: true,
    rageclick: {
      click_count: 3,
      timeout_ms: 1000,
    },
    session_recording: {
      maskAllInputs: true,
      maskInputOptions: {
        password: true,
        email: true,
      },
    },
  });
}

export function PostHogProvider({ children }: { children: React.ReactNode }) {
  return (
    <PHProvider client={posthog}>
      {children}
    </PHProvider>
  );
}
