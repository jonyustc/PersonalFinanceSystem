"use client";

import { useEffect, useMemo, useState } from "react";
import { Cell, Pie, PieChart, ResponsiveContainer } from "recharts";

import { formatMoney } from "@/lib/money";

/** Neutral slice color for the folded "Other" bucket. */
const OTHER_COLOR = "#94a3b8";
const MAX_SLICES = 7;

export interface DonutRow {
  name: string;
  amount: number;
  color: string;
}

interface DonutSlice {
  name: string;
  amount: number;
  color: string;
}

interface CategoryDonutProps {
  /** Ranked (desc) category rows for the current level. */
  rows: DonutRow[];
  total: number;
}

/**
 * Donut of the top category totals (top 7 + "Other") with the period total in
 * the center. Tapping a slice enlarges it and shows its name + amount below,
 * mirroring the mobile `_PieSummary`.
 */
export function CategoryDonut({ rows, total }: CategoryDonutProps) {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);

  const slices = useMemo<DonutSlice[]>(() => {
    const top = rows.slice(0, MAX_SLICES).map((row) => ({
      name: row.name,
      amount: row.amount,
      color: row.color,
    }));
    const rest = rows.slice(MAX_SLICES);
    if (rest.length > 0) {
      top.push({
        name: "Other",
        amount: rest.reduce((sum, row) => sum + row.amount, 0),
        color: OTHER_COLOR,
      });
    }
    return top;
  }, [rows]);

  useEffect(() => {
    setSelectedIndex(null);
  }, [rows]);

  const selected =
    selectedIndex !== null && selectedIndex < slices.length
      ? slices[selectedIndex]
      : null;

  return (
    <section className="card p-4">
      <div className="relative h-[240px]">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={slices}
              dataKey="amount"
              nameKey="name"
              innerRadius="58%"
              outerRadius={(entry: DonutSlice) =>
                selected && entry.name === selected.name ? "88%" : "80%"
              }
              paddingAngle={slices.length > 1 ? 2 : 0}
              stroke="#ffffff"
              strokeWidth={2}
              isAnimationActive={false}
              onClick={(_, index) =>
                setSelectedIndex((current) => (current === index ? null : index))
              }
            >
              {slices.map((slice) => (
                <Cell key={slice.name} fill={slice.color} className="cursor-pointer" />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <p className="money max-w-[45%] truncate text-lg font-bold text-ink">
            {formatMoney(total)}
          </p>
          <p className="text-xs text-muted">Total expense</p>
        </div>
      </div>

      {selected ? (
        <div className="mt-2 flex items-center justify-center gap-2 border-t border-line pt-3">
          <span
            className="h-2.5 w-2.5 shrink-0 rounded-full"
            style={{ backgroundColor: selected.color }}
            aria-hidden
          />
          <p className="truncate text-sm font-medium text-ink">{selected.name}</p>
          <p className="money shrink-0 text-sm font-semibold text-ink">
            {formatMoney(selected.amount)}
          </p>
          <p className="shrink-0 text-xs text-muted">
            {total > 0 ? `${Math.round((selected.amount / total) * 100)}%` : ""}
          </p>
        </div>
      ) : null}
    </section>
  );
}
