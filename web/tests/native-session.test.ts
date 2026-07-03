import { describe, expect, test } from "bun:test";

process.env.SKIP_ENV_VALIDATION = "1";
process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY = "pk_test_key";
process.env.CLERK_SECRET_KEY = "sk_test_secret_key_that_is_long_enough_for_native_tokens";
process.env.CMUX_NATIVE_AUTH_SECRET = "native-test-secret-that-is-at-least-thirty-two-bytes";

const {
  mintNativeSessionTokenPair,
  refreshNativeSessionTokenPair,
  verifyNativeAuthToken,
} = await import("../services/auth/nativeSession");

describe("cmux native session tokens", () => {
  test("mints signed access and refresh tokens with normalized Clerk identity claims", () => {
    const tokens = mintNativeSessionTokenPair({
      userId: "user_123",
      displayName: "Dorsa",
      primaryEmail: "dorsa@example.com",
      imageURL: "https://img.example/dorsa.png",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected", " org_other ", "org_selected", ""],
    }, Math.floor(Date.now() / 1000));

    const access = verifyNativeAuthToken(tokens.accessToken);
    const refresh = verifyNativeAuthToken(tokens.refreshToken);

    expect(access).toMatchObject({
      kind: "access",
      userId: "user_123",
      displayName: "Dorsa",
      primaryEmail: "dorsa@example.com",
      imageURL: "https://img.example/dorsa.png",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected", "org_other"],
    });
    expect(refresh).toMatchObject({
      kind: "refresh",
      userId: "user_123",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected", "org_other"],
    });
    expect(access!.exp - access!.iat).toBe(15 * 60);
    expect(refresh!.exp - refresh!.iat).toBe(30 * 24 * 60 * 60);
    expect(access!.nonce).not.toBe(refresh!.nonce);
  });

  test("rejects tampered malformed and expired tokens", () => {
    const tokens = mintNativeSessionTokenPair({ userId: "user_123" });
    const parts = tokens.accessToken.split(".");
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    payload.userId = "attacker";
    const tamperedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");

    expect(verifyNativeAuthToken(`cmuxv1.${tamperedPayload}.${parts[2]}`)).toBeNull();
    expect(verifyNativeAuthToken("not-a-token")).toBeNull();

    const expired = mintNativeSessionTokenPair(
      { userId: "user_123" },
      Math.floor(Date.now() / 1000) - 31 * 24 * 60 * 60
    );
    expect(verifyNativeAuthToken(expired.accessToken)).toBeNull();
    expect(verifyNativeAuthToken(expired.refreshToken)).toBeNull();
  });

  test("refreshes only refresh tokens and preserves Clerk identity claims", () => {
    const original = mintNativeSessionTokenPair({
      userId: "user_123",
      displayName: "Dorsa",
      primaryEmail: "dorsa@example.com",
      imageURL: "https://img.example/dorsa.png",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected"],
    });

    expect(refreshNativeSessionTokenPair(original.accessToken)).toBeNull();

    const refreshed = refreshNativeSessionTokenPair(original.refreshToken);
    expect(refreshed).not.toBeNull();
    expect(refreshed!.accessToken).not.toBe(original.accessToken);
    expect(refreshed!.refreshToken).not.toBe(original.refreshToken);
    expect(verifyNativeAuthToken(refreshed!.accessToken)).toMatchObject({
      kind: "access",
      userId: "user_123",
      displayName: "Dorsa",
      primaryEmail: "dorsa@example.com",
      imageURL: "https://img.example/dorsa.png",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected"],
    });
  });
});
