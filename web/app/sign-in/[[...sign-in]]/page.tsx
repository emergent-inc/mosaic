import { SignIn } from "@clerk/nextjs";

export default function SignInPage() {
  return (
    <main className="grid min-h-screen place-items-center px-6 py-12">
      <SignIn
        path="/sign-in"
        routing="path"
        signUpUrl="/sign-up"
        fallbackRedirectUrl="/"
      />
    </main>
  );
}
