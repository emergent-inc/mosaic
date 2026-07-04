import { auth, currentUser } from "@clerk/nextjs/server";
import {
  type NativeSessionClaims,
  verifyNativeAuthToken,
} from "../auth/nativeSession";
import { vmBillingPlanIdFromMetadata } from "../workspaces/mosaicWorkspace";

export type AuthedUser = {
  id: string;
  displayName: string | null;
  primaryEmail: string | null;
  billingCustomerType: "team" | "user";
  billingTeamId: string;
  selectedTeamId: string | null;
  teams: readonly AuthedTeam[];
  teamIds: readonly string[];
  userBillingPlanId: string | null;
  billingPlanId: string | null;
};

export type AuthedTeam = {
  id: string;
  billingPlanId: string | null;
};

/**
 * Verify the caller's Clerk session. Accepts either a cmux native bearer token
 * minted from a Clerk browser session or a Clerk cookie session for browser
 * routes.
 *
 * Returns the resolved user or null if unauthenticated.
 */
export async function verifyRequest(
  request: Request,
  options: { readonly requestedTeamId?: string | null; readonly allowCookie?: boolean } = {},
): Promise<AuthedUser | null> {
  const authHeader = request.headers.get("authorization");

  if (authHeader?.toLowerCase().startsWith("bearer ")) {
    const accessToken = authHeader.slice("bearer ".length).trim();
    const claims = accessToken ? verifyNativeAuthToken(accessToken) : null;
    if (claims?.kind === "access") {
      return authedUserFromNativeClaims(claims, options);
    }
    const legacyStackUser = await legacyStackUserFromRequest(request, accessToken);
    if (legacyStackUser) {
      return await authedUserFromStackUser(legacyStackUser, options);
    }
  }

  if (options.allowCookie === false) {
    return null;
  }

  const legacyCookieUser = await legacyStackCookieUserFromRequest(request);
  if (legacyCookieUser) {
    return await authedUserFromStackUser(legacyCookieUser, options);
  }

  // Fall back to Clerk's Next.js cookie flow when a browser hits the route.
  try {
    const clerkAuth = await auth();
    if (!clerkAuth.userId) return null;
    return authedUserFromClerkCookie(
      clerkAuth.userId,
      clerkAuth.orgId ?? null,
      await currentUser(),
      options
    );
  } catch {
    return null;
  }
}

async function legacyStackCookieUserFromRequest(request: Request): Promise<StackUserLike | null> {
  try {
    const { getStackServerApp, isStackConfigured } = await import("../../app/lib/stack");
    if (!isStackConfigured()) return null;
    return await getStackServerApp().getUser({
      tokenStore: request as unknown as { headers: { get(name: string): string | null } },
    }) as StackUserLike | null;
  } catch {
    return null;
  }
}

async function legacyStackUserFromRequest(request: Request, accessToken: string): Promise<StackUserLike | null> {
  const refreshToken = request.headers.get("x-stack-refresh-token")?.trim();
  if (!accessToken || !refreshToken) return null;
  try {
    const { getStackServerApp, isStackConfigured } = await import("../../app/lib/stack");
    if (!isStackConfigured()) return null;
    return await getStackServerApp().getUser({
      tokenStore: { accessToken, refreshToken },
    }) as StackUserLike | null;
  } catch {
    return null;
  }
}

async function authedUserFromStackUser(
  user: StackUserLike,
  options: { readonly requestedTeamId?: string | null },
): Promise<AuthedUser> {
  const selectedTeam = teamLike(user.selectedTeam);
  const requestedTeamId = normalizedOptionalString(options.requestedTeamId);
  const needsListedTeams = !selectedTeam || (!!requestedTeamId && requestedTeamId !== selectedTeam.id);
  const listedTeams = needsListedTeams && typeof user.listTeams === "function"
    ? (await user.listTeams()).map(teamLike).filter((team): team is TeamLike => !!team)
    : [];
  const teams = uniqueTeams([selectedTeam, ...listedTeams]);
  return authedUserFromParts({
    userId: user.id,
    displayName: user.displayName,
    primaryEmail: user.primaryEmail,
    selectedTeam,
    teams,
    userBillingPlanId: planIdFromMetadata(user.clientReadOnlyMetadata) ?? null,
    requestedTeamId,
  });
}

function authedUserFromNativeClaims(
  claims: NativeSessionClaims,
  options: { readonly requestedTeamId?: string | null },
): AuthedUser {
  const requestedTeamId = normalizedOptionalString(options.requestedTeamId);
  const claimedTeamWorkspaces = new Map(
    (claims.teamWorkspaces ?? []).map((team) => [team.id, team]),
  );
  const selectedTeam = claims.selectedTeamId
    ? {
        id: claims.selectedTeamId,
        clientReadOnlyMetadata: undefined,
        billingPlanId: claimedTeamWorkspaces.get(claims.selectedTeamId)?.vmBillingPlanId ?? null,
      }
    : null;
  const teamIds = uniqueStrings([
    selectedTeam?.id,
    ...claims.teamIds,
  ]);
  return authedUserFromParts({
    userId: claims.userId,
    displayName: claims.displayName,
    primaryEmail: claims.primaryEmail,
    selectedTeam,
    teams: teamIds.map((id) => ({
      id,
      clientReadOnlyMetadata: undefined,
      billingPlanId: claimedTeamWorkspaces.get(id)?.vmBillingPlanId ?? null,
    })),
    userBillingPlanId: null,
    requestedTeamId,
  });
}

