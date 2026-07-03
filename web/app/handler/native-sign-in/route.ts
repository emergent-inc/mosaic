import { randomUUID } from "crypto";
import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

const NATIVE_HANDOFF_COOKIE = "mosaic-native-auth-handoff";
const NATIVE_HANDOFF_PARAM = "mosaic_auth_handoff";

function canSetAutoHandoff(request: NextRequest): boolean {
  const fetchSite = request.headers.get("sec-fetch-site");
  return fetchSite === null || fetchSite === "none" || fetchSite === "same-origin" || fetchSite === "same-site";
}

function sameOriginURL(value: string, request: NextRequest): URL | null {
  try {
    const url = new URL(value, request.nextUrl.origin);
    return url.origin === request.nextUrl.origin ? url : null;
  } catch {
    return null;
  }
}

export function GET(request: NextRequest) {
  const afterAuthReturnTo = request.nextUrl.searchParams.get("after_auth_return_to");
  if (!afterAuthReturnTo) return NextResponse.redirect(new URL("/sign-in", request.url));

  const afterSignInURL = sameOriginURL(afterAuthReturnTo, request);
  if (!afterSignInURL || afterSignInURL.pathname !== "/handler/after-sign-in") {
    return NextResponse.redirect(new URL("/", request.url));
  }

  const nativeReturnTo = afterSignInURL.searchParams.get("native_app_return_to");
  const shouldSetHandoff = canSetAutoHandoff(request) && nativeReturnTo?.includes("mosaic_auth_state") === true;
  let nonce: string | null = null;
  if (shouldSetHandoff) {
    nonce = randomUUID();
    afterSignInURL.searchParams.set(NATIVE_HANDOFF_PARAM, nonce);
  }

  const clerkSignInURL = new URL("/sign-in", request.nextUrl.origin);
  clerkSignInURL.searchParams.set("redirect_url", afterSignInURL.toString());
  const response = NextResponse.redirect(clerkSignInURL);
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
