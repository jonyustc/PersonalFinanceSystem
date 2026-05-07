"use client";

import { useQuery } from "@tanstack/react-query";
import {
  ArrowDownRight,
  ArrowUpRight,
  CalendarDays,
  ChevronRight,
  RefreshCcw,
  Sparkles,
  Wallet,
} from "lucide-react";
import { useMemo, useState } from "react";

import { ExpenseDrilldownDrawer } from "@/components/reports/expense-drilldown-drawer";
import {
  ExpenseHierarchyChart,
  type ExpenseSlice,
} from "@/components/reports/expense-hierarchy-chart";
import { NetWorthLine } from "@/components/reports/networth-line";
import { Heatmap } from "@/components/transactions/heatmap";
import { StatCard } from "@/components/ui/stat-card";
import { formatCurrency } from "@/lib/utils";
import {
  fetchCategorySpending,
  fetchCategoryTree,
  fetchNetWorthTrend,
  fetchTransactionAnalytics,
  fetchTransactions,
} from "@/services/finance-service";
import type { Category, Transaction, TransactionAnalytics } from "@/types/api";

const windows = [
  { key: "30", label: "Last 30 days" },
  { key: "90", label: "Last 90 days" },
  { key: "180", label: "Last 6 months" },
];

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

function findCategoryPath(
  nodes: Category[],
  targetId: string,
  path: Category[] = [],
): Category[] | null {
  for (const node of nodes) {
    const currentPath = [...path, node];
    if (node.id === targetId) return currentPath;
    if (node.children?.length) {
      const next = findCategoryPath(node.children, targetId, currentPath);
      if (next) return next;
    }
  }
  return null;
}

