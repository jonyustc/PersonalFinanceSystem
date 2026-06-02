"use client";

import {
  useInfiniteQuery,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { AnimatePresence, motion } from "framer-motion";
import {
  ArrowDownLeft,
  ArrowRightLeft,
  ArrowUpRight,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CreditCard,
  Plus,
  ReceiptText,
  Search,
  Tag,
  X,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { TransactionForm } from "@/components/transactions/transaction-form";
import { Button } from "@/components/ui/button";
import { cn, formatCurrency } from "@/lib/utils";
import {
  createTransaction,
  deleteTransaction,
  fetchAccounts,
  fetchCategories,
  fetchTransactionAnalytics,
  fetchTransactions,
  updateTransaction,
} from "@/services/finance-service";
import type {
  Account,
  Category,
  Transaction,
  TransactionFilters,
} from "@/types/api";

const today = new Date();

function toLocalDateInputValue(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

const todayIso = toLocalDateInputValue(today);

function dateFromIso(value?: string) {
  if (!value) return new Date();
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function shiftIsoDate(value: string | undefined, days: number) {
  const date = dateFromIso(value ?? todayIso);
  date.setDate(date.getDate() + days);
  return toLocalDateInputValue(date);
}

function displayDateLabel(value?: string) {
  const date = dateFromIso(value ?? todayIso);
  const todayDate = dateFromIso(todayIso);
  const yesterday = dateFromIso(todayIso);
  yesterday.setDate(todayDate.getDate() - 1);
  const tomorrow = dateFromIso(todayIso);
  tomorrow.setDate(todayDate.getDate() + 1);

  if (date.toDateString() === todayDate.toDateString()) return "Today";
  if (date.toDateString() === yesterday.toDateString()) return "Yesterday";
  if (date.toDateString() === tomorrow.toDateString()) return "Tomorrow";
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function TransactionExperience() {
  const queryClient = useQueryClient();
  const [filters, setFilters] = useState<TransactionFilters>({
    from_date: todayIso,
    to_date: todayIso,
    limit: 30,
  });
  const [searchDraft, setSearchDraft] = useState("");
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Transaction | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(
      () =>
        setFilters((current) => ({
          ...current,
          search: searchDraft || undefined,
          offset: 0,
        })),
      250,
    );
    return () => window.clearTimeout(timer);
  }, [searchDraft]);

  const accountsQuery = useQuery({
    queryKey: ["accounts"],
    queryFn: fetchAccounts,
  });
  const categoriesQuery = useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
  });
  const analyticsQuery = useQuery({
    queryKey: ["transactions", "analytics", filters.from_date, filters.to_date],
    queryFn: () => fetchTransactionAnalytics(filters),
  });
  const transactionQuery = useInfiniteQuery({
    queryKey: ["transactions", filters],
    queryFn: ({ pageParam = 0 }) =>
      fetchTransactions({ ...filters, offset: pageParam }),
    initialPageParam: 0,
    getNextPageParam: (last) => last.next_offset ?? undefined,
  });

  const accounts = accountsQuery.data ?? [];
  const categories = categoriesQuery.data ?? [];
  const activeAccounts = useMemo(
    () => accounts.filter((account) => account.is_active && !account.archived),
    [accounts],
  );
  const transactions =
    transactionQuery.data?.pages.flatMap((page) => page.items) ?? [];
  const analytics = analyticsQuery.data;
  const grouped = useMemo(
    () => groupTransactions(transactions),
    [transactions],
  );

  const quickCategories = useMemo(
    () =>
      categories
        .filter(
          (category) => category.type === "expense" && !category.parent_id,
        )
        .slice(0, 6),
    [categories],
  );

  async function save(payload: any) {
    if (editing) await updateTransaction(editing.id, payload);
    else await createTransaction(payload);
    setFormOpen(false);
    setEditing(null);
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["transactions"] }),
      queryClient.invalidateQueries({ queryKey: ["accounts"] }),
    ]);
  }

  async function remove(id: string) {
    if (!confirm("Delete this transaction and roll back its balance?")) return;
    await deleteTransaction(id);
    await queryClient.invalidateQueries({ queryKey: ["transactions"] });
  }

  function setTransactionDate(date: string) {
    setFilters((current) => ({
      ...current,
      from_date: date,
      to_date: date,
      offset: 0,
    }));
  }

  return (
    <div className="min-h-[calc(100vh-7rem)] space-y-5 pb-28 md:pb-6">
      <section className="sticky top-14 z-20 -mx-4 border-y border-line bg-surface/95 px-4 py-3 backdrop-blur md:top-0 md:mx-0 md:rounded-md md:border">
        <div className="grid gap-2 lg:grid-cols-[minmax(220px,1fr)_auto_auto_auto_auto]">
          <SmartSearchBar value={searchDraft} onChange={setSearchDraft} />

          <div className="flex h-11 items-center rounded-md border border-line bg-white">
            <button
              type="button"
              className="flex h-10 w-10 items-center justify-center text-muted hover:text-brand-700"
              onClick={() => setTransactionDate(shiftIsoDate(filters.from_date, -1))}
              title="Previous day"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <button
              type="button"
              className="min-w-36 border-x border-line px-3 text-center text-sm font-semibold text-ink"
              onClick={() => setTransactionDate(todayIso)}
              title="Go to today"
            >
              <span className="block leading-tight">{displayDateLabel(filters.from_date)}</span>
              <span className="block text-[11px] font-normal text-muted">{filters.from_date ?? todayIso}</span>
            </button>
            <button
              type="button"
              className="flex h-10 w-10 items-center justify-center text-muted hover:text-brand-700"
              onClick={() => setTransactionDate(shiftIsoDate(filters.from_date, 1))}
              title="Next day"
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>

          <select
            className="input h-11 min-w-32 bg-white text-sm capitalize"
            value={filters.type ?? ""}
            onChange={(event) =>
              setFilters((current) => ({
                ...current,
                type: (event.target.value || undefined) as TransactionFilters["type"],
                offset: 0,
              }))
            }
          >
            <option value="">All types</option>
            <option value="expense">Expense</option>
            <option value="income">Income</option>
            <option value="transfer">Transfer</option>
          </select>

          <select
            className="input h-11 min-w-40 bg-white text-sm"
            value={filters.account_id ?? ""}
            onChange={(event) =>
              setFilters((current) => ({
                ...current,
                account_id: event.target.value || undefined,
                offset: 0,
              }))
            }
          >
            <option value="">All accounts</option>
            {activeAccounts.map((account) => (
              <option key={account.id} value={account.id}>
                {account.name}
              </option>
            ))}
          </select>

          <button
            type="button"
            onClick={() => {
              setSearchDraft("");
              setFilters({ from_date: todayIso, to_date: todayIso, limit: 30 });
            }}
            className="inline-flex h-11 items-center justify-center rounded-md border border-line bg-white px-3 text-sm font-semibold text-muted"
          >
            Clear
          </button>

          <button
            type="button"
            onClick={() => {
              setEditing(null);
              setFormOpen(true);
            }}
            className="inline-flex h-11 items-center justify-center gap-2 rounded-md border border-brand-600 bg-brand-600 px-4 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-700"
          >
            <Plus className="h-4 w-4" />
            Add
          </button>
        </div>
      </section>

      <DaySummaryPanel
        analytics={analytics}
        loading={analyticsQuery.isLoading}
        transactionCount={transactions.length}
        selectedDate={filters.from_date ?? todayIso}
        filters={filters}
        accounts={activeAccounts}
        onClearType={() =>
          setFilters((current) => ({ ...current, type: undefined, offset: 0 }))
        }
        onClearAccount={() =>
          setFilters((current) => ({ ...current, account_id: undefined, offset: 0 }))
        }
      />

      <TransactionTimeline
        accounts={accounts}
        categories={categories}
        grouped={grouped}
        loading={transactionQuery.isLoading}
        onEdit={(transaction: Transaction) => {
          setEditing(transaction);
          setFormOpen(true);
        }}
        onDelete={remove}
      />

      {transactionQuery.hasNextPage ? (
        <div className="flex justify-center">
          <Button
            variant="secondary"
            onClick={() => transactionQuery.fetchNextPage()}
            disabled={transactionQuery.isFetchingNextPage}
          >
            {transactionQuery.isFetchingNextPage ? "Loading..." : "Load more"}
          </Button>
        </div>
      ) : null}

      <TransactionSidePanel
        open={formOpen}
        title={editing ? "Edit transaction" : "Add transaction"}
        onClose={() => {
          setFormOpen(false);
          setEditing(null);
        }}
        transaction={editing}
        accounts={activeAccounts}
        categories={categories}
        selectedDate={filters.to_date ?? todayIso}
        quickCategories={quickCategories}
        onSubmit={save}
      />
    </div>
  );
}

