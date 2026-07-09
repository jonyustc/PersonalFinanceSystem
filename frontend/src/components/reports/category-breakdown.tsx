"use client";

import { ArrowLeft, ChevronRight } from "lucide-react";

import { ProgressPill } from "@/components/ui/progress-pill";
import { categoryVisual } from "@/lib/category-visuals";
import { formatMoney } from "@/lib/money";

export interface CategoryRowDatum {
  id: string;
  name: string;
  amount: number;
  /** Series color assigned by rank (matches the donut slice). */
  color: string;
  /** True when tapping drills into subcategories instead of transactions. */
  hasChildren: boolean;
}

interface CategoryBreakdownProps {
  rows: CategoryRowDatum[];
  /** Total expense of the current level, used for the percentage captions. */
  total: number;
  /** Names of the drill path, e.g. ["Food"]; empty at the top level. */
  breadcrumb: string[];
  onRowClick: (row: CategoryRowDatum) => void;
  onBack: () => void;
}

/**
 * Ranked per-category list with progress bars. Tapping a parent replaces the
 * list with its subcategories; tapping a leaf opens the transaction drawer.
 * Mirrors the mobile `_CategoryBreakdown`.
 */
export function CategoryBreakdown({
  rows,
  total,
  breadcrumb,
  onRowClick,
  onBack,
}: CategoryBreakdownProps) {
  const maxAmount = rows.reduce((max, row) => Math.max(max, row.amount), 0);

  return (
    <section className="card">
      {breadcrumb.length > 0 ? (
        <div className="flex items-center gap-2 border-b border-line p-3">
          <button
            type="button"
            onClick={onBack}
            title="Back"
            aria-label="Back"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-brand-600/10 text-brand-700 transition hover:bg-brand-600/20"
          >
            <ArrowLeft className="h-4 w-4" />
          </button>
          <p className="min-w-0 truncate text-sm font-semibold text-ink">
            <span className="text-muted">All categories / </span>
            {breadcrumb.join(" / ")}
          </p>
        </div>
      ) : null}

      {rows.length === 0 ? (
        <p className="p-4 text-sm text-muted">
          No expense recorded here for this period.
        </p>
      ) : (
        <div className="divide-y divide-line">
          {rows.map((row) => {
            const { Icon } = categoryVisual(row.name);
            const percent = total > 0 ? Math.round((row.amount / total) * 100) : 0;
            return (
              <button
                key={row.id}
                type="button"
                onClick={() => onRowClick(row)}
                className="flex w-full items-center gap-3 p-3 text-left transition hover:bg-surface"
              >
                <span
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
                  style={{ backgroundColor: `${row.color}24`, color: row.color }}
                >
                  <Icon className="h-[18px] w-[18px]" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="flex items-baseline justify-between gap-3">
                    <span className="truncate text-sm font-medium text-ink">
                      {row.name}
                    </span>
                    <span className="money shrink-0 text-sm font-semibold text-ink">
                      {formatMoney(row.amount)}
                    </span>
                  </span>
                  <span className="mt-1.5 flex items-center gap-2">
                    <ProgressPill
                      fraction={maxAmount > 0 ? row.amount / maxAmount : 0}
                      color={row.color}
                      className="h-1.5"
                    />
                    <span className="w-8 shrink-0 text-right text-[11px] text-muted">
                      {percent}%
                    </span>
                  </span>
                </span>
                <ChevronRight
                  className="h-4 w-4 shrink-0 text-muted/70"
                  aria-hidden
                />
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}
