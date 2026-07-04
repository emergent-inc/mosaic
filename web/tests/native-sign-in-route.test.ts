import { describe, expect, test } from "bun:test";
import { NextRequest } from "next/server";

const { makeNativeSignInHandler } = await import("../app/handler/native-sign-in/route");

function nativeSignInRequest(fetchSite: string | null = "same-origin"): NextRequest {
  const afterSignIn = new URL("https://mosaic.test/handler/after-sign-in");
  afterSignIn.searchParams.set(
    "native_app_return_to",
    "mosaic-dev://auth-callback?mosaic_auth_state=state-123"
  );
  return new NextRequest(
    `https://mosaic.test/handler/native-sign-in?after_auth_return_to=${encodeURIComponent(afterSignIn.toString())}`,
    fetchSite === null ? undefined : { headers: { "sec-fetch-site": fetchSite } }
  );
}

const signedOutGET = makeNativeSignInHandler({
  getAuth: async () => ({ userId: null }),
});

const signedInGET = makeNativeSignInHandler({
  getAuth: async () => ({ userId: "user_1" }),
});

describe("native sign-in handoff route", () => {
  test("redirects signed-out browsers into Clerk sign-in and preserves native return state", async () => {
    const response = await signedOutGET(nativeSignInRequest());
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

  test("redirects signed-in browsers to the native account selector", async () => {
    const response = await signedInGET(nativeSignInRequest());
    expect(response.status).toBe(307);

    const location = new URL(response.headers.get("location")!);
    expect(location.pathname).toBe("/handler/native-account-select");
    const afterSignInURL = new URL(location.searchParams.get("after_auth_return_to")!);
    expect(afterSignInURL.pathname).toBe("/handler/after-sign-in");
    expect(afterSignInURL.searchParams.get("native_app_return_to")).toBe(
      "mosaic-dev://auth-callback?mosaic_auth_state=state-123"
    );
    expect(afterSignInURL.searchParams.get("mosaic_auth_handoff")).toBeTruthy();

    const cookie = response.headers.get("set-cookie");
    expect(cookie).toContain("mosaic-native-auth-handoff=");
    expect(cookie).toContain("Path=/handler/after-sign-in");
  });

  test("does not set auto-open handoff cookie for cross-site requests", async () => {
    const response = await signedOutGET(nativeSignInRequest("cross-site"));
    const location = new URL(response.headers.get("location")!);
    const redirectURL = new URL(location.searchParams.get("redirect_url")!);
    expect(redirectURL.searchParams.get("mosaic_auth_handoff")).toBeNull();
    expect(response.headers.get("set-cookie")).toBeNull();
  });

  test("rejects off-origin and non after-sign-in return targets", async () => {
    const offOrigin = await signedOutGET(
      new NextRequest(
        "https://mosaic.test/handler/native-sign-in?after_auth_return_to=https%3A%2F%2Fevil.example%2Fhandler%2Fafter-sign-in"
      )
    );
    expect(offOrigin.status).toBe(307);
    expect(offOrigin.headers.get("location")).toBe("https://mosaic.test/");

    const wrongPath = await signedOutGET(
      new NextRequest(
        "https://mosaic.test/handler/native-sign-in?after_auth_return_to=%2Fhandler%2Fnot-after-sign-in"
      )
    );
    expect(wrongPath.status).toBe(307);
    expect(wrongPath.headers.get("location")).toBe("https://mosaic.test/");
  });
});
