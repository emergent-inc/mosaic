import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { currentUser } from "@clerk/nextjs/server";
import messages from "../../../messages/en.json";
import { nativeIdentityClaimsFor } from "../../../services/auth/clerkIdentity";
import {
  clerkSignInURLForOrigin,
  validatedAfterSignInURLForOrigin,
} from "../native-handoff";
import { OtherAccountsButton } from "./other-accounts-button";

type SearchParams = Record<string, string | string[] | undefined>;

function firstValue(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

async function requestOrigin(): Promise<string> {
  const headerStore = await headers();
  const host = headerStore.get("host") ?? "mosaic.inc";
  const forwardedProto = headerStore.get("x-forwarded-proto")?.split(",")[0]?.trim();
  const protocol = forwardedProto || (host.startsWith("localhost") || host.startsWith("127.0.0.1") ? "http" : "https");
  return `${protocol}://${host}`;
}

function withName(template: string, name: string): string {
  return template.replaceAll("{name}", name);
}

function initials(name: string): string {
  const letters = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
  return letters || name[0]?.toUpperCase() || "M";
}

export default async function NativeAccountSelectPage({
  searchParams,
}: {
  searchParams?: Promise<SearchParams>;
}) {
  const origin = await requestOrigin();
  const params = await searchParams;
  const afterSignInURL = validatedAfterSignInURLForOrigin(
    firstValue(params?.after_auth_return_to),
    origin
  );
  if (!afterSignInURL) {
    redirect("/");
  }

  const user = await currentUser();
  if (!user) {
    redirect(clerkSignInURLForOrigin(origin, afterSignInURL).toString());
  }

  const identity = nativeIdentityClaimsFor(user);
  const displayName = identity.displayName ?? identity.primaryEmail ?? messages.nativeAccountSelect.fallbackName;
  const email = identity.primaryEmail;
  const copy = messages.nativeAccountSelect;
  const signInURL = clerkSignInURLForOrigin(origin, afterSignInURL).toString();

  return (
    <main className="grid min-h-screen place-items-center bg-[#0a0a0a] px-6 py-12 text-white">
      <section className="w-full max-w-md rounded-3xl border border-white/10 bg-[#0f0f0f] p-8 shadow-2xl shadow-black/30">
        <div className="mx-auto mb-5 grid size-16 place-items-center rounded-full border border-white/10 bg-white/10 text-xl font-semibold">
          {initials(displayName)}
        </div>
        <div className="mb-8 text-center">
          <p className="mb-2 text-sm font-medium text-neutral-400">{copy.eyebrow}</p>
          <h1 className="text-2xl font-semibold tracking-tight">
            {withName(copy.title, displayName)}
          </h1>
          {email ? (
            <p className="mt-2 text-sm text-neutral-400">{email}</p>
          ) : null}
          <p className="mt-4 text-sm leading-6 text-neutral-400">{copy.body}</p>
        </div>
        <div className="space-y-3">
          <a
            href={afterSignInURL.toString()}
            className="block w-full rounded-2xl border border-white/10 bg-white px-4 py-3 text-center text-sm font-semibold text-black transition hover:bg-neutral-200"
          >
            {withName(copy.continueButton, displayName)}
          </a>
          <OtherAccountsButton
            redirectUrl={signInURL}
            label={copy.otherAccountsButton}
          />
        </div>
      </section>
    </main>
  );
}
