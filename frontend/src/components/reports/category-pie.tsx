"use client";

import { PieChart, Pie, Tooltip, ResponsiveContainer, Cell } from "recharts";
import { formatCurrency } from "@/lib/utils";
const currencyTooltip = (value: unknown) => formatCurrency(Number(value ?? 0));

const COLORS = [
  "#6366f1",
  "#22c55e",
  "#f97316",
  "#ef4444",
  "#06b6d4",
  "#a855f7",
];

export function CategoryPie({ data }: { data: any[] }) {
  if (!data?.length) {
    return (
      <div className="bg-card p-4 rounded-2xl border border-line">
        <p className="text-sm text-muted">No category data</p>
      </div>
    );
  }

  return (
    <div className="bg-card p-4 rounded-2xl border border-line shadow-sm">
      <h3 className="mb-3 font-semibold">Expenses by Category</h3>

      <ResponsiveContainer width="100%" height={260}>
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="label" outerRadius={90}>
            {data.map((_: any, i: number) => (
              <Cell key={i} fill={COLORS[i % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip formatter={currencyTooltip} />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}
