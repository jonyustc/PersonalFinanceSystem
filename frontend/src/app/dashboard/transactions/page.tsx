"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CalendarDays, Edit3, Plus, RefreshCw, Trash2, TrendingDown, TrendingUp, WalletCards } from "lucide-react";

import { TransactionForm } from "@/components/transactions/transaction-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
import {
  createTransaction,
  deleteTransaction,
  fetchAccounts,
  fetchCategories,
  fetchMonthlySummary,
  fetchTransactions,
  updateTransaction
} from "@/services/finance-service";
import type {
  Account,
  Category,
  MonthlySummary,
  Transaction,
  TransactionCreatePayload,
  TransactionFilters,
  TransactionUpdatePayload
} from "@/types/api";

function toDateInput(value: Date) {
  return value.toISOString().slice(0, 10);
}

const now = new Date();

export default function TransactionsPage() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [summary, setSummary] = useState<MonthlySummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [defaultType, setDefaultType] = useState<"income" | "expense">("expense");
  const [editingTransaction, setEditingTransaction] = useState<Transaction | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [filters, setFilters] = useState<TransactionFilters>({
    start_date: toDateInput(new Date(now.getFullYear(), now.getMonth(), 1)),
    end_date: toDateInput(new Date(now.getFullYear(), now.getMonth() + 1, 0)),
    limit: 50,
    offset: 0
  });

  const accountById = useMemo(() => new Map(accounts.map((account) => [account.id, account])), [accounts]);
  const categoryById = useMemo(() => new Map(categories.map((category) => [category.id, category])), [categories]);

  const loadReferenceData = useCallback(async () => {
    const [accountRows, categoryRows] = await Promise.all([fetchAccounts(), fetchCategories()]);
    setAccounts(accountRows);
    setCategories(categoryRows);
  }, []);

  const loadTransactions = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [transactionRows, summaryRow] = await Promise.all([
        fetchTransactions({
          ...filters,
          start_date: filters.start_date ? new Date(`${filters.start_date}T00:00:00`).toISOString() : undefined,
          end_date: filters.end_date ? new Date(`${filters.end_date}T23:59:59`).toISOString() : undefined
        }),
        fetchMonthlySummary(now.getMonth() + 1, now.getFullYear())
      ]);
      setTransactions(transactionRows.items);
      setSummary(summaryRow);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to load transactions");
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    loadReferenceData().catch((err) => setError(err instanceof Error ? err.message : "Unable to load accounts or categories"));
  }, [loadReferenceData]);

  useEffect(() => {
    loadTransactions();
  }, [loadTransactions]);

  function openCreateModal(type: "income" | "expense") {
    setEditingTransaction(null);
    setDefaultType(type);
    setModalOpen(true);
  }

  function openEditModal(transaction: Transaction) {
    setEditingTransaction(transaction);
    setDefaultType(transaction.txn_type === "income" ? "income" : "expense");
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingTransaction(null);
  }

  async function handleSave(payload: TransactionCreatePayload | TransactionUpdatePayload) {
    if (editingTransaction) {
      await updateTransaction(editingTransaction.id, payload as TransactionUpdatePayload);
    } else {
      await createTransaction(payload as TransactionCreatePayload);
    }
    closeModal();
    await Promise.all([loadTransactions(), loadReferenceData()]);
  }

  async function handleDelete(transaction: Transaction) {
    const confirmed = window.confirm("Delete this transaction? Account balance will be adjusted.");
    if (!confirmed) return;

    setDeletingId(transaction.id);
    setError(null);
    try {
      await deleteTransaction(transaction.id);
      await Promise.all([loadTransactions(), loadReferenceData()]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to delete transaction");
    } finally {
      setDeletingId(null);
    }
  }

  function updateFilter(key: keyof TransactionFilters, value: string) {
    setFilters((current) => ({ ...current, [key]: value || undefined, offset: 0 }));
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Transactions</h1>
          <p className="mt-1 text-sm text-muted">Add income and expenses, filter activity, and track this month&apos;s cashflow.</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button variant="secondary" onClick={loadTransactions} disabled={loading}>
            <RefreshCw className="h-4 w-4" aria-hidden />
            Refresh
          </Button>
          <Button variant="secondary" onClick={() => openCreateModal("income")}>
            <TrendingUp className="h-4 w-4" aria-hidden />
            Add income
          </Button>
          <Button onClick={() => openCreateModal("expense")}>
            <Plus className="h-4 w-4" aria-hidden />
            Add expense
          </Button>
        </div>
      </div>

      <section className="grid gap-4 md:grid-cols-3">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Income this month</p>
            <TrendingUp className="h-4 w-4 text-brand-700" aria-hidden />
          </div>
          <p className="mt-2 text-2xl font-semibold text-ink">{formatCurrency(summary?.total_income ?? 0)}</p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Expense this month</p>
            <TrendingDown className="h-4 w-4 text-amber-700" aria-hidden />
          </div>
          <p className="mt-2 text-2xl font-semibold text-ink">{formatCurrency(summary?.total_expense ?? 0)}</p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Savings this month</p>
            <WalletCards className="h-4 w-4 text-sky-700" aria-hidden />
          </div>
          <p className="mt-2 text-2xl font-semibold text-ink">{formatCurrency(summary?.savings ?? 0)}</p>
        </div>
      </section>

      <section className="rounded-lg border border-line bg-white p-4 shadow-soft">
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">Start date</span>
            <input
              className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              type="date"
              value={filters.start_date ?? ""}
              onChange={(event) => updateFilter("start_date", event.target.value)}
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">End date</span>
            <input
              className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              type="date"
              value={filters.end_date ?? ""}
              onChange={(event) => updateFilter("end_date", event.target.value)}
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">Account</span>
            <select
              className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              value={filters.account_id ?? ""}
              onChange={(event) => updateFilter("account_id", event.target.value)}
            >
              <option value="">All accounts</option>
              {accounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name}
                </option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">Category</span>
            <select
              className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              value={filters.category_id ?? ""}
              onChange={(event) => updateFilter("category_id", event.target.value)}
            >
              <option value="">All categories</option>
              {categories.map((category) => (
                <option key={category.id} value={category.id}>
                  {category.name}
                </option>
              ))}
            </select>
          </label>
          <div className="flex items-end">
            <Button className="w-full" variant="secondary" onClick={() => setFilters({ limit: 50, offset: 0 })}>
              Clear filters
            </Button>
          </div>
        </div>
      </section>

      {error ? <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</p> : null}

      <section className="hidden overflow-hidden rounded-lg border border-line bg-white shadow-soft lg:block">
        <div className="grid grid-cols-[1fr_130px_150px_150px_130px] gap-4 border-b border-line px-5 py-3 text-xs font-semibold uppercase text-muted">
          <span>Description</span>
          <span>Type</span>
          <span>Account</span>
          <span className="text-right">Amount</span>
          <span className="text-right">Actions</span>
        </div>
        {loading ? <p className="px-5 py-6 text-sm text-muted">Loading transactions...</p> : null}
        {!loading && !transactions.length ? <p className="px-5 py-6 text-sm text-muted">No transactions match your filters.</p> : null}
        {transactions.map((transaction) => {
          const account = accountById.get(transaction.account_id);
          const category = transaction.category_id ? categoryById.get(transaction.category_id) : null;
          return (
            <div
              className="grid grid-cols-[1fr_130px_150px_150px_130px] items-center gap-4 border-b border-line px-5 py-4 text-sm last:border-0"
              key={transaction.id}
            >
              <div className="min-w-0">
                <p className="truncate font-semibold text-ink">{transaction.description || category?.name || "Transaction"}</p>
                <p className="truncate text-xs text-muted">
                  <CalendarDays className="mr-1 inline h-3 w-3" aria-hidden />
                  {new Date(transaction.txn_date).toLocaleString()}
                </p>
              </div>
              <span className={transaction.txn_type === "income" ? "font-medium text-brand-700" : "font-medium text-amber-700"}>
                {transaction.txn_type}
              </span>
              <span className="truncate text-muted">{account?.name ?? "Unknown"}</span>
              <span className="text-right font-semibold text-ink">{formatCurrency(transaction.amount, account?.currency ?? "USD")}</span>
              <div className="flex justify-end gap-2">
                <button className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink" onClick={() => openEditModal(transaction)} type="button">
                  <Edit3 className="h-4 w-4" aria-hidden />
                </button>
                <button
                  className="rounded-md p-2 text-muted hover:bg-red-50 hover:text-red-700 disabled:opacity-50"
                  disabled={deletingId === transaction.id}
                  onClick={() => handleDelete(transaction)}
                  type="button"
                >
                  <Trash2 className="h-4 w-4" aria-hidden />
                </button>
              </div>
            </div>
          );
        })}
      </section>

      <section className="grid gap-4 lg:hidden">
        {loading ? <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">Loading transactions...</p> : null}
        {!loading && !transactions.length ? (
          <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">No transactions match your filters.</p>
        ) : null}
        {transactions.map((transaction) => {
          const account = accountById.get(transaction.account_id);
          const category = transaction.category_id ? categoryById.get(transaction.category_id) : null;
          return (
            <article className="rounded-lg border border-line bg-white p-5 shadow-soft" key={transaction.id}>
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-sm font-medium text-muted">{category?.name ?? account?.name ?? "Transaction"}</p>
                  <h2 className="mt-1 truncate text-lg font-semibold text-ink">{transaction.description || transaction.txn_type}</h2>
                </div>
                <span className={transaction.txn_type === "income" ? "text-sm font-semibold text-brand-700" : "text-sm font-semibold text-amber-700"}>
                  {transaction.txn_type}
                </span>
              </div>
              <p className="mt-4 text-2xl font-semibold text-ink">{formatCurrency(transaction.amount, account?.currency ?? "USD")}</p>
              <p className="mt-2 text-sm text-muted">{new Date(transaction.txn_date).toLocaleString()}</p>
              <div className="mt-4 flex gap-2">
                <Button className="flex-1" variant="secondary" onClick={() => openEditModal(transaction)}>
                  <Edit3 className="h-4 w-4" aria-hidden />
                  Edit
                </Button>
                <Button className="flex-1" variant="secondary" disabled={deletingId === transaction.id} onClick={() => handleDelete(transaction)}>
                  <Trash2 className="h-4 w-4" aria-hidden />
                  Delete
                </Button>
              </div>
            </article>
          );
        })}
      </section>

      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingTransaction ? "Edit transaction" : defaultType === "income" ? "Add income" : "Add expense"}
        description="Balances update automatically after the transaction is saved."
      >
        <TransactionForm
          accounts={accounts}
          categories={categories}
          defaultType={defaultType}
          transaction={editingTransaction}
          onCancel={closeModal}
          onSubmit={handleSave}
        />
      </Modal>
    </div>
  );
}
