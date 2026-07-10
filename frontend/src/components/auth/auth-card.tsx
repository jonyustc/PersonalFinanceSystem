import Link from "next/link";
import type { ReactNode } from "react";

type AuthCardProps = {
  title: string;
  subtitle: string;
  switchLabel: string;
  switchHref: string;
  switchText: string;
  children: ReactNode;
};

export function AuthCard({ title, subtitle, switchLabel, switchHref, switchText, children }: AuthCardProps) {
  return (
    <div className="mx-auto w-full max-w-md rounded-lg border border-line bg-card p-6 shadow-soft sm:p-8">
      <div className="mb-7">
        <p className="text-sm font-semibold text-brand-700">Personal Finance</p>
        <h1 className="mt-3 text-3xl font-semibold text-ink">{title}</h1>
        <p className="mt-2 text-sm leading-6 text-muted">{subtitle}</p>
      </div>
      {children}
      <p className="mt-6 text-center text-sm text-muted">
        {switchLabel}{" "}
        <Link className="font-semibold text-brand-700 hover:text-brand-600" href={switchHref}>
          {switchText}
        </Link>
      </p>
    </div>
  );
}
