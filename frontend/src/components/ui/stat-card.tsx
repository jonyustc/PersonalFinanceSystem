import type { LucideIcon } from "lucide-react";

type StatCardProps = {
  label: string;
  value: string;
  icon: LucideIcon;
  tone?: "green" | "amber" | "blue";
};

const tones = {
  green: "bg-brand-50 text-brand-700",
  amber: "bg-amber-50 text-amber-700",
  blue: "bg-sky-50 text-sky-700"
};

export function StatCard({ label, value, icon: Icon, tone = "green" }: StatCardProps) {
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-sm text-muted">{label}</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{value}</p>
        </div>
        <div className={`flex h-11 w-11 items-center justify-center rounded-md ${tones[tone]}`}>
          <Icon className="h-5 w-5" aria-hidden />
        </div>
      </div>
    </div>
  );
}
