import { NextRequest, NextResponse } from "next/server";
import type { Locale } from "../../../i18n/routing";
import { locales, routing } from "../../../i18n/routing";
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

type ClerkUserLike = {
  id: string;
  fullName?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  primaryEmailAddress?: { emailAddress?: string | null } | null;
  emailAddresses?: readonly { emailAddress?: string | null }[];
};

type ClerkOrganizationMembershipLike = {
  organization?: { id?: string | null } | null;
};

type AfterSignInHandlerDependencies = {
  getAuth: () => Promise<ClerkAuthLike>;
  getUser: (userId: string) => Promise<ClerkUserLike | null>;
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
    body {
      align-items: center;
      background: #fff;
      color: #111;
      display: flex;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      justify-content: center;
      margin: 0;
      min-height: 100vh;
      padding: 24px;
    }
    main {
      max-width: 440px;
      text-align: center;
    }
    h1 {
      font-size: 24px;
      font-weight: 600;
      margin: 0 0 12px;
    }
    p {
      color: #555;
      line-height: 1.5;
      margin: 0 0 24px;
    }
    a {
      background: #111;
      border-radius: 8px;
      color: #fff;
      display: inline-block;
      font-size: 14px;
      font-weight: 500;
      padding: 10px 18px;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <main>
    <h1>${escapedTitle}</h1>
    <p>${escapedBody}</p>
    <a href="${escapedHref}">${escapedButton}</a>
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
    const tokens = mintNativeSessionTokenPair({
      userId: auth.userId,
      displayName: displayNameFor(user),
      primaryEmail: primaryEmailFor(user),
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

function displayNameFor(user: ClerkUserLike | null): string | null {
  if (!user) return null;
  if (user.fullName?.trim()) return user.fullName.trim();
  const joined = [user.firstName, user.lastName]
    .map((part) => part?.trim())
    .filter(Boolean)
    .join(" ");
  return joined || null;
}

function primaryEmailFor(user: ClerkUserLike | null): string | null {
  return user?.primaryEmailAddress?.emailAddress
    ?? user?.emailAddresses?.find((email) => email.emailAddress)?.emailAddress
    ?? null;
}

function uniqueStrings(values: readonly (string | undefined)[]): readonly string[] {
  return [...new Set(values.filter((value): value is string => typeof value === "string" && value.length > 0))];
}
