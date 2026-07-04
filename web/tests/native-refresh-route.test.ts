import { describe, expect, test } from "bun:test";

process.env.SKIP_ENV_VALIDATION = "1";
process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY = "pk_test_key";
process.env.CLERK_SECRET_KEY = "sk_test_secret_key_that_is_long_enough_for_native_tokens";
process.env.CMUX_NATIVE_AUTH_SECRET = "native-test-secret-that-is-at-least-thirty-two-bytes";

const { makeNativeRefreshHandler } = await import("../app/api/auth/native/refresh/route");
const {
  mintNativeSessionTokenPair,
  verifyNativeAuthToken,
} = await import("../services/auth/nativeSession");

describe("native auth refresh route", () => {
  test("hydrates refreshed native tokens with the current Clerk profile image", async () => {
    const original = mintNativeSessionTokenPair({
      userId: "user_legacy",
      displayName: "Legacy User",
      primaryEmail: "legacy@example.com",
      imageURL: null,
      selectedTeamId: "org_legacy",
      teamIds: ["org_legacy"],
    });
    const POST = makeNativeRefreshHandler({
      getUser: async (userId) => ({
        id: userId,
        fullName: "  Ada Lovelace  ",
        imageUrl: "  https://img.example/ada.png  ",
        primaryEmailAddress: { emailAddress: "ada@example.com" },
      }),
    });

    const response = await POST(new Request("https://cmux.test/api/auth/native/refresh", {
      method: "POST",
      headers: {
        "X-Mosaic-Refresh-Token": original.refreshToken,
      },
    }));

    expect(response.status).toBe(200);
    const body = await response.json() as { accessToken: string; refreshToken: string };
    expect(verifyNativeAuthToken(body.accessToken)).toMatchObject({
      kind: "access",
      userId: "user_legacy",
      displayName: "Ada Lovelace",
      primaryEmail: "ada@example.com",
      imageURL: "https://img.example/ada.png",
      selectedTeamId: "org_legacy",
      teamIds: ["org_legacy"],
    });
    expect(verifyNativeAuthToken(body.refreshToken)).toMatchObject({
      kind: "refresh",
      userId: "user_legacy",
      imageURL: "https://img.example/ada.png",
    });
  });

  test("preserves team and workspace claims while replacing stale identity claims", async () => {
    const original = mintNativeSessionTokenPair({
      userId: "user_legacy",
      displayName: "Old Name",
      primaryEmail: "old@example.com",
      imageURL: null,
      selectedTeamId: "org_team",
      teamIds: ["org_team", "org_other"],
      teamWorkspaces: [{
        id: "org_team",
        workspaceType: "team",
        mosaicPlan: "team",
        useType: "commercial",
        billingStatus: "active",
        vmBillingPlanId: "team",
      }],
    });
    const POST = makeNativeRefreshHandler({
      getUser: async (userId) => ({
        id: userId,
        fullName: "Fresh Account Name",
        imageUrl: "https://img.example/fresh.png",
        primaryEmailAddress: { emailAddress: "fresh@example.com" },
      }),
    });

    const response = await POST(new Request("https://cmux.test/api/auth/native/refresh", {
      method: "POST",
      body: JSON.stringify({ refreshToken: original.refreshToken }),
    }));

    expect(response.status).toBe(200);
    const body = await response.json() as { accessToken: string; refreshToken: string };
    const access = verifyNativeAuthToken(body.accessToken);
    const refresh = verifyNativeAuthToken(body.refreshToken);
    for (const claims of [access, refresh]) {
      expect(claims).toMatchObject({
        userId: "user_legacy",
        displayName: "Fresh Account Name",
        primaryEmail: "fresh@example.com",
        imageURL: "https://img.example/fresh.png",
        selectedTeamId: "org_team",
        teamIds: ["org_team", "org_other"],
        teamWorkspaces: [{
          id: "org_team",
          workspaceType: "team",
          mosaicPlan: "team",
          useType: "commercial",
          billingStatus: "active",
          vmBillingPlanId: "team",
        }],
      });
    }
  });

  test("continues to accept the legacy refresh header name", async () => {
    const original = mintNativeSessionTokenPair({
      userId: "user_legacy",
      imageURL: null,
    });
    const POST = makeNativeRefreshHandler({
      getUser: async (userId) => ({
        id: userId,
        fullName: "Grace Hopper",
        imageUrl: "https://img.example/grace.png",
      }),
    });

    const response = await POST(new Request("https://cmux.test/api/auth/native/refresh", {
      method: "POST",
      headers: {
        "X-Cmux-Refresh-Token": original.refreshToken,
      },
    }));

    expect(response.status).toBe(200);
  });

  test("rejects missing invalid and access-token refresh credentials without loading Clerk", async () => {
    let clerkLoads = 0;
    const POST = makeNativeRefreshHandler({
      getUser: async (userId) => {
        clerkLoads += 1;
        return { id: userId };
      },
    });
    const accessOnly = mintNativeSessionTokenPair({ userId: "user_legacy" }).accessToken;

    for (const request of [
      new Request("https://cmux.test/api/auth/native/refresh", { method: "POST" }),
      new Request("https://cmux.test/api/auth/native/refresh", {
        method: "POST",
        headers: { "X-Mosaic-Refresh-Token": "not-a-token" },
      }),
      new Request("https://cmux.test/api/auth/native/refresh", {
        method: "POST",
        headers: { "X-Mosaic-Refresh-Token": accessOnly },
      }),
    ]) {
      const response = await POST(request);
      expect(response.status).toBe(401);
      expect(await response.json()).toEqual({ error: "unauthorized" });
    }
    expect(clerkLoads).toBe(0);
  });
});
