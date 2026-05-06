import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";

import { formatCurrency } from "@/lib/utils";

const COLORS = ["#6366f1", "#22c55e", "#f97316", "#ef4444", "#06b6d4"];

export function CategoryPie({ data }: any[]) {
  if (!data || data.length === 0) {
    return (
      <div className="bg-white p-4 rounded-2xl border border-gray-100">
        <p className="text-sm text-gray-500">No category data</p>
      </div>
    );
  }

  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h3 className="mb-3 font-semibold">Expenses by Category</h3>

      <ResponsiveContainer width="100%" height={260}>
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="label" outerRadius={90}>
            {data.map((_: any, i: number) => (
              <Cell key={i} fill={COLORS[i % COLORS.length]} />
            ))}
          </Pie>

          <Tooltip formatter={(v: number) => formatCurrency(v)} />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}
