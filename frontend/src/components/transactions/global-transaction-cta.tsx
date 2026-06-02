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

  const accountsQuery = useQuery({
    queryKey: ["accounts"],
    queryFn: fetchAccounts,
    enabled: open,
  });

  const categoriesQuery = useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
    enabled: open,
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
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-5 right-5 z-30 inline-flex h-14 w-14 items-center justify-center rounded-full bg-brand-600 text-white shadow-soft transition hover:bg-brand-700 focus:outline-none focus:ring-4 focus:ring-brand-100"
        title="Add transaction"
      >
        <Plus className="h-6 w-6" />
      </button>

      <AnimatePresence>
        {open ? (
          <motion.div
            className="fixed inset-0 z-40 bg-slate-950/35 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <motion.section
              className="absolute bottom-0 right-0 top-0 flex w-full flex-col bg-white shadow-2xl ring-1 ring-slate-200 sm:max-w-xl"
              initial={{ x: 520 }}
              animate={{ x: 0 }}
              exit={{ x: 520 }}
              transition={{ type: "spring", stiffness: 320, damping: 30 }}
            >
              <div className="flex items-center justify-between border-b border-line px-5 py-3">
                <div>
                  <p className="text-sm font-semibold text-slate-900">Add transaction</p>
                </div>
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="rounded-full p-2 text-slate-500 hover:bg-slate-100"
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-3 pt-3">
                {accountsQuery.isLoading || categoriesQuery.isLoading ? (
                  <div className="space-y-3">
                    {Array.from({ length: 6 }).map((_, index) => (
                      <div
                        key={index}
                        className="h-14 animate-pulse rounded-md bg-slate-100"
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
