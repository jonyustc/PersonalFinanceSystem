"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { AnimatePresence, motion } from "framer-motion";
import { Plus, X } from "lucide-react";
import { useMemo, useState } from "react";

import { TransactionForm } from "@/components/transactions/transaction-form";
import {
  createTransaction,
  fetchAccounts,
  fetchCategories,
} from "@/services/finance-service";
import type { Category, TransactionCreatePayload } from "@/types/api";

function todayInputValue() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function GlobalTransactionCta() {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);

  // Prefetched (not gated on `open`) so the sheet opens with data ready —
  // logging a transaction should never wait on a spinner.
  const accountsQuery = useQuery({
    queryKey: ["accounts"],
    queryFn: fetchAccounts,
  });

  const categoriesQuery = useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
  });

  const accounts = accountsQuery.data ?? [];
  const categories = categoriesQuery.data ?? [];
  const quickCategories = useMemo(
    () =>
      categories
        .filter((category: Category) => category.type === "expense" && !category.parent_id)
        .slice(0, 6),
    [categories],
  );

  async function save(payload: TransactionCreatePayload) {
    await createTransaction(payload);
    setOpen(false);
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["transactions"] }),
      queryClient.invalidateQueries({ queryKey: ["accounts"] }),
      queryClient.invalidateQueries({ queryKey: ["dashboard"] }),
    ]);
    window.dispatchEvent(new Event("finance:data-mutated"));
  }

  return (
    <>
      {/* FAB — sits above the mobile bottom nav; standard corner position on desktop */}
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-[calc(5rem+var(--safe-bottom))] right-4 z-30 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-brand-600 text-white shadow-fab transition hover:bg-brand-700 active:scale-95 focus:outline-none focus:ring-4 focus:ring-brand-100 lg:bottom-6 lg:right-6"
        title="Add transaction"
      >
        <Plus className="h-7 w-7" />
      </button>

      <AnimatePresence>
        {open ? (
          <motion.div
            className="fixed inset-0 z-50 bg-slate-950/40"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={(event) => {
              if (event.target === event.currentTarget) setOpen(false);
            }}
          >
            {/* Bottom sheet on mobile, right panel on desktop */}
            <motion.section
              className="absolute inset-x-0 bottom-0 flex h-[94dvh] w-full flex-col rounded-t-3xl bg-card sm:inset-y-0 sm:left-auto sm:right-0 sm:h-full sm:max-w-xl sm:rounded-none sm:ring-1 sm:ring-line"
              initial={{ y: 480, opacity: 0.6 }}
              animate={{ y: 0, opacity: 1 }}
              exit={{ y: 480, opacity: 0 }}
              transition={{ type: "spring", stiffness: 340, damping: 32 }}
            >
              <div className="mx-auto mt-2 h-1.5 w-10 rounded-full bg-line sm:hidden" />
              <div className="flex items-center justify-between px-5 pb-2 pt-3">
                <p className="text-base font-bold text-ink">Add transaction</p>
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="rounded-full p-2 text-muted hover:bg-surface"
                  aria-label="Close"
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-3 sm:px-5">
                {accountsQuery.isLoading || categoriesQuery.isLoading ? (
                  <div className="space-y-3">
                    {Array.from({ length: 6 }).map((_, index) => (
                      <div
                        key={index}
                        className="h-14 animate-pulse rounded-xl bg-surface"
                      />
                    ))}
                  </div>
                ) : (
                  <TransactionForm
                    accounts={accounts}
                    categories={categories}
                    selectedDate={todayInputValue()}
                    quickCategories={quickCategories}
                    autoFocusAmount
                    onSubmit={save}
                    onCancel={() => setOpen(false)}
                  />
                )}
              </div>
            </motion.section>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </>
  );
}
