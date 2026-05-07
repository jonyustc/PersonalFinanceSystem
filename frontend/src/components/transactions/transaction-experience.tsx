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
  CreditCard,
  Filter,
  Plus,
  ReceiptText,
  Search,
  Sparkles,
  Tag,
  X,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
} from "recharts";

import { TransactionForm } from "@/components/transactions/transaction-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
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
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
  .toISOString()
  .slice(0, 10);
const todayIso = today.toISOString().slice(0, 10);

export function TransactionExperience() {
  const queryClient = useQueryClient();
  const [filters, setFilters] = useState<TransactionFilters>({
    from_date: monthStart,
    to_date: todayIso,
    limit: 30,
  });
  const [searchDraft, setSearchDraft] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [filterOpen, setFilterOpen] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);
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
  const transactions =
    transactionQuery.data?.pages.flatMap((page) => page.items) ?? [];
  const analytics = analyticsQuery.data;
  const grouped = useMemo(
    () => groupTransactions(transactions),
    [transactions],
  );

  const recentMerchants = useMemo(
    () =>
      Array.from(
        new Set(
          transactions
            .map((transaction) => transaction.merchant_name)
            .filter(Boolean) as string[],
        ),
      ).slice(0, 5),
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
    setModalOpen(false);
    setEditing(null);
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["transactions"] }),
      queryClient.invalidateQueries({ queryKey: ["accounts"] }),
    ]);
  }

  async function quickSave(payload: any) {
    const tempTransaction = {
      ...payload,
      id: `temp-${Date.now()}`,
      amount: String(payload.amount),
      txn_date: payload.txn_date || new Date().toISOString(),
      merchant_name: payload.merchant_name || null,
      tags: [],
    };

    const previous = queryClient.getQueryData<any>(["transactions", filters]);
    queryClient.setQueryData(["transactions", filters], (current: any) => {
      if (!current || !current.pages) return current;
      return {
        ...current,
        pages: current.pages.map((page: any, index: number) =>
          index === 0
            ? { ...page, items: [tempTransaction, ...page.items] }
            : page,
        ),
      };
    });

    try {
      await createTransaction(payload);
      setSheetOpen(false);
    } catch (error) {
      if (previous)
        queryClient.setQueryData(["transactions", filters], previous);
      throw error;
    } finally {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["transactions", filters] }),
        queryClient.invalidateQueries({
          queryKey: [
            "transactions",
            "analytics",
            filters.from_date,
            filters.to_date,
          ],
        }),
      ]);
    }
  }

  async function remove(id: string) {
    if (!confirm("Delete this transaction and roll back its balance?")) return;
    await deleteTransaction(id);
    await queryClient.invalidateQueries({ queryKey: ["transactions"] });
  }

  return (
    <div className="min-h-[calc(100vh-7rem)] space-y-5 pb-28 md:pb-6">
      <StickyFinanceHeader
        analytics={analytics}
        loading={analyticsQuery.isLoading}
      />

      <section className="sticky top-14 z-20 -mx-4 border-y border-line bg-surface/95 px-4 py-3 backdrop-blur md:top-0 md:mx-0 md:rounded-md md:border">
        <div className="flex gap-2 overflow-x-auto pb-1">
          <SmartSearchBar value={searchDraft} onChange={setSearchDraft} />
          <button
            className="inline-flex h-11 shrink-0 items-center gap-2 rounded-md border border-line bg-white px-3 text-sm font-semibold"
            onClick={() => setFilterOpen(true)}
          >
            <Filter className="h-4 w-4" />
            Filters
          </button>
          {(["expense", "income", "transfer"] as const).map((type) => (
            <button
              key={type}
              className={cn(
                "h-11 shrink-0 rounded-full border px-4 text-sm font-semibold capitalize",
                filters.type === type
                  ? "border-brand-600 bg-brand-50 text-brand-700"
                  : "border-line bg-white text-muted",
              )}
              onClick={() =>
                setFilters((current) => ({
                  ...current,
                  type: current.type === type ? undefined : type,
                }))
              }
            >
              {type}
            </button>
          ))}
          <button
            type="button"
            onClick={() => setSheetOpen(true)}
            className="inline-flex h-11 shrink-0 items-center gap-2 rounded-full border border-brand-600 bg-brand-600 px-4 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-700"
          >
            <Plus className="h-4 w-4" />
            Add transaction
          </button>
        </div>
      </section>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_360px]">
        <TransactionTimeline
          accounts={accounts}
          categories={categories}
          grouped={grouped}
          loading={transactionQuery.isLoading}
          onEdit={(transaction: Transaction) => {
            setEditing(transaction);
            setModalOpen(true);
          }}
          onDelete={remove}
        />
        <aside className="hidden space-y-4 xl:block">
          <CashflowWidget analytics={analytics} />
          <MerchantInsightCard analytics={analytics} />
        </aside>
      </div>

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

      <QuickAddTransactionFAB onClick={() => setSheetOpen(true)} />
      <QuickTransactionSheet
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        accounts={accounts}
        categories={categories}
        selectedDate={filters.to_date ?? todayIso}
        recentMerchants={recentMerchants}
        quickCategories={quickCategories}
        onSubmit={quickSave}
      />
      <FilterDrawer
        open={filterOpen}
        filters={filters}
        accounts={accounts}
        categories={categories}
        onClose={() => setFilterOpen(false)}
        onChange={setFilters}
      />

      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editing ? "Edit Transaction" : "Quick Add"}
      >
        <TransactionForm
          transaction={editing}
          accounts={accounts}
          categories={categories}
          selectedDate={filters.to_date ?? todayIso}
          onSubmit={save}
          onCancel={() => setModalOpen(false)}
        />
      </Modal>
    </div>
  );
}

