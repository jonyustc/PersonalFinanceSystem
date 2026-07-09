import type { LucideIcon } from "lucide-react";

import { cn } from "@/lib/utils";

interface EmptyPanelProps {
  icon: LucideIcon;
  title: string;
  body?: string;
  action?: React.ReactNode;
  className?: string;
}

export function EmptyPanel({ icon: Icon, title, body, action, className }: EmptyPanelProps) {
  return (
    <div className={cn("card flex flex-col items-center px-6 py-10 text-center", className)}>
      <span className="mb-4 flex h-[72px] w-[72px] items-center justify-center rounded-full bg-brand-600/10 text-brand-700">
        <Icon className="h-8 w-8" />
      </span>
      <p className="text-sm font-bold text-ink">{title}</p>
      {body ? <p className="mt-1 max-w-xs text-xs text-muted">{body}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}
