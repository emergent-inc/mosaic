import { describe, expect, test } from "bun:test";

const { nativeIdentityClaimsFor } = await import("../services/auth/clerkIdentity");

describe("Clerk identity claim normalization", () => {
  test("prefers trimmed full name primary email and profile image URL", () => {
    expect(nativeIdentityClaimsFor({
      id: "user_1",
      fullName: "  Ada Lovelace  ",
      firstName: "Ignored",
      lastName: "Name",
      imageUrl: "  https://img.example/ada.png  ",
      primaryEmailAddress: { emailAddress: "ada@example.com" },
      emailAddresses: [{ emailAddress: "secondary@example.com" }],
    })).toEqual({
      displayName: "Ada Lovelace",
      primaryEmail: "ada@example.com",
      imageURL: "https://img.example/ada.png",
    });
  });

  test("falls back to first and last name and first available email", () => {
    expect(nativeIdentityClaimsFor({
      id: "user_1",
      fullName: " ",
      firstName: " Grace ",
      lastName: " Hopper ",
      imageUrl: "https://img.example/grace.png",
      primaryEmailAddress: null,
      emailAddresses: [{ emailAddress: "" }, { emailAddress: "grace@example.com" }],
    })).toEqual({
      displayName: "Grace Hopper",
      primaryEmail: "grace@example.com",
      imageURL: "https://img.example/grace.png",
    });
  });

  test("returns nulls for missing user or blank profile image", () => {
    expect(nativeIdentityClaimsFor(null)).toEqual({
      displayName: null,
      primaryEmail: null,
      imageURL: null,
    });
    expect(nativeIdentityClaimsFor({
      id: "user_1",
      fullName: "",
      imageUrl: "   ",
    })).toEqual({
      displayName: null,
      primaryEmail: null,
      imageURL: null,
    });
  });
});
