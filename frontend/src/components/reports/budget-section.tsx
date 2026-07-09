"use client";

import { ProgressPill } from "@/components/ui/progress-pill";
import { SectionHeader } from "@/components/ui/section-header";
import { formatMoney } from "@/lib/money";
import { cn } from "@/lib/utils";

// Shape of GET /budgets/summary (backend `BudgetSummaryResponse`); the
// service wrapper is untyped, so the contract is pinned here.
export interface BudgetSummaryItem {
  category_id: string;
  category_name: string;
  budget: number;
  spent: number;
  remaining: number;
  used_percentage: number;
  overspending: boolean;
}

export interface BudgetSummary {
  month: string;
  income: number;
  opening_balance: number;
  total_balance: number;
  total_budget: number;
  total_spent: number;
  planned_balance: number;
  actual_balance: number;
  categories: BudgetSummaryItem[];
}

interface BudgetSectionProps {
  summary: BudgetSummary | undefined;
  loading: boolean;
}

/** Month-only budget vs spending card with utilization-colored progress. */
export function BudgetSection({ summary, loading }: BudgetSectionProps) {
  if (loading) {
    return (
      <div className="space-y-2">
        <SectionHeader title="Budget" subtitle="This month's plan" />
        <div className="card h-32 animate-pulse" />
      </div>
    );
  }

  if (!summary) return null;

  const totalBudget = Number(summary.total_budget ?? 0);
  const totalSpent = Number(summary.total_spent ?? 0);
  const left = totalBudget - totalSpent;
  const overallFraction = totalBudget > 0 ? totalSpent / totalBudget : 0;

  return (
    <div className="space-y-2">
      <SectionHeader title="Budget" subtitle="This month's plan" />
      <section className="card divide-y divide-line">
        <div className="p-4">
          <ProgressPill fraction={overallFraction} />
          <p className="mt-2 text-xs text-muted">
            <span className="money font-semibold text-ink">
              {formatMoney(totalSpent)}
            </span>{" "}
            spent of{" "}
            <span className="money font-semibold text-ink">
              {formatMoney(totalBudget)}
            </span>{" "}
            budget ·{" "}
            <span
              className={cn(
                "money font-semibold",
                left >= 0 ? "text-income" : "text-expense",
              )}
            >
              {formatMoney(Math.abs(left))} {left >= 0 ? "left" : "over"}
            </span>
          </p>
        </div>

        {summary.categories.length === 0 ? (
          <p className="p-4 text-sm text-muted">
            No budget plan found for this month.
          </p>
        ) : (
          <div className="divide-y divide-line">
            {summary.categories.map((item) => {
              const budget = Number(item.budget ?? 0);
              const spent = Number(item.spent ?? 0);
              const fraction = budget > 0 ? spent / budget : 0;
              const over = item.overspending || spent > budget;
              return (
                <div key={item.category_id} className="p-3">
                  <div className="flex items-baseline justify-between gap-3">
                    <p className="min-w-0 truncate text-sm font-medium text-ink">
                      {item.category_name}
                    </p>
                    <p
                      className={cn(
                        "money shrink-0 text-xs font-semibold",
                        over ? "text-expense" : "text-ink",
                      )}
                    >
                      {formatMoney(spent)}{" "}
                      <span className="font-normal text-muted">
                        / {formatMoney(budget)}
                      </span>
                    </p>
                  </div>
                  <ProgressPill fraction={fraction} className="mt-1.5 h-1.5" />
                </div>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}
