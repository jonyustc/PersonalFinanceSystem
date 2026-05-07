"use client";

import { formatCurrency } from "@/lib/utils";
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";

const COLORS = [
  "#7c3aed",
  "#0ea5e9",
  "#22c55e",
  "#f97316",
  "#ef4444",
  "#6366f1",
  "#f59e0b",
];

export type ExpenseSlice = {
  id: string;
  label: string;
  value: number;
  childrenCount?: number;
};

export function ExpenseHierarchyChart({
  data,
  selectedId,
  onSliceClick,
}: {
  data: ExpenseSlice[];
  selectedId?: string | null;
  onSliceClick: (id: string) => void;
}) {
  if (!data?.length) {
    return (
      <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
        <p className="text-sm text-slate-500">
          No expense categories found for this period.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-sm text-slate-500">Expense hierarchy</p>
          <h2 className="mt-1 text-lg font-semibold text-slate-900">
            Tap a category to explore
          </h2>
        </div>
      </div>

      <div className="mt-5 h-[320px]">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="label"
              innerRadius={64}
              outerRadius={110}
              paddingAngle={4}
              onClick={(payload: any) =>
                payload?.payload?.id && onSliceClick(payload.payload.id)
              }
              animationDuration={600}
              label={(entry) => entry.label}
            >
              {data.map((entry, index) => (
                <Cell
                  key={entry.id}
                  fill={COLORS[index % COLORS.length]}
                  stroke={entry.id === selectedId ? "#111827" : "transparent"}
                  strokeWidth={entry.id === selectedId ? 3 : 1}
                />
              ))}
            </Pie>
            <Tooltip
              formatter={(value: number, name: string) => [
                formatCurrency(value),
                name,
              ]}
              contentStyle={{
                borderRadius: 18,
                borderColor: "rgba(148,163,184,0.16)",
                backgroundColor: "#ffffff",
                boxShadow: "0 20px 45px rgba(15,23,42,0.08)",
              }}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        {data.slice(0, 4).map((item) => (
          <button
            key={item.id}
            type="button"
            onClick={() => onSliceClick(item.id)}
            className="rounded-3xl border border-slate-200 p-4 text-left transition hover:border-slate-300"
          >
            <p className="text-sm font-semibold text-slate-900">{item.label}</p>
            <p className="mt-2 text-sm text-slate-500">
              {formatCurrency(item.value)}
            </p>
            <p className="mt-1 text-xs text-slate-400">
              {item.childrenCount ?? 0} subcategories
            </p>
          </button>
        ))}
      </div>
    </div>
  );
}
