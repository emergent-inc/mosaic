import { describe, expect, test } from "bun:test";
import { NextRequest } from "next/server";

const { GET } = await import("../app/handler/native-sign-in/route");

describe("native sign-in handoff route", () => {
  test("redirects into Clerk sign-in and preserves native return state", () => {
    const afterSignIn = new URL("https://cmux.test/handler/after-sign-in");
    afterSignIn.searchParams.set(
      "native_app_return_to",
      "mosaic-dev://auth-callback?mosaic_auth_state=state-123"
    );
    const request = new NextRequest(
      `https://cmux.test/handler/native-sign-in?after_auth_return_to=${encodeURIComponent(afterSignIn.toString())}`,
      { headers: { "sec-fetch-site": "same-origin" } }
    );

    const response = GET(request);
    expect(response.status).toBe(307);

    const location = new URL(response.headers.get("location")!);
    expect(location.pathname).toBe("/sign-in");
    const redirectURL = new URL(location.searchParams.get("redirect_url")!);
    expect(redirectURL.pathname).toBe("/handler/after-sign-in");
    expect(redirectURL.searchParams.get("native_app_return_to")).toBe(
      "mosaic-dev://auth-callback?mosaic_auth_state=state-123"
    );
    const handoff = redirectURL.searchParams.get("mosaic_auth_handoff");
    expect(handoff).toBeTruthy();

    const cookie = response.headers.get("set-cookie");
    expect(cookie).toContain("mosaic-native-auth-handoff=");
    expect(cookie).toContain("Path=/handler/after-sign-in");
    expect(cookie).toContain("HttpOnly");
    expect(cookie).toContain("SameSite=lax");
  });

  test("does not set auto-open handoff cookie for cross-site requests", () => {
    const afterSignIn = new URL("https://cmux.test/handler/after-sign-in");
    afterSignIn.searchParams.set(
      "native_app_return_to",
      "mosaic-dev://auth-callback?mosaic_auth_state=state-123"
    );
    const request = new NextRequest(
      `https://cmux.test/handler/native-sign-in?after_auth_return_to=${encodeURIComponent(afterSignIn.toString())}`,
      { headers: { "sec-fetch-site": "cross-site" } }
    );

    const response = GET(request);
    const location = new URL(response.headers.get("location")!);
    const redirectURL = new URL(location.searchParams.get("redirect_url")!);
    expect(redirectURL.searchParams.get("mosaic_auth_handoff")).toBeNull();
    expect(response.headers.get("set-cookie")).toBeNull();
  });

  test("rejects off-origin and non after-sign-in return targets", () => {
    const offOrigin = GET(
      new NextRequest(
        "https://cmux.test/handler/native-sign-in?after_auth_return_to=https%3A%2F%2Fevil.example%2Fhandler%2Fafter-sign-in"
      )
    );
    expect(offOrigin.status).toBe(307);
    expect(offOrigin.headers.get("location")).toBe("https://cmux.test/");

    const wrongPath = GET(
      new NextRequest(
        "https://cmux.test/handler/native-sign-in?after_auth_return_to=%2Fhandler%2Fnot-after-sign-in"
      )
    );
    expect(wrongPath.status).toBe(307);
    expect(wrongPath.headers.get("location")).toBe("https://cmux.test/");
  });
});
