import { NextResponse } from "next/server";
import { verifyNativeAuthToken } from "../../../../../services/auth/nativeSession";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const refreshToken = request.headers.get("x-mosaic-refresh-token")?.trim()
    ?? (await refreshTokenFromBody(request));
  if (!refreshToken || !verifyNativeAuthToken(refreshToken)) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // Tokens are signed and self-contained. Revocation is acknowledged so local
  // sign-out can complete; short access-token TTL bounds stale credential use.
  return NextResponse.json({ ok: true });
}

async function refreshTokenFromBody(request: Request): Promise<string | null> {
  try {
    const body = await request.json() as { refreshToken?: unknown };
    return typeof body.refreshToken === "string" && body.refreshToken.trim()
      ? body.refreshToken.trim()
      : null;
  } catch {
    return null;
  }
}
