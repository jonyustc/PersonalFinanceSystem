"use client";

import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
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
  return (
    <Modal
      open={open}
      title={`Transactions for ${categoryName}`}
      onClose={onClose}
    >
      <div className="space-y-4">
        {loading ? (
          <div className="space-y-3">
            {Array.from({ length: 4 }).map((_, index) => (
              <div
                key={index}
                className="h-20 animate-pulse rounded-3xl bg-slate-100"
              />
            ))}
          </div>
        ) : transactions.length === 0 ? (
          <div className="rounded-3xl border border-slate-200 bg-slate-50 p-6 text-center text-sm text-slate-600">
            No transactions found for this category.
          </div>
        ) : (
          <div className="space-y-3">
            {transactions.map((transaction) => (
              <article
                key={transaction.id}
                className="rounded-3xl border border-slate-200 p-4 shadow-sm"
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-slate-900">
                      {transaction.merchant_name ||
                        transaction.description ||
                        "Unnamed expense"}
                    </p>
                    <p className="mt-1 text-sm text-slate-500">
                      {transaction.category_id
                        ? transaction.category_id
                        : "Uncategorized"}{" "}
                      •{" "}
                      {new Date(transaction.txn_date).toLocaleDateString(
                        "en-US",
                      )}
                    </p>
                  </div>
                  <p className="text-sm font-semibold text-rose-600">
                    -{formatCurrency(transaction.amount)}
                  </p>
                </div>
                <div className="mt-3 flex flex-wrap gap-2 text-xs text-slate-500">
                  <span>{transaction.account_id}</span>
                  {transaction.tags?.map((tag) => (
                    <span
                      key={tag}
                      className="rounded-full bg-slate-100 px-2 py-1"
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </article>
            ))}
          </div>
        )}
      </div>
      <button
        type="button"
        onClick={onClose}
        className="mt-6 inline-flex items-center justify-center rounded-full bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800"
      >
        Close
      </button>
    </Modal>
  );
}
