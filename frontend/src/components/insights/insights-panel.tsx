"use client";

import { AlertTriangle, CheckCircle2, Info } from "lucide-react";
import type { Insight } from "@/lib/insights";

function iconByType(type: Insight["type"]) {
  if (type === "warning") return AlertTriangle;
  if (type === "success") return CheckCircle2;
  return Info;
}

function colorByType(type: Insight["type"]) {
  if (type === "warning") return "bg-expense-soft text-expense";
  if (type === "success") return "bg-income-soft text-income";
  return "bg-brand-600/15 text-brand-700";
}

export function InsightsPanel({ items }: { items: Insight[] }) {
  if (!items?.length) {
    return (
      <div className="bg-card p-4 rounded-2xl border border-line">
        <p className="text-sm text-muted">No insights yet</p>
      </div>
    );
  }

  return (
    <div className="bg-card p-4 rounded-2xl border border-line shadow-sm space-y-3">
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