function StickyFinanceHeader({
  analytics,
  loading,
}: {
  analytics: any;
  loading: boolean;
}) {
  const trend = (analytics?.spending_trend ?? []).map((point: any) => ({
    date: String(point.date).slice(5),
    amount: point.type === "expense" ? Number(point.amount) : 0,
  }));

  return (
    <section className="rounded-md bg-ink p-4 text-white shadow-soft md:p-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="flex items-center gap-2 text-sm font-medium text-white/70">
            <Sparkles className="h-4 w-4" /> This month
          </p>
          <h1 className="mt-1 text-2xl font-semibold">Transactions</h1>
          <p className="text-sm text-white/60">
            Your money timeline, insights, and quick actions.
          </p>
        </div>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <Metric
            label="Income"
            value={analytics?.total_income}
            tone="green"
            loading={loading}
          />
          <Metric
            label="Spent"
            value={analytics?.total_expense}
            tone="red"
            loading={loading}
          />
          <Metric
            label="Cashflow"
            value={analytics?.net_cashflow}
            tone="blue"
            loading={loading}
          />
        </div>
      </div>
      <div className="mt-5 h-28">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={trend}>
            <defs>
              <linearGradient id="spendFill" x1="0" x2="0" y1="0" y2="1">
                <stop offset="0" stopColor="#34d399" stopOpacity={0.35} />
                <stop offset="1" stopColor="#34d399" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid stroke="rgba(255,255,255,.08)" vertical={false} />
            <XAxis
              dataKey="date"
              tick={{ fill: "rgba(255,255,255,.55)", fontSize: 11 }}
              axisLine={false}
              tickLine={false}
            />
            <Tooltip
              formatter={(value: unknown) => formatCurrency(Number(value ?? 0))}
            />
            <Area
              dataKey="amount"
              stroke="#34d399"
              fill="url(#spendFill)"
              strokeWidth={2}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </section>
  );
}

