import { createHmac } from "crypto";
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

// Forges a token whose payload is exactly `claims`, signed with the same HMAC
// scheme as the production minter. Used to reproduce tokens that predate a
// claim (e.g. a legacy token minted before `imageURL` existed).
function signLegacyToken(claims: Record<string, unknown>): string {
  const secret = process.env.CMUX_NATIVE_AUTH_SECRET!;
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const signature = createHmac("sha256", secret).update(payload).digest("base64url");
  return `cmuxv1.${payload}.${signature}`;
}

function baseLegacyClaims(kind: "access" | "refresh") {
  const now = Math.floor(Date.now() / 1000);
  return {
    kind,
    userId: "user_legacy",
    displayName: "Legacy User",
    primaryEmail: "legacy@example.com",
    // NOTE: no `imageURL` field — this is the pre-imageURL token shape.
    selectedTeamId: "org_legacy",
    teamIds: ["org_legacy"],
    exp: now + 60 * 60,
    iat: now,
    nonce: "legacy-nonce",
  };
}

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

  test("normalizes a missing or null imageURL to null when minting", () => {
    const withoutImage = mintNativeSessionTokenPair({
      userId: "user_123",
      displayName: "Dorsa",
    });
    expect(verifyNativeAuthToken(withoutImage.accessToken)!.imageURL).toBeNull();

    const withNullImage = mintNativeSessionTokenPair({
      userId: "user_123",
      imageURL: null,
    });
    expect(verifyNativeAuthToken(withNullImage.accessToken)!.imageURL).toBeNull();
  });

  // Legacy native tokens minted before the `imageURL` claim existed are still
  // accepted so the user stays signed in. The browser sign-in handoff is the
  // authoritative moment where Clerk profile data is captured; refresh preserves
  // the signed-in token claims it is handed.
  test("accepts legacy tokens without an imageURL claim and reports null", () => {
    const legacyAccess = signLegacyToken(baseLegacyClaims("access"));

    const claims = verifyNativeAuthToken(legacyAccess);
    expect(claims).not.toBeNull();
    expect(claims!.userId).toBe("user_legacy");
    expect(claims!.imageURL).toBeNull();
  });

  test("pure refresh helper preserves a legacy refresh token imageURL null", () => {
    const legacyRefresh = signLegacyToken(baseLegacyClaims("refresh"));

    const refreshed = refreshNativeSessionTokenPair(legacyRefresh);
    expect(refreshed).not.toBeNull();

    const refreshedAccess = verifyNativeAuthToken(refreshed!.accessToken);
    expect(refreshedAccess).toMatchObject({
      kind: "access",
      userId: "user_legacy",
      displayName: "Legacy User",
    });
    expect(refreshedAccess!.imageURL).toBeNull();
  });
});