function DaySummaryPanel({
  analytics,
  loading,
  transactionCount,
  selectedDate,
  filters,
  accounts,
  onClearType,
  onClearAccount,
}: {
  analytics: any;
  loading: boolean;
  transactionCount: number;
  selectedDate: string;
  filters: TransactionFilters;
  accounts: Account[];
  onClearType: () => void;
  onClearAccount: () => void;
}) {
  const account = accounts.find((item) => item.id === filters.account_id);
  const chips = [
    filters.type
      ? { label: `Type: ${filters.type}`, onClear: onClearType }
      : null,
    account ? { label: `Account: ${account.name}`, onClear: onClearAccount } : null,
  ].filter(Boolean) as { label: string; onClear: () => void }[];

  return (
    <section className="rounded-md border border-line bg-white p-3 shadow-sm">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-sm font-semibold text-ink">
            {displayDateLabel(selectedDate)}
          </p>
          <p className="text-xs text-muted">
            {transactionCount} visible transactions
          </p>
        </div>
        <div className="grid grid-cols-3 gap-2 md:min-w-[420px]">
          <SummaryMetric label="Income" value={analytics?.total_income} tone="income" loading={loading} />
          <SummaryMetric label="Spent" value={analytics?.total_expense} tone="expense" loading={loading} />
          <SummaryMetric label="Net" value={analytics?.net_cashflow} tone="net" loading={loading} />
        </div>
      </div>

      {chips.length > 0 ? (
        <div className="mt-3 flex flex-wrap gap-2">
          {chips.map((chip) => (
            <button
              key={chip.label}
              type="button"
              onClick={chip.onClear}
              className="inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3 py-1.5 text-xs font-semibold text-muted hover:text-brand-700"
            >
              {chip.label}
              <X className="h-3 w-3" />
            </button>
          ))}
        </div>
      ) : null}
    </section>
  );
}

