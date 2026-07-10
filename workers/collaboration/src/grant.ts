// Join-grant verification for relay connects.
//
// www mints short-lived signed join grants of the form
//   `mosaicgrant1.<base64url(JSON claims)>.<base64url(HMAC-SHA256(payload))>`
// signed with MOSAIC_COLLAB_GRANT_SECRET (shared secret with www; see
// www/services/collab/grant.ts and www/relay-worker/worker.js for the
// contract). The relay's only responsibility is: no valid grant whose `room`
// matches the connect path, no connect. All org/plan enforcement happens in
// www before a grant is minted.
//
// Rollout: grants are verified whenever one is presented. Connects without a
// grant are only rejected when COLLABORATION_REQUIRE_GRANT="true", so old app
// builds that join by bare session code keep working until the flag flips.

const GRANT_PREFIX = "mosaicgrant1";

export interface CollabGrantClaims {
  room: string;
  userId?: string;
  orgId?: string | null;
  role?: string;
  mode?: string;
  exp: number;
  iat?: number;
  nonce?: string;
}

export async function verifyCollabGrant(
  token: string,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<CollabGrantClaims | null> {
  if (token === "" || secret === "") return null;
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== GRANT_PREFIX) return null;
  const [, payloadPart, signaturePart] = parts;

  const expected = await hmacBase64Url(payloadPart, secret);
  if (!timingSafeEqual(signaturePart, expected)) return null;

  let claims: unknown;
  try {
    claims = JSON.parse(base64UrlToString(payloadPart));
  } catch {
    return null;
  }
  if (typeof claims !== "object" || claims === null) return null;
  const record = claims as Record<string, unknown>;
  if (typeof record.room !== "string" || record.room === "") return null;
  if (typeof record.exp !== "number" || record.exp <= nowSeconds) return null;
  return record as unknown as CollabGrantClaims;
}

export function grantFromRequest(request: Request, url: URL): string | null {
  const fromQuery = url.searchParams.get("grant");
  if (fromQuery !== null && fromQuery.trim() !== "") return fromQuery.trim();
  const header = request.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice("bearer ".length).trim();
  return token === "" ? null : token;
}

async function hmacBase64Url(payload: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return bytesToBase64Url(new Uint8Array(signature));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i += 1) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlToString(value: string): string {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}
