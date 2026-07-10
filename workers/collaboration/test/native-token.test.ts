import { expect, test } from "bun:test";
import {
  bearerTokenFromRequest,
  claimsAuthorizeTeam,
  verifyNativeAccessToken,
} from "../src/native-token";

const SECRET = "test-native-secret";

async function mintToken(
  claims: Record<string, unknown>,
  secret = SECRET,
): Promise<string> {
  const payload = base64UrlEncode(JSON.stringify(claims));
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  return `mosaicv1.${payload}.${bytesToBase64Url(new Uint8Array(signature))}`;
}

function base64UrlEncode(value: string): string {
  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function futureExp(): number {
  return Math.floor(Date.now() / 1000) + 600;
}

function accessClaims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    kind: "access",
    userId: "user_1",
    displayName: "Alex",
    selectedTeamId: "org_1",
    teamIds: ["org_1", "org_2"],
    exp: futureExp(),
    ...overrides,
  };
}

test("verifyNativeAccessToken accepts a validly signed access token", async () => {
  const token = await mintToken(accessClaims());

  const claims = await verifyNativeAccessToken(token, SECRET);

  expect(claims).not.toBeNull();
  expect(claims?.userId).toBe("user_1");
  expect(claims?.displayName).toBe("Alex");
  expect(claims?.selectedTeamId).toBe("org_1");
  expect(claims?.teamIds).toEqual(["org_1", "org_2"]);
});

test("verifyNativeAccessToken rejects refresh tokens", async () => {
  const token = await mintToken(accessClaims({ kind: "refresh" }));

  expect(await verifyNativeAccessToken(token, SECRET)).toBeNull();
});

test("verifyNativeAccessToken rejects wrong secret, expiry, and tampering", async () => {
  const wrongSecret = await mintToken(accessClaims(), "some-other-secret");
  const expired = await mintToken(
    accessClaims({ exp: Math.floor(Date.now() / 1000) - 1 }),
  );
  const valid = await mintToken(accessClaims());
  const [prefix, , signature] = valid.split(".");
  const forgedPayload = base64UrlEncode(
    JSON.stringify(accessClaims({ userId: "user_stolen" })),
  );

  expect(await verifyNativeAccessToken(wrongSecret, SECRET)).toBeNull();
  expect(await verifyNativeAccessToken(expired, SECRET)).toBeNull();
  expect(
    await verifyNativeAccessToken(`${prefix}.${forgedPayload}.${signature}`, SECRET),
  ).toBeNull();
});

test("verifyNativeAccessToken rejects malformed tokens and missing claims", async () => {
  const missingUser = await mintToken(accessClaims({ userId: "" }));
  const missingExp = await mintToken({ kind: "access", userId: "user_1" });

  expect(await verifyNativeAccessToken("not-a-token", SECRET)).toBeNull();
  expect(await verifyNativeAccessToken("mosaicgrant1.abc.def", SECRET)).toBeNull();
  expect(await verifyNativeAccessToken("", SECRET)).toBeNull();
  expect(await verifyNativeAccessToken(missingUser, SECRET)).toBeNull();
  expect(await verifyNativeAccessToken(missingExp, SECRET)).toBeNull();
});

test("verifyNativeAccessToken drops non-string team ids", async () => {
  const token = await mintToken(accessClaims({ teamIds: ["org_1", 42, "", null] }));

  const claims = await verifyNativeAccessToken(token, SECRET);

  expect(claims?.teamIds).toEqual(["org_1"]);
});

test("claimsAuthorizeTeam allows member teams and the personal team", async () => {
  const token = await mintToken(accessClaims());
  const claims = await verifyNativeAccessToken(token, SECRET);
  if (claims === null) throw new Error("expected claims");

  expect(claimsAuthorizeTeam(claims, "org_1")).toBe(true);
  expect(claimsAuthorizeTeam(claims, "org_2")).toBe(true);
  expect(claimsAuthorizeTeam(claims, "user_1")).toBe(true);
  expect(claimsAuthorizeTeam(claims, "org_other")).toBe(false);
});

test("bearerTokenFromRequest extracts the bearer token", () => {
  const withToken = new Request("https://relay.test/", {
    headers: { authorization: "Bearer token-a" },
  });
  const empty = new Request("https://relay.test/", {
    headers: { authorization: "Bearer   " },
  });
  const bare = new Request("https://relay.test/");

  expect(bearerTokenFromRequest(withToken)).toBe("token-a");
  expect(bearerTokenFromRequest(empty)).toBeNull();
  expect(bearerTokenFromRequest(bare)).toBeNull();
});

export { mintToken };
