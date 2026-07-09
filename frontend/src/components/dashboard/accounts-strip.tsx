import Link from "next/link";

import { formatMoney } from "@/lib/money";
import type { SimpleDashboardAccount } from "@/types/api";

const TYPE_LABELS: Record<SimpleDashboardAccount["type"], string> = {
  CASH: "Cash",
  BANK: "Bank",
  MOBILE_BANKING: "Mobile banking",
};

interface AccountsStripProps {
  accounts: SimpleDashboardAccount[];
}

// Horizontally scrollable row of compact account cards, like the mobile
// dashboard's account carousel.
export function AccountsStrip({ accounts }: AccountsStripProps) {
  return (
    <div className="-mx-3 flex snap-x gap-3 overflow-x-auto px-3 pb-1">
      {accounts.map((account) => (
        <Link
          key={account.id}
          href="/dashboard/accounts"
          className="card min-w-[160px] shrink-0 snap-start p-4 transition hover:border-brand-600/40"
        >
          <p className="truncate text-sm font-semibold text-ink">{account.name}</p>
          <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-wide text-muted">
            {TYPE_LABELS[account.type] ?? account.type}
          </p>
          <p className="money mt-2 text-base font-bold text-ink">
            {formatMoney(account.balance, account.currency || "BDT")}
          </p>
        </Link>
      ))}
    </div>
  );
}
