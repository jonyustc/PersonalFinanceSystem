import { AuthCard } from "@/components/auth/auth-card";
import { RegisterForm } from "@/components/auth/register-form";

export default function RegisterPage() {
  return (
    <AuthCard
      title="Create account"
      subtitle="Start with a secure profile, then add accounts, categories, budgets, and investment activity."
      switchLabel="Already registered?"
      switchHref="/auth/login"
      switchText="Sign in"
    >
      <RegisterForm />
    </AuthCard>
  );
}
