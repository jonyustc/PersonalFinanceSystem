import { cn } from "@/lib/utils";

interface ProgressPillProps {
  /** 0..1 (values above 1 are clamped and rendered full) */
  fraction: number;
  color?: string;
  className?: string;
}

// Pill-shaped progress bar with utilization coloring, same as mobile:
// >=90% expense red, >=60% warning amber, else brand teal.
export function utilizationColor(fraction: number): string {
  if (fraction >= 0.9) return "#b91c1c";
  if (fraction >= 0.6) return "#b45309";
  return "#0f766e";
}

export function ProgressPill({ fraction, color, className }: ProgressPillProps) {
  const clamped = Math.max(0, Math.min(1, fraction));

  return (
    <div className={cn("h-2 w-full overflow-hidden rounded-full bg-line", className)}>
      <div
        className="h-full rounded-full transition-[width] duration-500"
        style={{
          width: `${clamped * 100}%`,
          backgroundColor: color ?? utilizationColor(fraction),
        }}
      />
    </div>
  );
}