function SummaryMetric({
  label,
  value,
  tone,
  loading,
}: {
  label: string;
  value?: string;
  tone: "income" | "expense" | "net";
  loading: boolean;
}) {
  const colors = {
    income: "text-emerald-700",
    expense: "text-rose-700",
    net: "text-ink",
  };
  return (
    <div className="rounded-md bg-surface p-3">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className={cn("mt-1 truncate text-sm font-semibold", colors[tone])}>
        {loading ? "--" : formatCurrency(value ?? 0)}
      </p>
    </div>
  );
}

function SmartSearchBar({
  value,
  onChange,
}: {
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="relative min-w-0 flex-1">
      <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
      <input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder="Search merchant, note, amount, tags..."
        className="h-11 w-full rounded-full border border-line bg-white pl-10 pr-4 text-sm outline-none focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
      />
    </label>
  );
}

function TransactionTimeline({
  grouped,
  accounts,
  categories,
  loading,
  onEdit,
  onDelete,
}: any) {
  if (loading) return <SkeletonTimeline />;
  if (!grouped.length) return <EmptyState />;
  const totalCount = grouped.reduce(
    (sum: number, group: any) => sum + group.items.length,
    0,
  );
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between px-1 text-xs text-muted">
        <span>Timeline</span>
        <span>{totalCount} transactions loaded</span>
      </div>
      <AnimatePresence initial={false}>
        {grouped.map((group: any) => (
          <TransactionGroupSection
            key={group.key}
            group={group}
            accounts={accounts}
            categories={categories}
            onEdit={onEdit}
            onDelete={onDelete}
          />
        ))}
      </AnimatePresence>
    </div>
  );
}

function TransactionGroupSection({
  group,
  accounts,
  categories,
  onEdit,
  onDelete,
}: any) {
  return (
    <section className="space-y-2">
      <div className="flex items-center justify-between px-1">
        <h2 className="text-sm font-semibold text-ink">{group.label}</h2>
        <span className="text-xs font-medium text-muted">
          {formatCurrency(group.total)}
        </span>
      </div>
      <div className="space-y-2">
        {group.items.map((transaction: Transaction, index: number) => (
          <TransactionCard
            key={transaction.id}
            transaction={transaction}
            accounts={accounts}
            categories={categories}
            index={index}
            onEdit={() => onEdit(transaction)}
            onDelete={() => onDelete(transaction.id)}
          />
        ))}
      </div>
    </section>
  );
}

