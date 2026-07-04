export type ClerkUserIdentityLike = {
  id: string;
  fullName?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  imageUrl?: string | null;
  primaryEmailAddress?: { emailAddress?: string | null } | null;
  emailAddresses?: readonly { emailAddress?: string | null }[];
};

export type NativeIdentityClaims = {
  displayName: string | null;
  primaryEmail: string | null;
  imageURL: string | null;
};

export function nativeIdentityClaimsFor(user: ClerkUserIdentityLike | null): NativeIdentityClaims {
  return {
    displayName: displayNameFor(user),
    primaryEmail: primaryEmailFor(user),
    imageURL: imageURLFor(user),
  };
}

function displayNameFor(user: ClerkUserIdentityLike | null): string | null {
  if (!user) return null;
  if (user.fullName?.trim()) return user.fullName.trim();
  const joined = [user.firstName, user.lastName]
    .map((part) => part?.trim())
    .filter(Boolean)
    .join(" ");
  return joined || null;
}

function primaryEmailFor(user: ClerkUserIdentityLike | null): string | null {
  return user?.primaryEmailAddress?.emailAddress
    ?? user?.emailAddresses?.find((email) => email.emailAddress)?.emailAddress
    ?? null;
}

function imageURLFor(user: ClerkUserIdentityLike | null): string | null {
  const imageUrl = user?.imageUrl?.trim();
  return imageUrl || null;
}
