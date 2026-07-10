// Native mosaic auth token verification for team-scoped worker APIs.
//
// www mints `mosaicv1.<base64url(JSON claims)>.<base64url(HMAC-SHA256)>`
// access/refresh token pairs for the signed-in native app (see
// www/services/auth/nativeSession.ts). The worker shares the signing secret
// (MOSAIC_NATIVE_AUTH_SECRET) so it can authenticate the app's requests and
// scope them to the teams the token claims membership of, without a Clerk
// round-trip. Only short-lived `access` tokens are accepted here.

const NATIVE_TOKEN_PREFIX = "mosaicv1";

export interface NativeAccessClaims {
  userId: string;
  displayName: string | null;
  selectedTeamId: string | null;
  teamIds: readonly string[];
  exp: number;
}

export async function verifyNativeAccessToken(
  token: string,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<NativeAccessClaims | null> {
  if (token === "" || secret === "") return null;
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== NATIVE_TOKEN_PREFIX) return null;
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
  if (record.kind !== "access") return null;
  if (typeof record.userId !== "string" || record.userId === "") return null;
  if (typeof record.exp !== "number" || record.exp <= nowSeconds) return null;

  const teamIds = Array.isArray(record.teamIds)
    ? record.teamIds.filter(
        (teamId): teamId is string => typeof teamId === "string" && teamId !== "",
      )
    : [];
  return {
    userId: record.userId,
    displayName: typeof record.displayName === "string" ? record.displayName : null,
    selectedTeamId:
      typeof record.selectedTeamId === "string" && record.selectedTeamId !== ""
        ? record.selectedTeamId
        : null,
    teamIds,
    exp: record.exp,
  };
}

/// Whether the token's claims authorize operating on `teamId`. A user's own
/// id doubles as their personal team (mirrors www's solo-account convention
/// where billingTeamId falls back to the user id).
export function claimsAuthorizeTeam(claims: NativeAccessClaims, teamId: string): boolean {
  return teamId === claims.userId || claims.teamIds.includes(teamId);
}

export function bearerTokenFromRequest(request: Request): string | null {
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
