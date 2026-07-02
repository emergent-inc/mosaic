import { describe, expect, test } from "bun:test";

process.env.SKIP_ENV_VALIDATION = "1";
process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY = "pk_test_key";
process.env.CLERK_SECRET_KEY = "sk_test_secret_key_that_is_long_enough_for_native_tokens";
process.env.CMUX_NATIVE_AUTH_SECRET = "native-test-secret-that-is-at-least-thirty-two-bytes";

const { mintNativeSessionTokenPair } = await import("../services/auth/nativeSession");
const { verifyRequest } = await import("../services/vms/auth");

describe("VM auth with cmux native Clerk tokens", () => {
  test("accepts cmux native access tokens and resolves Clerk user/team claims", async () => {
    const tokens = mintNativeSessionTokenPair({
      userId: "user_clerk",
      displayName: "Clerk User",
      primaryEmail: "clerk@example.com",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected", "org_other"],
    });

    const user = await verifyRequest(
      new Request("https://cmux.test/api/vm?teamId=org_other", {
        headers: {
          authorization: `Bearer ${tokens.accessToken}`,
        },
      }),
      { requestedTeamId: "org_other" }
    );

    expect(user).toMatchObject({
      id: "user_clerk",
      displayName: "Clerk User",
      primaryEmail: "clerk@example.com",
      billingCustomerType: "team",
      billingTeamId: "org_other",
      selectedTeamId: "org_selected",
      teamIds: ["org_selected", "org_other"],
    });
  });

  test("rejects refresh tokens and malformed native tokens as request access credentials", async () => {
    const tokens = mintNativeSessionTokenPair({ userId: "user_clerk" });

    const refreshAsBearer = await verifyRequest(
      new Request("https://cmux.test/api/vm", {
        headers: { authorization: `Bearer ${tokens.refreshToken}` },
      }),
      { allowCookie: false }
    );
    expect(refreshAsBearer).toBeNull();

    const malformed = await verifyRequest(
      new Request("https://cmux.test/api/vm", {
        headers: { authorization: "Bearer cmuxv1.not.valid" },
      }),
      { allowCookie: false }
    );
    expect(malformed).toBeNull();
  });
});
