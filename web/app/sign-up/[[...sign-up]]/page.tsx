import { SignUp } from "@clerk/nextjs";
import { AuthAnalytics } from "../../components/auth-analytics";

export default function SignUpPage() {
  return (
    <main className="grid min-h-screen place-items-center bg-[#0a0a0a] px-6 py-12 text-white">
      <AuthAnalytics mode="sign_up" />
      <SignUp
        path="/sign-up"
        routing="path"
        signInUrl="/sign-in"
        fallbackRedirectUrl="/"
        appearance={{
          variables: {
            colorBackground: "#0a0a0a",
            colorPrimary: "#ffffff",
            colorDanger: "#f87171",
            borderRadius: "0.875rem",
            fontFamily: "var(--font-geist-sans)",
          },
          elements: {
            rootBox: "w-full",
            cardBox: "shadow-none",
            card: "w-full rounded-3xl border border-white/10 bg-[#0f0f0f] shadow-none",
            headerTitle: "text-white",
            headerSubtitle: "text-neutral-400",
            socialButtonsBlockButton: "border-white/10 bg-[#141414] text-white shadow-none hover:bg-[#1a1a1a]",
            formFieldInput: "border-white/10 bg-[#111111] text-white shadow-none focus:border-white/30",
            formButtonPrimary: "border border-white/10 bg-[#171717] text-white shadow-none hover:bg-[#1f1f1f]",
            footerActionText: "text-neutral-400",
            footerActionLink: "text-white",
            dividerLine: "bg-white/10",
            dividerText: "text-neutral-500",
          },
        }}
      />
    </main>
  );
}
