"use client";

import {
  BarChart,
  Bar,
  XAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts";
import { formatCurrency } from "@/lib/utils";

const months = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

function mapIncome(data: any[]) {
  return data.map((i) => {
    const match = i.label?.match(/\d+/);
    const m = match ? Number(match[0]) : 0;
    return {
      name: months[m - 1] || i.label,
      amount: Number(i.amount || 0),
    };
  });
}

export function IncomeBar({ data }: any[]) {
  if (!data?.length) {
    return (
      <div className="bg-white p-4 rounded-2xl border border-gray-100">
        <p className="text-sm text-gray-500">No income data</p>
      </div>
    );
  }

  const chartData = mapIncome(data);

  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h3 className="mb-3 font-semibold">Income by Month</h3>

      <ResponsiveContainer width="100%" height={260}>
        <BarChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis dataKey="name" tick={{ fontSize: 12 }} />
          <Tooltip formatter={(v: number) => formatCurrency(v)} />
          <Bar dataKey="amount" fill="#22c55e" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
