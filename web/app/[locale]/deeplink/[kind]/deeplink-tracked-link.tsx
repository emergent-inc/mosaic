"use client";

import posthog from "posthog-js";
import type { CSSProperties, ReactNode } from "react";
import { captureWebAcquisitionEvent } from "../../../lib/web-analytics";

type DeeplinkTrackedLinkProps = {
  readonly href: string;
  readonly event: string;
  readonly kind: string;
  readonly result: "open_native" | "download_fallback";
  readonly className?: string;
  readonly style?: CSSProperties;
  readonly children: ReactNode;
};

export function DeeplinkTrackedLink({
  href,
  event,
  kind,
  result,
  className,
  style,
  children,
}: DeeplinkTrackedLinkProps) {
  return (
    <a
      href={href}
      className={className}
      style={style}
      onClick={() => {
        const properties = { kind, result };
        posthog.capture(event, properties);
        if (event !== "cmuxterm_linking_started") {
          posthog.capture("cmuxterm_linking_started", properties);
        }
        captureWebAcquisitionEvent("web_deeplink_started", {
          entrypoint: "deeplink_page",
          result: result === "open_native" ? "started" : "failed",
          link_kind: kind,
          fallback_shown: result === "download_fallback",
        });
      }}
    >
      {children}
    </a>
  );
}
