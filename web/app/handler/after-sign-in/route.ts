import { cookies } from "next/headers";
import { auth, currentUser } from "@clerk/nextjs/server";
import { makeAfterSignInHandler } from "./handler";

export const dynamic = "force-dynamic";

export const GET = makeAfterSignInHandler({
  getAuth: auth,
  getUser: async () => currentUser(),
  getCookieStore: cookies,
});
