import { NextRequest, NextResponse } from "next/server";
import type { Locale } from "../../../i18n/routing";
import { locales, routing } from "../../../i18n/routing";
import { nativeIdentityClaimsFor, type ClerkUserIdentityLike } from "../../../services/auth/clerkIdentity";
import { mintNativeSessionTokenPair } from "../../../services/auth/nativeSession";

const NATIVE_SCHEME = "mosaic://";
const NATIVE_SCHEMES = new Set(["mosaic", "mosaic-nightly"]);
const NATIVE_HANDOFF_COOKIE = "mosaic-native-auth-handoff";
const NATIVE_HANDOFF_PARAM = "mosaic_auth_handoff";

type AfterSignInMessages = {
  title: string;
  body: string;
  button: string;
};

type LocalizedAfterSignInMessages = {
  locale: Locale;
  messages: AfterSignInMessages;
};

type CookieStore = {
  get: (name: string) => { value: string } | undefined;
  getAll: () => { name: string; value: string }[];
};

type ClerkAuthLike = {
  userId: string | null;
  orgId?: string | null;
};

type ClerkOrganizationMembershipLike = {
  organization?: { id?: string | null } | null;
};

type AfterSignInHandlerDependencies = {
  getAuth: () => Promise<ClerkAuthLike>;
  getUser: (userId: string) => Promise<ClerkUserIdentityLike | null>;
  listMemberships?: (userId: string) => Promise<readonly ClerkOrganizationMembershipLike[]>;
  getCookieStore: () => Promise<CookieStore>;
};

function isLocalRequest(request: NextRequest): boolean {
  const hostHeader = request.headers.get("host");
  const host = (hostHeader?.split(":")[0] ?? request.nextUrl.hostname).toLowerCase();
  return host === "localhost" || host === "127.0.0.1" || host === "::1";
}

function localAllowedNativeSchemes(): Set<string> {
  const values = [
    process.env.CMUX_AUTH_CALLBACK_SCHEME,
    process.env.CMUX_ALLOWED_NATIVE_CALLBACK_SCHEMES,
    process.env.CMUX_DEV_NATIVE_CALLBACK_SCHEMES,
  ];
  const schemes = new Set<string>();
  for (const value of values) {
    for (const raw of value?.split(/[\s,]+/) ?? []) {
      const scheme = raw.trim().replace(/:\/\/.*$/, "").replace(/:$/, "");
      if (/^mosaic-dev-[a-z0-9-]+$/.test(scheme)) schemes.add(scheme);
    }
  }
  return schemes;
}

function isAllowedNativeReturnTo(href: string, request: NextRequest): boolean {
  try {
    const url = new URL(href);
    if (url.hostname !== "auth-callback") return false;
    if (url.pathname !== "" && url.pathname !== "/") return false;
    const scheme = url.protocol.replace(":", "");
    if (NATIVE_SCHEMES.has(scheme)) return true;
    if (scheme === "mosaic-dev") return isLocalRequest(request);
    return isLocalRequest(request) && localAllowedNativeSchemes().has(scheme);
  } catch {
    return false;
  }
}

function buildNativeHref(
  baseHref: string | null,
  refreshToken: string | undefined,
  accessToken: string | undefined
): string | null {
  if (!refreshToken || !accessToken) return baseHref;
  const href = baseHref ?? `${NATIVE_SCHEME}auth-callback`;
  try {
    const url = new URL(href);
    url.searchParams.set("mosaic_refresh", refreshToken);
    url.searchParams.set("mosaic_access", accessToken);
    return url.toString();
  } catch {
    return `${NATIVE_SCHEME}auth-callback?mosaic_refresh=${encodeURIComponent(refreshToken)}&mosaic_access=${encodeURIComponent(accessToken)}`;
  }
}

function hasAuthState(href: string): boolean {
  try {
    return new URL(href).searchParams.has("mosaic_auth_state");
  } catch {
    return false;
  }
}