function Metric({
  label,
  value,
  tone,
  loading,
}: {
  label: string;
  value?: string;
  tone: "green" | "red" | "blue";
  loading: boolean;
}) {
  const colors = {
    green: "text-emerald-300",
    red: "text-rose-300",
    blue: "text-sky-300",
  };
  return (
    <div className="rounded-md bg-white/8 p-3">
      <p className="text-xs text-white/60">{label}</p>
      <p className={cn("mt-1 text-lg font-semibold", colors[tone])}>
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
  return (
    <div className="space-y-5">
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

function CashflowWidget({ analytics }: any) {
  return (
    <section className="rounded-md border border-line bg-white p-4 shadow-soft">
      <h3 className="font-semibold text-ink">Habit Signal</h3>
      <p className="mt-2 text-sm text-muted">Average daily spend</p>
      <p className="mt-1 text-2xl font-semibold text-rose-600">
        {formatCurrency(analytics?.average_daily_spending ?? 0)}
      </p>
    </section>
  );
}

function MerchantInsightCard({ analytics }: any) {
  const merchants = analytics?.top_merchants ?? [];
  return (
    <section className="rounded-md border border-line bg-white p-4 shadow-soft">
      <h3 className="font-semibold text-ink">Top Merchants</h3>
      <div className="mt-3 space-y-2">
        {merchants.length ? (
          merchants.map((m: any) => (
            <div className="flex justify-between text-sm" key={m.label}>
              <span className="truncate text-muted">{m.label}</span>
              <span className="font-semibold">{formatCurrency(m.amount)}</span>
            </div>
          ))
        ) : (
          <p className="text-sm text-muted">No merchant patterns yet.</p>
        )}
      </div>
    </section>
  );
}

function FilterDrawer({
  open,
  filters,
  accounts,
  categories,
  onClose,
  onChange,
}: any) {
  return (
    <AnimatePresence>
      {open ? (
        <motion.div
          className="fixed inset-0 z-50 bg-ink/35"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
        >
          <motion.aside
            className="absolute bottom-0 right-0 max-h-[86vh] w-full overflow-y-auto rounded-t-2xl bg-white p-5 shadow-soft md:inset-y-0 md:max-h-none md:w-[420px] md:rounded-l-lg md:rounded-tr-none"
            initial={{ y: 80 }}
            animate={{ y: 0 }}
            exit={{ y: 80 }}
          >
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Smart Filters</h2>
              <button onClick={onClose}>
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="mt-5 grid gap-4">
              <FilterInput
                label="From"
                type="date"
                value={filters.from_date ?? ""}
                onChange={(value: string) =>
                  onChange({ ...filters, from_date: value || undefined })
                }
              />
              <FilterInput
                label="To"
                type="date"
                value={filters.to_date ?? ""}
                onChange={(value: string) =>
                  onChange({ ...filters, to_date: value || undefined })
                }
              />
              <FilterInput
                label="Merchant"
                value={filters.merchant ?? ""}
                onChange={(value: string) =>
                  onChange({ ...filters, merchant: value || undefined })
                }
              />
              <select
                className="input h-11"
                value={filters.account_id ?? ""}
                onChange={(e) =>
                  onChange({
                    ...filters,
                    account_id: e.target.value || undefined,
                  })
                }
              >
                <option value="">All accounts</option>
                {accounts.map((a: Account) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
              <select
                className="input h-11"
                value={filters.category_id ?? ""}
                onChange={(e) =>
                  onChange({
                    ...filters,
                    category_id: e.target.value || undefined,
                  })
                }
              >
                <option value="">All categories</option>
                {categories.map((c: Category) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
              <Button onClick={onClose}>Apply filters</Button>
            </div>
          </motion.aside>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}

function FilterInput({ label, value, type = "text", onChange }: any) {
  return (
    <label>
      <span className="mb-2 block text-sm font-medium text-ink">{label}</span>
      <input
        className="input h-11"
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </label>
  );
}

function QuickTransactionSheet({
  open,
  onClose,
  accounts,
  categories,
  selectedDate,
  recentMerchants,
  quickCategories,
  onSubmit,
}: {
  open: boolean;
  onClose: () => void;
  accounts: Account[];
  categories: Category[];
  selectedDate: string;
  recentMerchants: string[];
  quickCategories: Category[];
  onSubmit: (payload: any) => Promise<void>;
}) {
  return (
    <AnimatePresence>
      {open ? (
        <motion.div
          className="fixed inset-0 z-40 flex items-end justify-center bg-slate-950/40 px-4 py-4 backdrop-blur-sm"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
        >
          <motion.section
            className="w-full max-w-xl overflow-hidden rounded-t-3xl bg-white shadow-2xl ring-1 ring-slate-200 sm:rounded-3xl"
            initial={{ y: 300 }}
            animate={{ y: 0 }}
            exit={{ y: 300 }}
            transition={{ type: "spring", stiffness: 320, damping: 28 }}
          >
            <div className="flex items-center justify-between border-b border-line px-5 py-4">
              <div>
                <p className="text-sm font-semibold text-slate-900">
                  Quick entry
                </p>
                <p className="text-sm text-slate-500">
                  Add a transaction in seconds with amount-first entry.
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

            <div className="space-y-4 px-5 pb-5 pt-4">
              <TransactionForm
                accounts={accounts}
                categories={categories}
                selectedDate={selectedDate}
                recentMerchants={recentMerchants}
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

function QuickAddTransactionFAB({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="fixed bottom-5 right-5 z-30 inline-flex h-14 w-14 items-center justify-center rounded-full bg-brand-600 text-white shadow-soft transition hover:bg-brand-700 md:hidden"
    >
      <Plus className="h-6 w-6" />
    </button>
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
