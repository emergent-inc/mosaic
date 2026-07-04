import { cookies } from "next/headers";
import { auth, clerkClient, currentUser } from "@clerk/nextjs/server";
import { makeAfterSignInHandler } from "./handler";

export const dynamic = "force-dynamic";

export const GET = makeAfterSignInHandler({
  getAuth: auth,
  getUser: async () => currentUser(),
  listMemberships: async (userId) => {
    const client = await clerkClient();
    const memberships = await client.users.getOrganizationMembershipList({
      userId,
      limit: 100,
    });
    return memberships.data;
  },
  getCookieStore: cookies,
});
