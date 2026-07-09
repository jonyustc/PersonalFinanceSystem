"use client";

import { ArrowDown, ArrowUp } from "lucide-react";

import { formatMoney, signedMoney } from "@/lib/money";
import { cn } from "@/lib/utils";

export const SPEND_SOURCES = ["Cash", "Bank", "Card"] as const;
export type SpendSource = (typeof SPEND_SOURCES)[number];

interface SpendingSummaryCardProps {
  spent: number;
  income: number;
  /** Total expense in the immediately-previous equal-length period. */
  previousSpent: number | null;
  dailyAverage: number;
  sources: Record<SpendSource, number>;
  onSourceClick: (source: SpendSource) => void;
}

/**
 * Headline spend card: big total, period-over-period change, income / net /
 * daily-average row, and the Cash / Bank / Card "spent from" chips. Mirrors
 * the mobile `_SpendingSummary`.
 */
export function SpendingSummaryCard({
  spent,
  income,
  previousSpent,
  dailyAverage,
  sources,
  onSourceClick,
}: SpendingSummaryCardProps) {
  const net = income - spent;
  const hasPrevious = previousSpent !== null && previousSpent > 0;
  const changePercent = hasPrevious
    ? ((spent - previousSpent) / previousSpent) * 100
    : 0;
  const spendingUp = changePercent >= 0;

  return (
    <section className="card p-5">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">
        Spent
      </p>
      <p className="money mt-1 truncate text-3xl font-extrabold text-expense">
        {formatMoney(spent)}
      </p>

      {hasPrevious ? (
        <p
          className={cn(
            "mt-1.5 flex items-center gap-1 text-xs font-bold",
            spendingUp ? "text-expense" : "text-income",
          )}
        >
          {spendingUp ? (
            <ArrowUp className="h-3.5 w-3.5" aria-hidden />
          ) : (
            <ArrowDown className="h-3.5 w-3.5" aria-hidden />
          )}
          {Math.abs(Math.round(changePercent))}% vs previous period
        </p>
      ) : null}

      <div className="mt-4 grid grid-cols-3 gap-3 border-t border-line pt-4">
        <SummaryMetric label="Income" value={formatMoney(income)} className="text-income" />
        <SummaryMetric
          label="Net"
          value={signedMoney(net)}
          className={net >= 0 ? "text-income" : "text-expense"}
        />
        <SummaryMetric label="Daily avg" value={formatMoney(dailyAverage)} className="text-ink" />
      </div>

      <div className="mt-4">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">
          Spent from
        </p>
        <div className="mt-2 grid grid-cols-3 gap-2">
          {SPEND_SOURCES.map((source) => (
            <button
              key={source}
              type="button"
              onClick={() => onSourceClick(source)}
              title={`${source} expense history`}
              className="min-w-0 rounded-xl border border-line bg-surface p-2.5 text-left transition hover:border-brand-600/40"
            >
              <p className="text-xs font-medium text-muted">{source}</p>
              <p className="money mt-0.5 truncate text-sm font-semibold text-ink">
                {formatMoney(sources[source])}
              </p>
            </button>
          ))}
        </div>
      </div>
    </section>
  );
}

function SummaryMetric({
  label,
  value,
  className,
}: {
  label: string;
  value: string;
  className?: string;
}) {
  return (
    <div className="min-w-0">
      <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">
        {label}
      </p>
      <p className={cn("money mt-0.5 truncate text-sm font-bold", className)}>{value}</p>
    </div>
  );
}
