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

export function NetWorthLine({ data }: any[]) {
  if (!data?.length) {
    return (
      <div className="bg-white p-4 rounded-2xl border border-gray-100">
        <p className="text-sm text-gray-500">No trend data</p>
      </div>
    );
  }

  const chartData = data.map((t) => ({
    name: t.period, // e.g., "2026-05"
    value: Number(t.amount || 0),
  }));

  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h3 className="mb-3 font-semibold">Net Worth Trend</h3>

      <ResponsiveContainer width="100%" height={260}>
        <LineChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis dataKey="name" tick={{ fontSize: 12 }} />
          <Tooltip formatter={(v: number) => formatCurrency(v)} />
          <Line dataKey="value" stroke="#3b82f6" strokeWidth={2} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
