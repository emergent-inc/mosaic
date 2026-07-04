import { NextRequest, NextResponse } from "next/server";
import { auth } from "@clerk/nextjs/server";
import {
  clerkSignInURL,
  nativeAccountSelectURL,
  prepareNativeHandoff,
  redirectWithHandoffCookie,
} from "../native-handoff";

export const dynamic = "force-dynamic";

type ClerkAuthLike = {
  userId: string | null;
};

type NativeSignInHandlerDependencies = {
  getAuth: () => Promise<ClerkAuthLike>;
};

export function makeNativeSignInHandler(dependencies: NativeSignInHandlerDependencies) {
  return async function GET(request: NextRequest) {
    if (!request.nextUrl.searchParams.get("after_auth_return_to")) {
      return NextResponse.redirect(new URL("/sign-in", request.url));
    }

    const handoff = prepareNativeHandoff(request);
    if (!handoff) {
      return NextResponse.redirect(new URL("/", request.url));
    }

    const authState = await dependencies.getAuth();
    const location = authState.userId
      ? nativeAccountSelectURL(request, handoff.afterSignInURL)
      : clerkSignInURL(request, handoff.afterSignInURL);
    return redirectWithHandoffCookie(request, location, handoff.nonce);
  };
}

export const GET = makeNativeSignInHandler({ getAuth: auth });
