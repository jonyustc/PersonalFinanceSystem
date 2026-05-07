import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
} from "recharts";

import { formatCurrency } from "@/lib/utils";
const currencyTooltip = (value: unknown) => formatCurrency(Number(value ?? 0));

export function MonthlyTrend({ data }: { data: any[] }) {
  if (!data || data.length === 0) {
    return (
      <div className="bg-white p-4 rounded-2xl border border-gray-100">
        <p className="text-sm text-gray-500">No trend data</p>
      </div>
    );
  }

  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h3 className="mb-3 font-semibold">Monthly Cashflow</h3>

      <ResponsiveContainer width="100%" height={260}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />

          <XAxis dataKey="month" tick={{ fontSize: 12 }} />

          <Tooltip formatter={currencyTooltip} />

          <Line dataKey="income" stroke="#22c55e" strokeWidth={2} />
          <Line dataKey="expense" stroke="#ef4444" strokeWidth={2} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
