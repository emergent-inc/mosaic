import { NextResponse } from "next/server";
import { clerkClient } from "@clerk/nextjs/server";
import { nativeIdentityClaimsFor, type ClerkUserIdentityLike } from "../../../../../services/auth/clerkIdentity";
import { mintNativeSessionTokenPair, verifyNativeAuthToken } from "../../../../../services/auth/nativeSession";

export const dynamic = "force-dynamic";

type NativeRefreshHandlerDependencies = {
  getUser: (userId: string) => Promise<ClerkUserIdentityLike | null>;
};

export const POST = makeNativeRefreshHandler({
  getUser: async (userId) => {
    const client = await clerkClient();
    return client.users.getUser(userId);
  },
});

export function makeNativeRefreshHandler(dependencies: NativeRefreshHandlerDependencies) {
  return async function POST(request: Request) {
    const refreshToken = request.headers.get("x-mosaic-refresh-token")?.trim()
      ?? request.headers.get("x-cmux-refresh-token")?.trim()
      ?? (await refreshTokenFromBody(request));
    if (!refreshToken) {
      return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    }

    const claims = verifyNativeAuthToken(refreshToken);
    if (!claims || claims.kind !== "refresh") {
      return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    }

    const identity = nativeIdentityClaimsFor(await dependencies.getUser(claims.userId));
    const tokens = mintNativeSessionTokenPair({
      userId: claims.userId,
      displayName: identity.displayName,
      primaryEmail: identity.primaryEmail,
      imageURL: identity.imageURL,
      selectedTeamId: claims.selectedTeamId,
      teamIds: claims.teamIds,
      teamWorkspaces: claims.teamWorkspaces,
    });
    return NextResponse.json(tokens);
  };
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
