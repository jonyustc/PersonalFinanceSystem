"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";

import { cn } from "@/lib/utils";

import type { Granularity } from "./report-period";

const GRANULARITIES: { value: Granularity; label: string }[] = [
  { value: "week", label: "Week" },
  { value: "month", label: "Month" },
  { value: "year", label: "Year" },
];

interface PeriodControlsProps {
  granularity: Granularity;
  label: string;
  nextDisabled: boolean;
  onGranularityChange: (granularity: Granularity) => void;
  onPrevious: () => void;
  onNext: () => void;
}

/**
 * Week | Month | Year segmented pill plus the previous/next range navigator.
 * Mirrors the mobile reports header controls.
 */
export function PeriodControls({
  granularity,
  label,
  nextDisabled,
  onGranularityChange,
  onPrevious,
  onNext,
}: PeriodControlsProps) {
  return (
    <div className="space-y-3">
      <div className="card grid grid-cols-3 gap-1 p-1">
        {GRANULARITIES.map((option) => {
          const selected = option.value === granularity;
          return (
            <button
              key={option.value}
              type="button"
              aria-pressed={selected}
              onClick={() => onGranularityChange(option.value)}
              className={cn(
                "rounded-xl py-2 text-sm transition",
                selected
                  ? "bg-brand-600/15 font-semibold text-brand-700"
                  : "font-medium text-muted hover:text-ink",
              )}
            >
              {option.label}
            </button>
          );
        })}
      </div>

      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={onPrevious}
          title="Previous period"
          aria-label="Previous period"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-brand-600/10 text-brand-700 transition hover:bg-brand-600/20"
        >
          <ChevronLeft className="h-5 w-5" />
        </button>
        <p className="min-w-0 flex-1 truncate text-center text-sm font-semibold text-ink">
          {label}
        </p>
        <button
          type="button"
          onClick={onNext}
          disabled={nextDisabled}
          title="Next period"
          aria-label="Next period"
          className={cn(
            "flex h-10 w-10 shrink-0 items-center justify-center rounded-xl transition",
            nextDisabled
              ? "cursor-not-allowed bg-line/60 text-muted/50"
              : "bg-brand-600/10 text-brand-700 hover:bg-brand-600/20",
          )}
        >
          <ChevronRight className="h-5 w-5" />
        </button>
      </div>
    </div>
  );
}
