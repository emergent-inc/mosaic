import { SignIn } from "@clerk/nextjs";
import { AuthAnalytics } from "../../components/auth-analytics";

export default function SignInPage() {
  return (
    <main className="grid min-h-screen place-items-center px-6 py-12">
      <AuthAnalytics mode="sign_in" />
      <SignIn
        path="/sign-in"
        routing="path"
        signUpUrl="/sign-up"
        fallbackRedirectUrl="/"
      />
    </main>
  );
}
