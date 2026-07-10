import type { InputHTMLAttributes } from "react";

import { cn } from "@/lib/utils";

type InputProps = InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  error?: string;
};

export function Input({ className, label, error, id, ...props }: InputProps) {
  const inputId = id ?? props.name;

  return (
    <label className="block" htmlFor={inputId}>
      {label ? <span className="mb-2 block text-sm font-medium text-ink">{label}</span> : null}
      <input
        id={inputId}
        className={cn(
          "h-11 w-full rounded-md border border-line bg-card px-3 text-sm outline-none transition placeholder:text-muted/70 focus:border-brand-600 focus:ring-4 focus:ring-brand-100",
          error && "border-expense/60 focus:border-expense focus:ring-expense/15",
          className
        )}
        {...props}
      />
      {error ? <span className="mt-1 block text-xs text-expense">{error}</span> : null}
    </label>
  );
}