function TransactionCard({
  transaction,
  accounts,
  categories,
  index,
  onEdit,
  onDelete,
}: any) {
  const type = transaction.type ?? transaction.txn_type;
  const account = accounts.find(
    (item: Account) => item.id === transaction.account_id,
  );
  const category = categories.find(
    (item: Category) => item.id === transaction.category_id,
  );
  const merchant =
    transaction.merchant_name ||
    transaction.description ||
    (type === "transfer" ? "Transfer" : "Unlabeled transaction");
  const Icon =
    type === "income"
      ? ArrowDownLeft
      : type === "transfer"
        ? ArrowRightLeft
        : ArrowUpRight;
  return (
    <motion.article
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: Math.min(index * 0.025, 0.18) }}
      className="group rounded-md border border-line bg-white p-3 shadow-sm transition hover:-translate-y-0.5 hover:shadow-soft"
    >
      <div className="flex items-start gap-3">
        <div
          className={cn(
            "flex h-11 w-11 shrink-0 items-center justify-center rounded-md",
            type === "income"
              ? "bg-emerald-50 text-emerald-600"
              : type === "transfer"
                ? "bg-slate-100 text-slate-600"
                : "bg-rose-50 text-rose-600",
          )}
        >
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate font-semibold text-ink">{merchant}</p>
              <p className="truncate text-xs text-muted">
                {category?.name || "Uncategorized"} -{" "}
                {account?.name || "Unknown account"} -{" "}
                {humanTime(transaction.txn_date)}
              </p>
            </div>
            <p
              className={cn(
                "shrink-0 text-right text-base font-semibold",
                type === "income"
                  ? "text-emerald-600"
                  : type === "transfer"
                    ? "text-slate-600"
                    : "text-rose-600",
              )}
            >
              {type === "income" ? "+" : type === "expense" ? "-" : ""}
              {formatCurrency(transaction.amount, account?.currency)}
            </p>
          </div>
          <div className="mt-2 flex flex-wrap items-center gap-1.5">
            {transaction.is_recurring ? (
              <Badge icon={CalendarDays}>Recurring</Badge>
            ) : null}
            {transaction.is_split ? (
              <Badge icon={ReceiptText}>Split</Badge>
            ) : null}
            {type === "transfer" ? (
              <Badge icon={ArrowRightLeft}>Transfer</Badge>
            ) : null}
            {(transaction.tags ?? []).slice(0, 3).map((tag: string) => (
              <Badge key={tag} icon={Tag}>
                {tag}
              </Badge>
            ))}
          </div>
        </div>
      </div>
      <div className="mt-3 flex justify-end gap-2 opacity-100 md:opacity-0 md:transition md:group-hover:opacity-100">
        <button
          className="rounded-full bg-surface px-3 py-1.5 text-xs font-semibold text-muted"
          onClick={onEdit}
        >
          Edit
        </button>
        <button
          className="rounded-full bg-rose-50 px-3 py-1.5 text-xs font-semibold text-rose-600"
          onClick={onDelete}
        >
          Delete
        </button>
      </div>
    </motion.article>
  );
}

function Badge({ icon: Icon, children }: any) {
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-surface px-2 py-1 text-[11px] font-semibold text-muted">
      <Icon className="h-3 w-3" />
      {children}
    </span>
  );
}

function TransactionSidePanel({
  open,
  title,
  onClose,
  transaction,
  accounts,
  categories,
  selectedDate,
  quickCategories,
  onSubmit,
}: {
  open: boolean;
  title: string;
  onClose: () => void;
  transaction?: Transaction | null;
  accounts: Account[];
  categories: Category[];
  selectedDate: string;
  quickCategories: Category[];
  onSubmit: (payload: any) => Promise<void>;
}) {
  return (
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
                <p className="text-sm font-semibold text-slate-900">
                  {title}
                </p>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="inline-flex h-10 w-10 items-center justify-center rounded-full border border-line bg-slate-50 text-slate-700"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-3 pt-3">
              <TransactionForm
                transaction={transaction}
                accounts={accounts}
                categories={categories}
                selectedDate={selectedDate}
                quickCategories={quickCategories}
                autoFocusAmount
                onSubmit={onSubmit}
                onCancel={onClose}
              />
            </div>
          </motion.section>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}

function SkeletonTimeline() {
  return (
    <div className="space-y-3">
      {Array.from({ length: 7 }).map((_, i) => (
        <div
          key={i}
          className="h-24 animate-pulse rounded-md border border-line bg-white"
        />
      ))}
    </div>
  );
}

function EmptyState() {
  return (
    <div className="rounded-md border border-dashed border-line bg-white p-8 text-center">
      <CreditCard className="mx-auto h-10 w-10 text-brand-600" />
      <h2 className="mt-3 font-semibold">No transactions here</h2>
      <p className="mt-1 text-sm text-muted">
        Try a wider date range or add your first transaction.
      </p>
    </div>
  );
}

function groupTransactions(items: Transaction[]) {
  const map = new Map<
    string,
    { key: string; label: string; total: number; items: Transaction[] }
  >();
  for (const item of items) {
    const key = item.txn_date.slice(0, 10);
    if (!map.has(key))
      map.set(key, {
        key,
        label: humanDate(item.txn_date),
        total: 0,
        items: [],
      });
    const group = map.get(key)!;
    group.items.push(item);
    if ((item.type ?? item.txn_type) === "expense")
      group.total += Number(item.amount);
  }
  return Array.from(map.values());
}

function humanDate(value: string) {
  const date = new Date(value);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) return "Today";
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return "Yesterday";
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    month: "short",
    day: "numeric",
  });
}

function humanTime(value: string) {
  return new Date(value).toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
  });
}
