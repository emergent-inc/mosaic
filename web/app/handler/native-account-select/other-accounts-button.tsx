"use client";

import { useState } from "react";
import { useClerk } from "@clerk/nextjs";

export function OtherAccountsButton({
  redirectUrl,
  label,
}: {
  redirectUrl: string;
  label: string;
}) {
  const { signOut } = useClerk();
  const [isSigningOut, setIsSigningOut] = useState(false);

  return (
    <button
      type="button"
      disabled={isSigningOut}
      onClick={async () => {
        setIsSigningOut(true);
        await signOut({ redirectUrl });
      }}
      className="w-full rounded-2xl border border-white/10 px-4 py-3 text-sm font-medium text-white transition hover:bg-white/10 disabled:cursor-wait disabled:opacity-60"
    >
      {label}
    </button>
  );
}
