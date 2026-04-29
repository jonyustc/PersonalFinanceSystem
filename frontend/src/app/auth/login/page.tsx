import { AuthCard } from "@/components/auth/auth-card";
import { LoginForm } from "@/components/auth/login-form";

export default function LoginPage() {
  return (
    <AuthCard
      title="Welcome back"
      subtitle="Sign in to review balances, recent transactions, budgets, and portfolio movement."
      switchLabel="New here?"
      switchHref="/auth/register"
      switchText="Create an account"
    >
      <LoginForm />
    </AuthCard>
  );
}
