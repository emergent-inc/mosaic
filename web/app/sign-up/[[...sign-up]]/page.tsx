import { SignUp } from "@clerk/nextjs";
import { AuthAnalytics } from "../../components/auth-analytics";

export default function SignUpPage() {
  return (
    <main className="grid min-h-screen place-items-center px-6 py-12">
      <AuthAnalytics mode="sign_up" />
      <SignUp
        path="/sign-up"
        routing="path"
        signInUrl="/sign-in"
        fallbackRedirectUrl="/"
      />
    </main>
  );
}
