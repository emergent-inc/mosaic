import { createHmac, randomBytes, timingSafeEqual } from "crypto";
import { env } from "../../app/env";

const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

export type NativeSessionTokenKind = "access" | "refresh";

export type NativeSessionClaims = {
  kind: NativeSessionTokenKind;
  userId: string;
  displayName: string | null;
  primaryEmail: string | null;
  selectedTeamId: string | null;
  teamIds: readonly string[];
  exp: number;
  iat: number;
  nonce: string;
};

export type NativeSessionTokenPair = {
  accessToken: string;
  refreshToken: string;
};

export type NativeSessionUserInput = {
  userId: string;
  displayName?: string | null;
  primaryEmail?: string | null;
  selectedTeamId?: string | null;
  teamIds?: readonly string[];
};

export function mintNativeSessionTokenPair(
  user: NativeSessionUserInput,
  nowSeconds = Math.floor(Date.now() / 1000)
): NativeSessionTokenPair {
  return {
    accessToken: signClaims(claimsFor("access", user, nowSeconds, ACCESS_TOKEN_TTL_SECONDS)),
    refreshToken: signClaims(claimsFor("refresh", user, nowSeconds, REFRESH_TOKEN_TTL_SECONDS)),
  };
}

export function refreshNativeSessionTokenPair(refreshToken: string): NativeSessionTokenPair | null {
  const claims = verifyNativeAuthToken(refreshToken);
  if (!claims || claims.kind !== "refresh") return null;
  return mintNativeSessionTokenPair({
    userId: claims.userId,
    displayName: claims.displayName,
    primaryEmail: claims.primaryEmail,
    selectedTeamId: claims.selectedTeamId,
    teamIds: claims.teamIds,
  });
}

export function verifyNativeAuthToken(token: string): NativeSessionClaims | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "cmuxv1") return null;
  const [, payloadPart, signaturePart] = parts;
  const expectedSignature = signature(payloadPart);
  if (!constantTimeEqual(signaturePart, expectedSignature)) return null;

  let claims: NativeSessionClaims;
  try {
    claims = JSON.parse(Buffer.from(payloadPart, "base64url").toString("utf8")) as NativeSessionClaims;
  } catch {
    return null;
  }
  if (!isValidClaims(claims)) return null;
  if (claims.exp <= Math.floor(Date.now() / 1000)) return null;
  return claims;
}

function claimsFor(
  kind: NativeSessionTokenKind,
  user: NativeSessionUserInput,
  nowSeconds: number,
  ttlSeconds: number
): NativeSessionClaims {
  return {
    kind,
    userId: user.userId,
    displayName: user.displayName ?? null,
    primaryEmail: user.primaryEmail ?? null,
    selectedTeamId: user.selectedTeamId ?? null,
    teamIds: uniqueStrings(user.teamIds ?? []),
    exp: nowSeconds + ttlSeconds,
    iat: nowSeconds,
    nonce: randomBytes(16).toString("base64url"),
  };
}

function signClaims(claims: NativeSessionClaims): string {
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  return `cmuxv1.${payload}.${signature(payload)}`;
}

function signature(payload: string): string {
  return createHmac("sha256", signingSecret()).update(payload).digest("base64url");
}

function signingSecret(): string {
  return env.CMUX_NATIVE_AUTH_SECRET ?? env.CLERK_SECRET_KEY;
}

function constantTimeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.byteLength === right.byteLength && timingSafeEqual(left, right);
}

function isValidClaims(value: NativeSessionClaims): boolean {
  return (
    (value.kind === "access" || value.kind === "refresh") &&
    typeof value.userId === "string" &&
    value.userId.length > 0 &&
    (value.displayName === null || typeof value.displayName === "string") &&
    (value.primaryEmail === null || typeof value.primaryEmail === "string") &&
    (value.selectedTeamId === null || typeof value.selectedTeamId === "string") &&
    Array.isArray(value.teamIds) &&
    value.teamIds.every((teamId) => typeof teamId === "string" && teamId.length > 0) &&
    Number.isFinite(value.exp) &&
    Number.isFinite(value.iat) &&
    typeof value.nonce === "string"
  );
}

function uniqueStrings(values: readonly string[]): readonly string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}
