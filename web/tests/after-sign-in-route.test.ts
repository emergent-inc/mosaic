import { beforeEach, describe, expect, mock, test } from "bun:test";
import { NextRequest } from "next/server";

process.env.SKIP_ENV_VALIDATION = "1";
process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY = "pk_test_key";
process.env.CLERK_SECRET_KEY = "sk_test_secret_key_that_is_long_enough_for_native_tokens";
process.env.CMUX_NATIVE_AUTH_SECRET = "native-test-secret-that-is-at-least-thirty-two-bytes";

const HANDOFF_COOKIE = "mosaic-native-auth-handoff";
let handoffCookie: string | undefined;
let userId: string | null;
const getUser = mock(async (...args: unknown[]) => {
  const id = args[0] as string;
  return {
    id,
    fullName: "Test User",
    imageUrl: "https://img.example/test-user.png",
    primaryEmailAddress: { emailAddress: "test@example.com" },
  };
});

const { makeAfterSignInHandler } = await import("../app/handler/after-sign-in/handler");
const { verifyNativeAuthToken } = await import("../services/auth/nativeSession");

const GET = makeAfterSignInHandler({
  getAuth: async () => ({ userId, orgId: "org-1" }),
  getUser: async (id) => getUser(id) as Promise<{
    id: string;
    fullName: string;
    imageUrl: string;
    primaryEmailAddress: { emailAddress: string };
  }>,
  getCookieStore: async () => ({
    get: (name: string) => {
      if (name === HANDOFF_COOKIE && handoffCookie) return { value: handoffCookie };
      return undefined;
    },
    getAll: () => [],
  }),
});

function signInRequest(nativeReturnTo: string, handoffNonce: string): NextRequest {
  const encodedReturnTo = encodeURIComponent(nativeReturnTo);
  const encodedNonce = encodeURIComponent(handoffNonce);
  return new NextRequest(
    `https://cmux.test/handler/after-sign-in?native_app_return_to=${encodedReturnTo}&mosaic_auth_handoff=${encodedNonce}`,
    {
      headers: {
        "accept-language": "en",
      },
    }
  );
}

function returnHref(html: string): string {
  const match = html.match(/<a href="([^"]+)">Open Mosaic again<\/a>/);
  expect(match).toBeTruthy();
  return match![1].replaceAll("&amp;", "&");
}

describe("after sign-in native handoff", () => {
  beforeEach(() => {
    handoffCookie = undefined;
    userId = "user_1";
  });

  test("keeps a fallback page for verified native auto-open handoffs", async () => {
    handoffCookie = "handoff-nonce";
    const nativeReturnTo = "mosaic://auth-callback?mosaic_auth_state=state-123";

    const response = await GET(signInRequest(nativeReturnTo, "handoff-nonce"));

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    const html = await response.text();
    expect(html).toContain("Mosaic opened, you may close this tab");
    expect(html).toContain("Open Mosaic again");
    expect(html).toContain("window.location.replace");
    expect(html).not.toContain("http-equiv=\"refresh\"");

    const callbackURL = new URL(returnHref(html));
    expect(callbackURL.protocol).toBe("mosaic:");
    expect(callbackURL.hostname).toBe("auth-callback");
    expect(callbackURL.searchParams.get("mosaic_auth_state")).toBe("state-123");
    expect(callbackURL.searchParams.get("mosaic_refresh")).toStartWith("cmuxv1.");
    expect(callbackURL.searchParams.get("mosaic_access")).toStartWith("cmuxv1.");
    const accessClaims = verifyNativeAuthToken(callbackURL.searchParams.get("mosaic_access")!);
    const refreshClaims = verifyNativeAuthToken(callbackURL.searchParams.get("mosaic_refresh")!);
    expect(accessClaims).toMatchObject({
      kind: "access",
      userId: "user_1",
      displayName: "Test User",
      primaryEmail: "test@example.com",
      imageURL: "https://img.example/test-user.png",
      selectedTeamId: "org-1",
      teamIds: ["org-1"],
    });
    expect(refreshClaims).toMatchObject({
      kind: "refresh",
      userId: "user_1",
      imageURL: "https://img.example/test-user.png",
      selectedTeamId: "org-1",
    });
    const setCookie = response.headers.get("set-cookie");
    expect(setCookie).toContain(`${HANDOFF_COOKIE}=;`);
    expect(setCookie).toContain("Max-Age=0");
    expect(setCookie).toContain("Path=/handler/after-sign-in");
  });

  test("keeps the manual return page when the handoff nonce is not verified", async () => {
    handoffCookie = "different-nonce";
    const nativeReturnTo = "mosaic://auth-callback?mosaic_auth_state=state-123";

    const response = await GET(signInRequest(nativeReturnTo, "handoff-nonce"));

    expect(response.status).toBe(200);
    const html = await response.text();
    expect(html).toContain("Mosaic opened, you may close this tab");
    expect(html).toContain("Open Mosaic again");
    expect(html).not.toContain("window.location.replace");
    expect(returnHref(html)).toContain("mosaic://auth-callback");
  });

  test("redirects unauthenticated users to sign in", async () => {
    handoffCookie = "handoff-nonce";
    userId = null;
    const nativeReturnTo = "mosaic://auth-callback?mosaic_auth_state=state-123";

    const response = await GET(signInRequest(nativeReturnTo, "handoff-nonce"));

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("https://cmux.test/sign-in");
  });
});
