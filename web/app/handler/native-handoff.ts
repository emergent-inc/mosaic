import { randomUUID } from "crypto";
import { NextRequest, NextResponse } from "next/server";

export const NATIVE_HANDOFF_COOKIE = "mosaic-native-auth-handoff";
export const NATIVE_HANDOFF_PARAM = "mosaic_auth_handoff";

export type NativeHandoff = {
  afterSignInURL: URL;
  nonce: string | null;
};

function canSetAutoHandoff(request: NextRequest): boolean {
  const fetchSite = request.headers.get("sec-fetch-site");
  return fetchSite === null || fetchSite === "none" || fetchSite === "same-origin" || fetchSite === "same-site";
}

function sameOriginURL(value: string, origin: string): URL | null {
  try {
    const url = new URL(value, origin);
    return url.origin === origin ? url : null;
  } catch {
    return null;
  }
}

export function validatedAfterSignInURL(value: string | null, request: NextRequest): URL | null {
  return validatedAfterSignInURLForOrigin(value, request.nextUrl.origin);
}

export function validatedAfterSignInURLForOrigin(value: string | null, origin: string): URL | null {
  if (!value) return null;

  const afterSignInURL = sameOriginURL(value, origin);
  if (!afterSignInURL || afterSignInURL.pathname !== "/handler/after-sign-in") {
    return null;
  }

  return afterSignInURL;
}

export function prepareNativeHandoff(request: NextRequest): NativeHandoff | null {
  const afterSignInURL = validatedAfterSignInURL(
    request.nextUrl.searchParams.get("after_auth_return_to"),
    request
  );
  if (!afterSignInURL) return null;

  const nativeReturnTo = afterSignInURL.searchParams.get("native_app_return_to");
  const shouldSetHandoff = canSetAutoHandoff(request) && nativeReturnTo?.includes("mosaic_auth_state") === true;
  let nonce: string | null = null;
  if (shouldSetHandoff) {
    nonce = randomUUID();
    afterSignInURL.searchParams.set(NATIVE_HANDOFF_PARAM, nonce);
  }

  return { afterSignInURL, nonce };
}

export function clerkSignInURL(request: NextRequest, afterSignInURL: URL): URL {
  return clerkSignInURLForOrigin(request.nextUrl.origin, afterSignInURL);
}

export function clerkSignInURLForOrigin(origin: string, afterSignInURL: URL): URL {
  const clerkURL = new URL("/sign-in", origin);
  clerkURL.searchParams.set("redirect_url", afterSignInURL.toString());
  return clerkURL;
}

export function nativeAccountSelectURL(request: NextRequest, afterSignInURL: URL): URL {
  const selectURL = new URL("/handler/native-account-select", request.nextUrl.origin);
  selectURL.searchParams.set("after_auth_return_to", afterSignInURL.toString());
  return selectURL;
}

export function redirectWithHandoffCookie(request: NextRequest, location: URL, nonce: string | null): NextResponse {
  const response = NextResponse.redirect(location);
  if (nonce) {
    response.cookies.set(NATIVE_HANDOFF_COOKIE, nonce, {
      httpOnly: true,
      maxAge: 10 * 60,
      path: "/handler/after-sign-in",
      sameSite: "lax",
      secure: request.nextUrl.protocol === "https:",
    });
  }
  return response;
}
