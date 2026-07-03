"use client";

import posthog from "posthog-js";
import type { CSSProperties, ReactNode } from "react";

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
      }}
    >
      {children}
    </a>
  );
}
