"use client";

import { formatCurrency } from "@/lib/utils";

export function Heatmap({ data }: any[]) {
  if (!data?.length) return null;

  return (
    <div className="bg-white p-4 rounded-2xl border shadow-sm">
      <h3 className="mb-3 font-semibold">Spending Heatmap</h3>

      <div className="grid grid-cols-7 gap-2">
        {data.map((d, i) => (
          <div
            key={i}
            className="h-12 flex items-center justify-center text-xs rounded"
            style={{
              background:
                d.amount > 500
                  ? "#ef4444"
                  : d.amount > 200
                    ? "#f97316"
                    : "#22c55e",
              color: "white",
            }}
            title={`${d.date} - ${formatCurrency(d.amount)}`}
          >
            {new Date(d.date).getDate()}
          </div>
        ))}
      </div>
    </div>
  );
}
