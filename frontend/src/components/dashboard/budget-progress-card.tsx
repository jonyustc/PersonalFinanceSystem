import { PieChart } from "lucide-react";

import { ProgressPill, utilizationColor } from "@/components/ui/progress-pill";
import { formatMoney } from "@/lib/money";

interface BudgetProgressCardProps {
  totalBudget: number;
  totalSpent: number;
}

export function BudgetProgressCard({ totalBudget, totalSpent }: BudgetProgressCardProps) {
  if (totalBudget <= 0) return null;

  const fraction = totalSpent / totalBudget;
  const remaining = totalBudget - totalSpent;
  const color = utilizationColor(fraction);

  return (
    <section className="card p-4">
      <div className="flex items-center gap-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-brand-600/15 text-brand-700">
          <PieChart className="h-[18px] w-[18px]" />
        </span>
        <p className="min-w-0 flex-1 truncate text-sm font-bold text-ink">Monthly budget</p>
        <p className="money shrink-0 text-lg font-extrabold" style={{ color }}>
          {Math.round(fraction * 100)}%
        </p>
      </div>

      <ProgressPill fraction={fraction} className="mt-3" />

      <p className="money mt-2 text-xs text-muted">
        {formatMoney(totalSpent)} of {formatMoney(totalBudget)} spent ·{" "}
        {remaining >= 0 ? (
          <span>{formatMoney(remaining)} left</span>
        ) : (
          <span className="font-semibold text-expense">Over by {formatMoney(Math.abs(remaining))}</span>
        )}
      </p>
    </section>
  );
}
