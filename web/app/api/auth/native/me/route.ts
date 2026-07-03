import { NextResponse } from "next/server";
import { verifyNativeAuthToken } from "../../../../../services/auth/nativeSession";

export const dynamic = "force-dynamic";

export function GET(request: Request) {
  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const claims = verifyNativeAuthToken(token);
  if (!claims || claims.kind !== "access") {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  return NextResponse.json({
    user: {
      id: claims.userId,
      displayName: claims.displayName,
      primaryEmail: claims.primaryEmail,
      imageURL: claims.imageURL,
    },
    teams: claims.teamIds.map((id) => ({ id, displayName: null })),
    selectedTeamId: claims.selectedTeamId,
  });
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (!header?.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice("bearer ".length).trim();
  return token || null;
}
