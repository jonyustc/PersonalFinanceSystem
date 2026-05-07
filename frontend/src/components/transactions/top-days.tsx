"use client";

import { formatCurrency } from "@/lib/utils";

export function TopDays({ data }: { data: any[] }) {
  if (!data?.length) return null;

  const sorted = [...data].sort((a, b) => b.amount - a.amount).slice(0, 5);

  return (
    <div className="bg-white p-4 rounded-2xl border shadow-sm">
      <h3 className="mb-3 font-semibold">Top Spending Days</h3>

      {sorted.map((d, i) => (
        <div
          key={i}
          className="flex justify-between py-2 border-b last:border-none"
        >
          <span>{d.date}</span>
          <span className="font-medium">{formatCurrency(d.amount)}</span>
        </div>
      ))}
    </div>
  );
}
