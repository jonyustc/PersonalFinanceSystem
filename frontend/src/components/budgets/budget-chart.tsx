"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { formatCurrency } from "@/lib/utils";

type Props = {
  data: any[];
};
const currencyTooltip = (value: unknown) => formatCurrency(Number(value ?? 0));

export function BudgetChart({ data }: Props) {
  if (!data || data.length === 0) {
    return <p className="text-sm text-gray-500">No budget data</p>;
  }

  // ✅ FIXED MAPPING
  const chartData = data.map((b) => ({
    name: b.category_name || "Unknown",
    budget: Number(b.budget || 0), // ✅ FIX
    spent: Number(b.spent || 0),
  }));

  return (
    <div className="bg-white p-4 rounded border">
      <h2 className="font-semibold mb-3">Budget vs Actual</h2>

      <ResponsiveContainer width="100%" height={320}>
        <BarChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" />

          <XAxis dataKey="name" />
          <YAxis />

          <Tooltip formatter={currencyTooltip} />

          <Legend />

          {/* 🔵 Budget */}
          <Bar
            dataKey="budget"
            name="Budget"
            fill="#3b82f6"
            radius={[4, 4, 0, 0]}
          />

          {/* 🔥 Spent (dynamic color) */}
          <Bar dataKey="spent" name="Spent" radius={[4, 4, 0, 0]}>
            {chartData.map((entry, index) => (
              <Cell
                key={`cell-${index}`}
                fill={
                  entry.spent > entry.budget
                    ? "#ef4444" // 🔴 overspending
                    : "#22c55e" // 🟢 safe
                }
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
