"use client";

import {
  LineChart,
  Line,
  XAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts";
import { formatCurrency } from "@/lib/utils";

export function DailyTrend({ data }: any[]) {
  if (!data?.length) {
    return <p className="text-sm text-gray-500">No data</p>;
  }

  return (
    <div className="bg-white p-4 rounded-2xl border shadow-sm">
      <h3 className="mb-3 font-semibold">Daily Spending Trend</h3>

      <ResponsiveContainer width="100%" height={260}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis dataKey="date" tick={{ fontSize: 12 }} />
          <Tooltip formatter={(v: number) => formatCurrency(v)} />
          <Line dataKey="amount" stroke="#ef4444" strokeWidth={2} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
