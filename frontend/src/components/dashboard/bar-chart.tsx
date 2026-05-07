import { formatCurrency } from "@/lib/utils";

import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
} from "recharts";
const currencyTooltip = (value: unknown) => formatCurrency(Number(value ?? 0));

export function IncomeExpenseChart({ data }: any) {
  const chartData = [
    {
      name: "This Month",
      income: data.total_income_this_month || 0,
      expense: data.total_expense_this_month || 0,
    },
  ];

  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h3 className="mb-3 font-semibold">Income vs Expense</h3>

      <ResponsiveContainer width="100%" height={260}>
        <BarChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />

          <XAxis dataKey="name" tick={{ fontSize: 12 }} />

          <Tooltip
            formatter={currencyTooltip}
            contentStyle={{
              borderRadius: "8px",
              border: "1px solid #e5e7eb",
            }}
          />

          <Bar dataKey="income" fill="#22c55e" radius={[4, 4, 0, 0]} />
          <Bar dataKey="expense" fill="#ef4444" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
