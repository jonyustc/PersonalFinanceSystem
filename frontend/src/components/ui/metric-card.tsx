import type { LucideIcon } from "lucide-react";

import { cn } from "@/lib/utils";

interface MetricCardProps {
  icon: LucideIcon;
  label: string;
  value: string;
  caption?: string;
  tone?: "default" | "income" | "expense" | "brand" | "warning";
  onClick?: () => void;
  className?: string;
}

const toneStyles: Record<NonNullable<MetricCardProps["tone"]>, { chip: string; value: string }> = {
  default: { chip: "bg-slate-500/15 text-slate-600", value: "text-ink" },
  income: { chip: "bg-income/15 text-income", value: "text-income" },
  expense: { chip: "bg-expense/15 text-expense", value: "text-expense" },
  brand: { chip: "bg-brand-600/15 text-brand-700", value: "text-ink" },
  warning: { chip: "bg-warning/15 text-warning", value: "text-warning" },
};

// The mobile app's StatCard: tinted icon chip → uppercase micro-label →
// big tabular amount → muted caption. Flat card, hairline border.
export function MetricCard({
  icon: Icon,
  label,
  value,
  caption,
  tone = "default",
  onClick,
  className,
}: MetricCardProps) {
  const styles = toneStyles[tone];
  const Wrapper = onClick ? "button" : "div";

  return (
    <Wrapper
      onClick={onClick}
      className={cn(
        "card p-4 text-left min-w-0",
        onClick && "transition hover:border-brand-600/40 active:scale-[0.99]",
        className,
      )}
    >
      <span
        className={cn(
          "mb-2.5 flex h-9 w-9 items-center justify-center rounded-lg",
          styles.chip,
        )}
      >
        <Icon className="h-[18px] w-[18px]" />
      </span>
      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">
        {label}
      </p>
      <p className={cn("money mt-0.5 truncate text-xl font-bold", styles.value)}>
        {value}
      </p>
      {caption ? <p className="mt-0.5 truncate text-xs text-muted">{caption}</p> : null}
    </Wrapper>
  );
}