function verifiedAutoOpen(
  request: NextRequest,
  cookieStore: { get: (name: string) => { value: string } | undefined },
  nativeReturnTo: string
): boolean {
  if (!hasAuthState(nativeReturnTo)) return false;
  const handoffNonce = request.nextUrl.searchParams.get(NATIVE_HANDOFF_PARAM);
  if (!handoffNonce) return false;
  return cookieStore.get(NATIVE_HANDOFF_COOKIE)?.value === handoffNonce;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function preferredLocale(request: NextRequest): Locale {
  const accepted = request.headers.get("accept-language") ?? "";
  const requested = accepted
    .split(",")
    .map((part) => part.split(";")[0]?.trim())
    .filter(Boolean);
  for (const language of requested) {
    const exact = locales.find((locale) => locale.toLowerCase() === language.toLowerCase());
    if (exact) return exact;
    const base = language.split("-")[0]?.toLowerCase();
    const baseMatch = locales.find((locale) => locale.toLowerCase().split("-")[0] === base);
    if (baseMatch) return baseMatch;
  }
  return routing.defaultLocale;
}

async function afterSignInMessages(request: NextRequest): Promise<LocalizedAfterSignInMessages> {
  const locale = preferredLocale(request);
  const messages = (await import(`../../../messages/${locale}.json`)).default as {
    afterSignIn?: AfterSignInMessages;
  };
  if (!messages.afterSignIn) {
    throw new Error(`Missing afterSignIn messages for locale ${locale}`);
  }
  return {
    locale,
    messages: messages.afterSignIn,
  };
}

function nativeReturnResponse(
  href: string,
  localized: LocalizedAfterSignInMessages,
  autoOpen: boolean
): NextResponse {
  const { locale, messages } = localized;
  const escapedHref = escapeHtml(href);
  const scriptHref = JSON.stringify(href).replaceAll("<", "\\u003c");
  const escapedTitle = escapeHtml(messages.title);
  const escapedBody = escapeHtml(messages.body);
  const escapedButton = escapeHtml(messages.button);
  const bodyHTML = escapedBody ? `    <p>${escapedBody}</p>\n` : "";
  const autoOpenScript = autoOpen
    ? `  <script>\n    window.location.replace(${scriptHref});\n  </script>\n`
    : "";
  const response = new NextResponse(
    `<!doctype html>
<html lang="${escapeHtml(locale)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapedTitle}</title>
  <style>
    :root {
      color-scheme: dark;
      --background: #0a0a0a;
      --foreground: #ffffff;
      --muted: #a3a3a3;
      --border: rgba(255, 255, 255, 0.1);
      --card: #0f0f0f;
    }
    * {
      box-sizing: border-box;
    }
    body {
      align-items: center;
      background: var(--background);
      color: var(--foreground);
      display: flex;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      justify-content: center;
      margin: 0;
      min-height: 100vh;
      padding: 24px;
    }
    main {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 24px;
      box-shadow: none;
      max-width: 440px;
      padding: 40px;
      text-align: center;
      width: 100%;
    }
    h1 {
      font-size: 28px;
      font-weight: 650;
      letter-spacing: -0.04em;
      margin: 0 0 12px;
    }
    p {
      color: var(--muted);
      font-size: 15px;
      line-height: 1.5;
      margin: 0 0 28px;
    }
    a {
      background: #171717;
      border: 1px solid var(--border);
      border-radius: 10px;
      box-shadow: none;
      color: var(--foreground);
      display: inline-block;
      font-size: 14px;
      font-weight: 600;
      padding: 11px 18px;
      text-decoration: none;
      transition: background 120ms ease, transform 120ms ease;
    }
    a:hover {
      background: #1f1f1f;
      transform: translateY(-1px);
    }
    a:focus-visible {
      outline: 2px solid rgba(255, 255, 255, 0.35);
      outline-offset: 3px;
    }
    @media (max-width: 480px) {
      main {
        border-radius: 18px;
        padding: 32px 24px;
      }
      h1 {
        font-size: 24px;
      }
    }
  </style>
</head>
<body>
  <main>
    <h1>${escapedTitle}</h1>
${bodyHTML}    <a href="${escapedHref}">${escapedButton}</a>
  </main>
${autoOpenScript}
</body>
</html>`,
    {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    }
  );
  if (autoOpen) {
    response.cookies.set(NATIVE_HANDOFF_COOKIE, "", {
      httpOnly: true,
      maxAge: 0,
      path: "/handler/after-sign-in",
      sameSite: "lax",
      secure: requestIsSecure(),
    });
  }
  return response;
}

function requestIsSecure(): boolean {
  return process.env.NODE_ENV === "production";
}

export function makeAfterSignInHandler(dependencies: AfterSignInHandlerDependencies) {
  return async function GET(request: NextRequest) {
    const localizedMessages = await afterSignInMessages(request);
    const cookieStore = await dependencies.getCookieStore();
    const auth = await dependencies.getAuth();
    if (!auth.userId) {
      return NextResponse.redirect(new URL("/sign-in", request.url));
    }

    const user = await dependencies.getUser(auth.userId);
    const memberships = dependencies.listMemberships
      ? await dependencies.listMemberships(auth.userId)
      : [];
    const teamIds = uniqueStrings([
      auth.orgId ?? undefined,
      ...memberships.map((membership) => membership.organization?.id ?? undefined),
    ]);
    const identity = nativeIdentityClaimsFor(user);
    const tokens = mintNativeSessionTokenPair({
      userId: auth.userId,
      displayName: identity.displayName,
      primaryEmail: identity.primaryEmail,
      imageURL: identity.imageURL,
      selectedTeamId: auth.orgId ?? teamIds[0] ?? null,
      teamIds,
    });

    const nativeReturnTo = request.nextUrl.searchParams.get("native_app_return_to");
    if (
      nativeReturnTo !== null
    ) {
      if (isAllowedNativeReturnTo(nativeReturnTo, request)) {
        const href = buildNativeHref(nativeReturnTo, tokens.refreshToken, tokens.accessToken);
        const autoOpen = verifiedAutoOpen(request, cookieStore, nativeReturnTo);
        if (href) {
          return nativeReturnResponse(href, localizedMessages, autoOpen);
        }
      }
      return NextResponse.redirect(new URL("/", request.url));
    }

    const afterAuth = request.nextUrl.searchParams.get("after_auth_return_to");
    if (afterAuth && afterAuth.startsWith("/") && !afterAuth.startsWith("//")) {
      return NextResponse.redirect(new URL(afterAuth, request.url));
    }

    const fallback = buildNativeHref(null, tokens.refreshToken, tokens.accessToken);
    if (fallback) return nativeReturnResponse(fallback, localizedMessages, false);

    return NextResponse.redirect(new URL("/", request.url));
  };
}

function uniqueStrings(values: readonly (string | undefined)[]): readonly string[] {
  return [...new Set(values.filter((value): value is string => typeof value === "string" && value.length > 0))];
}