export default function ReportsPage() {
  const [range, setRange] = useState("30");
  const [selectedCategoryId, setSelectedCategoryId] = useState<string | null>(
    null,
  );
  const [activeCategory, setActiveCategory] = useState<Category | null>(null);

  const { fromDate, toDate } = useMemo(() => {
    const now = new Date();
    const start = new Date(now);
    start.setDate(now.getDate() - Number(range));
    return {
      fromDate: isoDate(start),
      toDate: isoDate(now),
    };
  }, [range]);

  const analyticsQuery = useQuery({
    queryKey: ["reports-analytics", fromDate, toDate],
    queryFn: () =>
      fetchTransactionAnalytics({ from_date: fromDate, to_date: toDate }),
    keepPreviousData: true,
  });

  const netWorthQuery = useQuery({
    queryKey: ["reports-net-worth"],
    queryFn: fetchNetWorthTrend,
  });

  const categoryTreeQuery = useQuery({
    queryKey: ["category-tree"],
    queryFn: fetchCategoryTree,
  });

  const categorySpendingQuery = useQuery({
    queryKey: ["category-spending", fromDate, toDate],
    queryFn: () =>
      fetchCategorySpending({ from_date: fromDate, to_date: toDate }),
  });

  const activeTransactionsQuery = useQuery({
    queryKey: ["drill-transactions", activeCategory?.id, fromDate, toDate],
    enabled: Boolean(activeCategory?.id),
    queryFn: () =>
      fetchTransactions({
        category_id: activeCategory?.id,
        from_date: fromDate,
        to_date: toDate,
        type: "expense",
      }),
    keepPreviousData: true,
  });

  const analytics = analyticsQuery.data as TransactionAnalytics | undefined;
  const netWorth = netWorthQuery.data || [];
  const categories = categoryTreeQuery.data ?? [];
  const categorySpending = categorySpendingQuery.data ?? [];

  const amountByCategory = useMemo(
    () =>
      new Map(
        categorySpending
          .filter((row) => row.id)
          .map((row) => [row.id as string, Number(row.amount)]),
      ),
    [categorySpending],
  );

  const selectedPath = useMemo(
    () =>
      selectedCategoryId
        ? (findCategoryPath(categories, selectedCategoryId) ?? [])
        : [],
    [categories, selectedCategoryId],
  );

  const selectedRoot = selectedPath[selectedPath.length - 1] ?? null;
  const currentLevel = selectedRoot?.children?.length
    ? selectedRoot.children
    : categories;

  const slices: ExpenseSlice[] = useMemo(
    () =>
      currentLevel
        .map((category) => ({
          id: category.id,
          label: category.name,
          value: amountByCategory.get(category.id) ?? 0,
          childrenCount: category.children?.length ?? 0,
        }))
        .filter((slice) => slice.value > 0),
    [currentLevel, amountByCategory],
  );

  const totalExpense = Number(analytics?.total_expense ?? 0);
  const currentTotal = selectedRoot
    ? Number(amountByCategory.get(selectedRoot.id) ?? 0)
    : slices.reduce((sum, slice) => sum + slice.value, 0);

  const breadcrumbPath = activeCategory
    ? (findCategoryPath(categories, activeCategory.id) ?? [])
    : selectedPath;

  const insightText = selectedRoot
    ? `${selectedRoot.name} represents ${totalExpense ? Math.round((currentTotal / totalExpense) * 100) : 0}% of your tracked spending.`
    : "Tap a category slice to reveal subcategories and the underlying transaction story.";

  const summaryStats = [
    {
      label: "Net cashflow",
      value: analytics?.net_cashflow ?? "0",
      icon: ArrowUpRight,
      tone: "green",
    },
    {
      label: "Income",
      value: analytics?.total_income ?? "0",
      icon: Wallet,
      tone: "blue",
    },
    {
      label: "Expense",
      value: analytics?.total_expense ?? "0",
      icon: ArrowDownRight,
      tone: "amber",
    },
    {
      label: "Avg daily spend",
      value: analytics?.average_daily_spending ?? "0",
      icon: Sparkles,
      tone: "blue",
    },
  ];

  const handleSliceClick = (id: string) => {
    const path = findCategoryPath(categories, id);
    if (!path) return;
    const node = path[path.length - 1];
    if (node.children?.length) {
      setSelectedCategoryId(id);
      setActiveCategory(null);
      return;
    }
    setActiveCategory(node);
  };

  return (
    <div className="space-y-6">
      <section className="sticky top-0 z-20 border-b border-slate-200/80 bg-white/95 backdrop-blur-sm py-4">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm uppercase tracking-[0.2em] text-slate-500">
                Reports
              </p>
              <h1 className="text-3xl font-semibold tracking-tight text-slate-900">
                Your spending story, made actionable
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-slate-600">
                Deep category stories, merchant signals and transaction
                drilldowns for smarter monthly choices.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {windows.map((option) => (
                <button
                  key={option.key}
                  type="button"
                  onClick={() => setRange(option.key)}
                  className={`rounded-full border px-4 py-2 text-sm transition ${
                    range === option.key
                      ? "border-slate-900 bg-slate-900 text-white"
                      : "border-slate-200 bg-white text-slate-700 hover:border-slate-300"
                  }`}
                >
                  {option.label}
                </button>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {summaryStats.map((stat) => (
            <StatCard
              key={stat.label}
              label={stat.label}
              value={stat.value}
              icon={stat.icon}
            />
          ))}
        </div>

        <div className="mt-6 grid gap-4 xl:grid-cols-[1.5fr_1fr]">
          <div className="space-y-4">
            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm text-slate-500">Expense insight</p>
                  <h2 className="mt-2 text-xl font-semibold text-slate-900">
                    {selectedRoot?.name ?? "Active spending"}
                  </h2>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedCategoryId(null);
                    setActiveCategory(null);
                  }}
                  className="inline-flex items-center gap-2 rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-700 hover:border-slate-300"
                >
                  <RefreshCcw className="h-4 w-4" /> Reset
                </button>
              </div>
              <p className="mt-4 text-sm leading-6 text-slate-600">
                {insightText}
              </p>
              <div className="mt-6">
                <div className="flex flex-wrap items-center gap-2 text-xs uppercase tracking-[0.18em] text-slate-500">
                  <span>Current view</span>
                  <ChevronRight className="h-3.5 w-3.5" />
                  <span>
                    {selectedRoot ? `${selectedRoot.name}` : "All expenses"}
                  </span>
                </div>
              </div>
            </div>

            <ExpenseHierarchyChart
              data={slices}
              selectedId={selectedCategoryId ?? activeCategory?.id}
              onSliceClick={handleSliceClick}
            />

            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <h3 className="text-base font-semibold text-slate-900">
                Drilldown navigation
              </h3>
              <div className="mt-4 flex flex-wrap gap-2 text-sm text-slate-600">
                <button
                  type="button"
                  onClick={() => {
                    setSelectedCategoryId(null);
                    setActiveCategory(null);
                  }}
                  className="rounded-full bg-slate-50 px-3 py-2"
                >
                  All expenses
                </button>
                {selectedPath.map((category) => (
                  <button
                    key={category.id}
                    type="button"
                    onClick={() => setSelectedCategoryId(category.id)}
                    className="rounded-full bg-slate-50 px-3 py-2"
                  >
                    {category.name}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="space-y-4">
            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-sm text-slate-500">Trend storytelling</p>
                  <h2 className="mt-2 text-xl font-semibold text-slate-900">
                    Spending heatmap
                  </h2>
                </div>
                <CalendarDays className="h-5 w-5 text-slate-400" />
              </div>
              <div className="mt-5">
                <Heatmap data={analytics?.expense_heatmap ?? []} />
              </div>
            </div>

            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-sm text-slate-500">Top merchants</p>
                  <h2 className="mt-2 text-xl font-semibold text-slate-900">
                    Merchant velocity
                  </h2>
                </div>
              </div>
              <div className="mt-4 space-y-3">
                {analytics?.top_merchants?.slice(0, 4).map((merchant) => (
                  <div
                    key={merchant.label}
                    className="flex justify-between rounded-3xl bg-slate-50 px-4 py-3"
                  >
                    <span className="text-sm font-medium text-slate-900">
                      {merchant.label}
                    </span>
                    <span className="text-sm text-slate-700">
                      {formatCurrency(merchant.amount)}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <p className="text-sm text-slate-500">Month-over-month</p>
              <div className="mt-5 h-64">
                <NetWorthLine data={netWorth} />
              </div>
            </div>
          </div>
        </div>
      </section>

      <ExpenseDrilldownDrawer
        open={Boolean(activeCategory)}
        categoryName={activeCategory?.name ?? "Category"}
        transactions={
          (activeTransactionsQuery.data as { items: Transaction[] } | undefined)
            ?.items ?? []
        }
        loading={activeTransactionsQuery.isFetching}
        onClose={() => setActiveCategory(null)}
      />
    </div>
  );
}
