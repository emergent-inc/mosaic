import { expect, test } from "bun:test";
import { verifyCollabGrant, grantFromRequest } from "../src/grant";

const SECRET = "test-collab-secret";

async function mintGrant(
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
  return `mosaicgrant1.${payload}.${bytesToBase64Url(new Uint8Array(signature))}`;
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
  return Math.floor(Date.now() / 1000) + 120;
}

test("verifyCollabGrant accepts a validly signed unexpired grant", async () => {
  const grant = await mintGrant({
    room: "5ZNHGF9P",
    userId: "web:abc",
    role: "guest",
    mode: "code",
    exp: futureExp(),
  });

  const claims = await verifyCollabGrant(grant, SECRET);

  expect(claims).not.toBeNull();
  expect(claims?.room).toBe("5ZNHGF9P");
  expect(claims?.role).toBe("guest");
});

test("verifyCollabGrant rejects a grant signed with the wrong secret", async () => {
  const grant = await mintGrant(
    { room: "5ZNHGF9P", exp: futureExp() },
    "some-other-secret",
  );

  expect(await verifyCollabGrant(grant, SECRET)).toBeNull();
});

test("verifyCollabGrant rejects an expired grant", async () => {
  const grant = await mintGrant({
    room: "5ZNHGF9P",
    exp: Math.floor(Date.now() / 1000) - 1,
  });

  expect(await verifyCollabGrant(grant, SECRET)).toBeNull();
});

test("verifyCollabGrant rejects tampered payloads", async () => {
  const grant = await mintGrant({ room: "5ZNHGF9P", exp: futureExp() });
  const [prefix, , signature] = grant.split(".");
  const forgedPayload = base64UrlEncode(
    JSON.stringify({ room: "STOLEN99", exp: futureExp() }),
  );

  expect(
    await verifyCollabGrant(`${prefix}.${forgedPayload}.${signature}`, SECRET),
  ).toBeNull();
});

test("verifyCollabGrant rejects unknown prefixes and malformed tokens", async () => {
  expect(await verifyCollabGrant("mosaicv1.abc.def", SECRET)).toBeNull();
  expect(await verifyCollabGrant("not-a-grant", SECRET)).toBeNull();
  expect(await verifyCollabGrant("", SECRET)).toBeNull();
});

test("verifyCollabGrant requires room and numeric exp claims", async () => {
  const missingRoom = await mintGrant({ exp: futureExp() });
  const missingExp = await mintGrant({ room: "5ZNHGF9P" });

  expect(await verifyCollabGrant(missingRoom, SECRET)).toBeNull();
  expect(await verifyCollabGrant(missingExp, SECRET)).toBeNull();
});

test("grantFromRequest prefers the query param and falls back to bearer", () => {
  const withQuery = new URL("https://relay.test/connect?grant=token-a");
  const plainURL = new URL("https://relay.test/connect");
  const bearerRequest = new Request("https://relay.test/connect", {
    headers: { authorization: "Bearer token-b" },
  });
  const bareRequest = new Request("https://relay.test/connect");

  expect(grantFromRequest(bareRequest, withQuery)).toBe("token-a");
  expect(grantFromRequest(bearerRequest, plainURL)).toBe("token-b");
  expect(grantFromRequest(bareRequest, plainURL)).toBeNull();
});

export { mintGrant };
