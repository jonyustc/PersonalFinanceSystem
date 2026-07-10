"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronDown, HandCoins, Handshake } from "lucide-react";
import { useEffect, useState } from "react";

import { EmptyPanel } from "@/components/ui/empty-panel";
import { MetricCard } from "@/components/ui/metric-card";
import { categoryVisual } from "@/lib/category-visuals";
import { formatMoney } from "@/lib/money";
import { cn } from "@/lib/utils";
import { fetchDebtSummary, fetchTransactions } from "@/services/finance-service";
import type { DebtParty, DebtType, Transaction } from "@/types/api";

const DEBT_ROW_LABELS: Record<DebtType, string> = {
  lent: "Lent",
  borrowed: "Borrowed",
  repaid_by_them: "They repaid",
  repaid_to_them: "You repaid",
};

// lent & repaid_to_them are money OUT of my pocket; the rest is money IN.
const MONEY_OUT: DebtType[] = ["lent", "repaid_to_them"];

function shortDate(value: string | null | undefined) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString("en-US", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function PartyRow({
  party,
  expanded,
  onToggle,
}: {
  party: DebtParty;
  expanded: boolean;
  onToggle: () => void;
}) {
  const { color } = categoryVisual(party.counterparty);
  const initial = party.counterparty.trim().charAt(0).toUpperCase() || "?";
  const lastDate = shortDate(party.last_txn_date);

  const transactionsQuery = useQuery({
    queryKey: ["debts", "party-transactions", party.counterparty],
    enabled: expanded,
    queryFn: () => fetchTransactions({ counterparty: party.counterparty, limit: 50 }),
  });

  const net =
    party.direction === "they_owe_me" ? (
      <span className="money font-semibold text-income">
        +{formatMoney(Math.abs(party.net_amount))}
      </span>
    ) : party.direction === "i_owe_them" ? (
      <span className="money font-semibold text-expense">
        -{formatMoney(Math.abs(party.net_amount))}
      </span>
    ) : (
      <span className="money font-semibold text-muted">Settled</span>
    );

  return (
    <div>
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center gap-3 px-4 py-3 text-left"
      >
        <span
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-bold"
          style={{ backgroundColor: `${color}1f`, color }}
        >
          {initial}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-medium text-ink">
            {party.counterparty}
          </span>
          <span className="block truncate text-xs text-muted">
            {party.txn_count} transaction{party.txn_count === 1 ? "" : "s"}
            {lastDate ? ` · last ${lastDate}` : ""}
          </span>
        </span>
        {net}
        <ChevronDown
          className={cn("h-4 w-4 shrink-0 text-muted transition-transform", expanded && "rotate-180")}
        />
      </button>

      {expanded ? (
        <div className="space-y-2 px-4 pb-3 pl-[68px]">
          {transactionsQuery.isLoading ? (
            <p className="text-xs text-muted">Loading transactions…</p>
          ) : transactionsQuery.isError ? (
            <p className="text-xs text-expense">Could not load transactions.</p>
          ) : (transactionsQuery.data?.items.length ?? 0) === 0 ? (
            <p className="text-xs text-muted">No transactions found.</p>
          ) : (
            transactionsQuery.data?.items.map((txn: Transaction) => {
              const debtType = txn.debt_type ?? null;
              const out = debtType ? MONEY_OUT.includes(debtType) : txn.type === "expense";
              const amount = Math.abs(Number(txn.amount || 0));
              return (
                <div key={txn.id} className="flex items-baseline gap-2 text-xs">
                  <span className="w-14 shrink-0 text-muted">
                    {shortDate(txn.txn_date)?.replace(/, \d{4}$/, "") ?? "—"}
                  </span>
                  <span className="shrink-0 font-semibold text-ink">
                    {debtType ? DEBT_ROW_LABELS[debtType] : "Other"}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-muted">
                    {txn.description || ""}
                  </span>
                  <span
                    className={cn(
                      "money shrink-0 font-semibold",
                      out ? "text-expense" : "text-income",
                    )}
                  >
                    {out ? "-" : "+"}
                    {formatMoney(amount)}
                  </span>
                </div>
              );
            })
          )}
        </div>
      ) : null}
    </div>
  );
}

export default function LoansPage() {
  const queryClient = useQueryClient();
  const [expandedParty, setExpandedParty] = useState<string | null>(null);

  const summaryQuery = useQuery({
    queryKey: ["debts", "summary"],
    queryFn: fetchDebtSummary,
  });

  // Any transaction mutation elsewhere in the app refreshes the loan ledger.
  useEffect(() => {
    const invalidate = () => queryClient.invalidateQueries({ queryKey: ["debts"] });
    window.addEventListener("finance:data-mutated", invalidate);
    return () => window.removeEventListener("finance:data-mutated", invalidate);
  }, [queryClient]);

  const summary = summaryQuery.data;
  const parties = summary?.parties ?? [];

  return (
    <div className="mx-auto w-full max-w-2xl space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <MetricCard
          icon={HandCoins}
          label="They owe you"
          value={formatMoney(summary?.total_receivable ?? 0)}
          tone="income"
        />
        <MetricCard
          icon={Handshake}
          label="You owe"
          value={formatMoney(summary?.total_payable ?? 0)}
          tone="expense"
        />
      </div>

      {summaryQuery.isLoading ? (
        <div className="card px-4 py-8 text-center text-sm text-muted">Loading loans…</div>
      ) : summaryQuery.isError ? (
        <div className="card px-4 py-8 text-center text-sm text-expense">
          Could not load the loan summary.
        </div>
      ) : parties.length === 0 ? (
        <EmptyPanel
          icon={HandCoins}
          title="No loans tracked"
          body="Add a transaction with the Loan / IOU option to track money you lend or borrow"
        />
      ) : (
        <div className="card divide-y divide-line">
          {parties.map((party) => (
            <PartyRow
              key={party.counterparty}
              party={party}
              expanded={expandedParty === party.counterparty}
              onToggle={() =>
                setExpandedParty((current) =>
                  current === party.counterparty ? null : party.counterparty,
                )
              }
            />
          ))}
        </div>
      )}
    </div>
  );
}
