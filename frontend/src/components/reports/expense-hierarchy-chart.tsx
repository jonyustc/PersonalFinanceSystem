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
  title = "Expense categories",
  subtitle = "Tap a category to explore",
  total,
  onSliceClick,
}: {
  data: ExpenseSlice[];
  selectedId?: string | null;
  title?: string;
  subtitle?: string;
  total?: number;
  onSliceClick: (id: string) => void;
}) {
  const chartTotal =
    total ?? data.reduce((sum, item) => sum + Number(item.value || 0), 0);

  if (!data?.length) {
    return (
      <div className="rounded-md border border-dashed border-line bg-white p-6 text-center shadow-sm">
        <p className="text-sm text-slate-500">
          No expense categories found for this month.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-md border border-line bg-white p-3 shadow-sm sm:p-4">
      <div className="flex items-center justify-between gap-4">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase text-brand-700">Expense</p>
          <h2 className="mt-1 break-words text-lg font-semibold text-slate-900">{title}</h2>
          <p className="mt-1 text-sm text-slate-500">{subtitle}</p>
        </div>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(280px,0.95fr)] lg:items-center">
        <div className="relative h-[240px] min-w-0 sm:h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={data}
                dataKey="value"
                nameKey="label"
                innerRadius={76}
                outerRadius={116}
                paddingAngle={3}
                onClick={(payload: any) =>
                  payload?.payload?.id && onSliceClick(payload.payload.id)
                }
                animationDuration={600}
              >
                {data.map((entry, index) => (
                  <Cell
                    key={entry.id}
                    fill={COLORS[index % COLORS.length]}
                    stroke={entry.id === selectedId ? "#111827" : "#ffffff"}
                    strokeWidth={entry.id === selectedId ? 4 : 2}
                  />
                ))}
              </Pie>
              <Tooltip
                formatter={(value, name) => [
                  formatCurrency(Number(value ?? 0)),
                  String(name),
                ]}
                labelFormatter={() => ""}
                contentStyle={{
                  borderRadius: 8,
                  borderColor: "rgba(148,163,184,0.16)",
                  backgroundColor: "#ffffff",
                  boxShadow: "0 20px 45px rgba(15,23,42,0.08)",
                }}
              />
            </PieChart>
          </ResponsiveContainer>
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <div className="max-w-36 text-center">
              <p className="text-xs font-semibold uppercase text-slate-500">
                Total
              </p>
              <p className="mt-1 break-words text-lg font-semibold text-slate-900">
                {formatCurrency(chartTotal)}
              </p>
            </div>
          </div>
        </div>

        <div className="min-w-0 space-y-2">
          {data.map((item, index) => {
            const percent =
              chartTotal > 0 ? Math.round((item.value / chartTotal) * 100) : 0;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => onSliceClick(item.id)}
                className="w-full rounded-md border border-line bg-surface p-3 text-left transition hover:border-brand-200 hover:bg-brand-50"
              >
                <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-3">
                  <span className="flex min-w-0 items-start gap-2">
                    <span
                      className="mt-1 h-3 w-3 shrink-0 rounded-full"
                      style={{ backgroundColor: COLORS[index % COLORS.length] }}
                    />
                    <span className="min-w-0">
                      <span className="block break-words text-sm font-semibold text-slate-900">
                        {item.label}
                      </span>
                      <span className="block text-xs text-slate-500">
                        {percent}% of this view
                      </span>
                    </span>
                  </span>
                  <span className="min-w-0 sm:shrink-0 sm:text-right">
                    <span className="block break-words text-sm font-semibold text-slate-900">
                      {formatCurrency(item.value)}
                    </span>
                    <span className="block text-xs text-slate-500">
                      {(item.childrenCount ?? 0) > 0
                        ? `${item.childrenCount} sub`
                        : "Details"}
                    </span>
                  </span>
                </div>
                <div className="mt-2 h-1.5 rounded-full bg-white">
                  <div
                    className="h-1.5 rounded-full"
                    style={{
                      width: `${Math.min(percent, 100)}%`,
                      backgroundColor: COLORS[index % COLORS.length],
                    }}
                  />
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
