import { NextResponse } from "next/server";
import { refreshNativeSessionTokenPair } from "../../../../../services/auth/nativeSession";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const refreshToken = request.headers.get("x-cmux-refresh-token")?.trim()
    ?? (await refreshTokenFromBody(request));
  if (!refreshToken) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const tokens = refreshNativeSessionTokenPair(refreshToken);
  if (!tokens) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  return NextResponse.json(tokens);
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
