"use client";

import { Modal } from "@/components/ui/modal";
import { formatMoney } from "@/lib/money";
import type { Transaction } from "@/types/api";

export function ExpenseDrilldownDrawer({
  open,
  categoryName,
  transactions,
  loading,
  onClose,
}: {
  open: boolean;
  categoryName: string;
  transactions: Transaction[];
  loading: boolean;
  onClose: () => void;
}) {
  const total = transactions.reduce(
    (sum, transaction) => sum + Number(transaction.amount ?? 0),
    0,
  );

  return (
    <Modal
      open={open}
      title={`Transactions for ${categoryName}`}
      onClose={onClose}
    >
      <div className="space-y-3">
        {loading ? (
          <div className="space-y-2">
            {Array.from({ length: 4 }).map((_, index) => (
              <div
                key={index}
                className="h-14 animate-pulse rounded-2xl bg-line/60"
              />
            ))}
          </div>
        ) : transactions.length === 0 ? (
          <div className="rounded-2xl border border-line bg-surface p-6 text-center text-sm text-muted">
            No transactions found for this period.
          </div>
        ) : (
          <>
            <div className="flex items-baseline justify-between rounded-2xl bg-surface px-3 py-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted">
                {transactions.length} transaction
                {transactions.length === 1 ? "" : "s"}
              </p>
              <p className="money text-sm font-bold text-expense">
                {formatMoney(total)}
              </p>
            </div>
            <div className="divide-y divide-line rounded-2xl border border-line">
              {transactions.map((transaction) => (
                <article
                  key={transaction.id}
                  className="flex items-start justify-between gap-3 p-3"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-ink">
                      {transaction.merchant_name ||
                        transaction.description ||
                        "Unnamed expense"}
                    </p>
                    <p className="mt-0.5 text-xs text-muted">
                      {new Date(transaction.txn_date).toLocaleDateString(
                        "en-US",
                        { month: "short", day: "numeric", year: "numeric" },
                      )}
                      {transaction.tags?.length
                        ? ` · ${transaction.tags.join(", ")}`
                        : ""}
                    </p>
                  </div>
                  <p className="money shrink-0 text-sm font-semibold text-expense">
                    -{formatMoney(transaction.amount)}
                  </p>
                </article>
              ))}
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
