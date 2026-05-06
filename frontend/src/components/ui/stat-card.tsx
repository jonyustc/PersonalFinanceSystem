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
  blue: "bg-sky-50 text-sky-700",
};

export function StatCard({ label, value, icon: Icon }: StatCardProps) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 hover:shadow-md transition">
      <div className="flex items-center justify-between">
        <span className="text-sm text-gray-500">{label}</span>
        <Icon className="h-4 w-4 text-gray-400" />
      </div>

      <p className="text-xl font-semibold mt-2">{formatCurrency(value || 0)}</p>
    </div>
  );
}