function authedUserFromClerkCookie(
  userId: string,
  orgId: string | null,
  user: ClerkUserLike | null,
  options: { readonly requestedTeamId?: string | null },
): AuthedUser {
  const requestedTeamId = normalizedOptionalString(options.requestedTeamId);
  const selectedTeam = orgId ? { id: orgId, clientReadOnlyMetadata: undefined } : null;
  const teams = uniqueTeams([selectedTeam]);
  return authedUserFromParts({
    userId,
    displayName: displayNameFor(user),
    primaryEmail: primaryEmailFor(user),
    selectedTeam,
    teams,
    userBillingPlanId: null,
    requestedTeamId,
  });
}

function authedUserFromParts(input: {
  userId: string;
  displayName: string | null;
  primaryEmail: string | null;
  selectedTeam: TeamLike | null;
  teams: readonly TeamLike[];
  userBillingPlanId: string | null;
  requestedTeamId: string | null;
}): AuthedUser {
  const teamIds = uniqueStrings([
    input.selectedTeam?.id,
    ...input.teams.map((team) => team.id),
  ]);
  const requestedTeam = input.requestedTeamId
    ? input.teams.find((team) => team.id === input.requestedTeamId) ?? null
    : null;
  const billingTeam = requestedTeam ?? input.selectedTeam ?? (input.teams.length === 1 ? input.teams[0] : null);
  const billingPlanId =
    billingTeam?.billingPlanId ??
    planIdFromMetadata(billingTeam?.clientReadOnlyMetadata) ??
    input.userBillingPlanId;

  return {
    id: input.userId,
    displayName: input.displayName,
    primaryEmail: input.primaryEmail,
    billingCustomerType: billingTeam ? "team" : "user",
    billingTeamId: billingTeam?.id ?? input.userId,
    selectedTeamId: input.selectedTeam?.id ?? null,
    teams: input.teams.map((team) => ({
      id: team.id,
      billingPlanId: team.billingPlanId ?? planIdFromMetadata(team.clientReadOnlyMetadata),
    })),
    teamIds,
    userBillingPlanId: input.userBillingPlanId,
    billingPlanId,
  };
}

type ClerkUserLike = {
  readonly id: string;
  readonly fullName?: string | null;
  readonly firstName?: string | null;
  readonly lastName?: string | null;
  readonly primaryEmailAddress?: { emailAddress?: string | null } | null;
  readonly emailAddresses?: readonly { emailAddress?: string | null }[];
  readonly clientReadOnlyMetadata?: unknown;
};

type StackUserLike = {
  readonly id: string;
  readonly displayName: string | null;
  readonly primaryEmail: string | null;
  readonly clientReadOnlyMetadata?: unknown;
  readonly selectedTeam?: unknown;
  readonly listTeams?: () => Promise<readonly unknown[]>;
};

type TeamLike = {
  readonly id: string;
  readonly clientReadOnlyMetadata?: unknown;
  readonly billingPlanId?: string | null;
};

function teamLike(value: unknown): TeamLike | null {
  if (!value || typeof value !== "object") return null;
  const id = (value as { id?: unknown }).id;
  if (typeof id !== "string" || !id) return null;
  return {
    id,
    clientReadOnlyMetadata: (value as { clientReadOnlyMetadata?: unknown }).clientReadOnlyMetadata,
    billingPlanId: planIdFromMetadata((value as { clientReadOnlyMetadata?: unknown }).clientReadOnlyMetadata),
  };
}

function planIdFromMetadata(metadata: unknown): string | null {
  return vmBillingPlanIdFromMetadata(metadata);
}

function uniqueStrings(values: readonly (string | undefined)[]): readonly string[] {
  return [...new Set(values.filter((value): value is string => typeof value === "string" && value.length > 0))];
}

function uniqueTeams(values: readonly (TeamLike | null | undefined)[]): readonly TeamLike[] {
  const teams: TeamLike[] = [];
  const seen = new Set<string>();
  for (const team of values) {
    if (!team || seen.has(team.id)) continue;
    seen.add(team.id);
    teams.push(team);
  }
  return teams;
}

function displayNameFor(user: ClerkUserLike | null): string | null {
  if (!user) return null;
  if (user.fullName?.trim()) return user.fullName.trim();
  const joined = [user.firstName, user.lastName]
    .map((part) => part?.trim())
    .filter(Boolean)
    .join(" ");
  return joined || null;
}

function primaryEmailFor(user: ClerkUserLike | null): string | null {
  return user?.primaryEmailAddress?.emailAddress
    ?? user?.emailAddresses?.find((email) => email.emailAddress)?.emailAddress
    ?? null;
}

function normalizedOptionalString(value: string | null | undefined): string | null {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}

export function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "content-type": "application/json" },
  });
}
