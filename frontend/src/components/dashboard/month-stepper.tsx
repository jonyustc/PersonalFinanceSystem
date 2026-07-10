"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";

function currentMonth() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function shiftMonth(month: string, delta: number) {
  const [year, monthNumber] = month.split("-").map(Number);
  const date = new Date(year, monthNumber - 1 + delta, 1);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabel(month: string) {
  const [year, monthNumber] = month.split("-").map(Number);
  return new Date(year, monthNumber - 1, 1).toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
}

interface MonthStepperProps {
  month: string;
  onChange: (month: string) => void;
}

export function MonthStepper({ month, onChange }: MonthStepperProps) {
  const atCurrentMonth = month >= currentMonth();

  return (
    <div className="flex h-9 items-center rounded-full border border-line bg-card">
      <button
        type="button"
        aria-label="Previous month"
        onClick={() => onChange(shiftMonth(month, -1))}
        className="flex h-9 w-9 items-center justify-center rounded-full text-muted transition hover:text-brand-700"
      >
        <ChevronLeft className="h-4 w-4" />
      </button>
      <span className="min-w-[104px] text-center text-xs font-semibold text-ink">
        {monthLabel(month)}
      </span>
      <button
        type="button"
        aria-label="Next month"
        disabled={atCurrentMonth}
        onClick={() => onChange(shiftMonth(month, 1))}
        className="flex h-9 w-9 items-center justify-center rounded-full text-muted transition hover:text-brand-700 disabled:cursor-not-allowed disabled:opacity-30"
      >
        <ChevronRight className="h-4 w-4" />
      </button>
    </div>
  );
}
