"use client";

import { useEffect } from "react";
import { captureWebAcquisitionEvent } from "../lib/web-analytics";

export function AuthAnalytics({ mode }: { readonly mode: "sign_in" | "sign_up" }) {
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    captureWebAcquisitionEvent(
      mode === "sign_in" ? "web_signin_started" : "web_signup_started",
      {
        entrypoint: params.has("redirect_url") ? "native_handoff" : "web_auth_page",
        result: "started",
        native_handoff_present: params.get("redirect_url")?.includes("native_app_return_to") ?? false,
      },
    );
  }, [mode]);

  return null;
}
