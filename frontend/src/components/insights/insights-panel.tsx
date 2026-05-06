"use client";

import { AlertTriangle, CheckCircle2, Info } from "lucide-react";
import type { Insight } from "@/lib/insights";

function iconByType(type: Insight["type"]) {
  if (type === "warning") return AlertTriangle;
  if (type === "success") return CheckCircle2;
  return Info;
}

function colorByType(type: Insight["type"]) {
  if (type === "warning") return "bg-red-50 text-red-700";
  if (type === "success") return "bg-green-50 text-green-700";
  return "bg-blue-50 text-blue-700";
}

export function InsightsPanel({ items }: { items: Insight[] }) {
  if (!items?.length) {
    return (
      <div className="bg-white p-4 rounded-2xl border border-gray-100">
        <p className="text-sm text-gray-500">No insights yet</p>
      </div>
    );
  }

  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm space-y-3">
      <h3 className="font-semibold">AI Insights</h3>

      {items.map((it, i) => {
        const Icon = iconByType(it.type);
        const color = colorByType(it.type);

        return (
          <div key={i} className={`flex gap-3 p-3 rounded-xl ${color}`}>
            <Icon className="h-5 w-5 mt-0.5" />
            <div>
              <p className="font-medium">{it.title}</p>
              <p className="text-sm">{it.message}</p>
            </div>
          </div>
        );
      })}
    </div>
  );
}
