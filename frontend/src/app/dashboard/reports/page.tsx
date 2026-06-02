"use client";

import { useQuery } from "@tanstack/react-query";
import {
  ArrowDownRight,
  ArrowLeft,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { useMemo, useState } from "react";

import { ExpenseDrilldownDrawer } from "@/components/reports/expense-drilldown-drawer";
import {
  ExpenseHierarchyChart,
  type ExpenseSlice,
} from "@/components/reports/expense-hierarchy-chart";
import { cn, formatCurrency } from "@/lib/utils";
import {
  fetchBudgetSummary,
  fetchCategorySpending,
  fetchCategoryTree,
  fetchTransactionAnalytics,
  fetchTransactions,
} from "@/services/finance-service";
import type { Category, Transaction, TransactionAnalytics } from "@/types/api";

function monthKey(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function monthRange(month: string) {
  const [year, monthIndex] = month.split("-").map(Number);
  const first = new Date(year, monthIndex - 1, 1);
  const last = new Date(year, monthIndex, 0);
  const format = (date: Date) =>
    `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  return { fromDate: format(first), toDate: format(last) };
}

function shiftMonth(month: string, offset: number) {
  const [year, monthIndex] = month.split("-").map(Number);
  const next = new Date(year, monthIndex - 1 + offset, 1);
  return monthKey(next);
}

function monthLabel(month: string) {
  const [year, monthIndex] = month.split("-").map(Number);
  return new Date(year, monthIndex - 1, 1).toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
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

function expenseCategories(categories: Category[]) {
  return categories.filter((category) => category.type?.toLowerCase() === "expense");
}

export default function ReportsPage() {
  const [month, setMonth] = useState(monthKey());
  const [selectedCategoryId, setSelectedCategoryId] = useState<string | null>(
    null,
  );
  const [activeCategory, setActiveCategory] = useState<Category | null>(null);

  const { fromDate, toDate } = useMemo(() => monthRange(month), [month]);

  const analyticsQuery = useQuery({
    queryKey: ["reports-analytics", fromDate, toDate, "expense"],
    queryFn: () =>
      fetchTransactionAnalytics({ from_date: fromDate, to_date: toDate }),
  });

  const categoryTreeQuery = useQuery({
    queryKey: ["category-tree"],
    queryFn: fetchCategoryTree,
  });

  const categorySpendingQuery = useQuery({
    queryKey: ["category-spending", fromDate, toDate, "expense"],
    queryFn: () =>
      fetchCategorySpending({ from_date: fromDate, to_date: toDate }),
  });

  const budgetSummaryQuery = useQuery({
    queryKey: ["budget-summary", month],
    queryFn: () => fetchBudgetSummary(month),
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
  });

  const analytics = analyticsQuery.data as TransactionAnalytics | undefined;
  const budgetSummary = budgetSummaryQuery.data as any;
  const categories = expenseCategories(categoryTreeQuery.data ?? []);
  const categorySpending = categorySpendingQuery.data ?? [];

  const directAmountByCategory = useMemo(
    () =>
      new Map(
        categorySpending
          .filter((row) => row.id)
          .map((row) => [row.id as string, Number(row.amount)]),
      ),
    [categorySpending],
  );

  const categoryTotal = useMemo(() => {
    const totals = new Map<string, number>();
    const visit = (category: Category): number => {
      const own = directAmountByCategory.get(category.id) ?? 0;
      const childTotal =
        category.children?.reduce((sum, child) => sum + visit(child), 0) ?? 0;
      const total = own + childTotal;
      totals.set(category.id, total);
      return total;
    };
    categories.forEach(visit);
    return totals;
  }, [categories, directAmountByCategory]);

  const selectedPath = useMemo(
    () =>
      selectedCategoryId
        ? (findCategoryPath(categories, selectedCategoryId) ?? [])
        : [],
    [categories, selectedCategoryId],
  );

  const selectedCategory = selectedPath[selectedPath.length - 1] ?? null;
  const currentLevel = selectedCategory?.children?.length
    ? expenseCategories(selectedCategory.children)
    : categories;

  const slices: ExpenseSlice[] = useMemo(
    () =>
      currentLevel
        .map((category) => ({
          id: category.id,
          label: category.name,
          value: categoryTotal.get(category.id) ?? 0,
          childrenCount: expenseCategories(category.children ?? []).length,
        }))
        .filter((slice) => slice.value > 0)
        .sort((a, b) => b.value - a.value),
    [currentLevel, categoryTotal],
  );

  const totalExpense = Number(analytics?.total_expense ?? 0);
  const totalIncome = Number(analytics?.total_income ?? 0);
  const averageSpend = Number(analytics?.average_daily_spending ?? 0);
  const selectedTotal = selectedCategory
    ? categoryTotal.get(selectedCategory.id) ?? 0
    : totalExpense;
  const selectedPercent =
    totalExpense > 0 ? Math.round((selectedTotal / totalExpense) * 100) : 0;

  function resetDrilldown() {
    setSelectedCategoryId(null);
    setActiveCategory(null);
  }

  function handleMonthChange(nextMonth: string) {
    setMonth(nextMonth);
    resetDrilldown();
  }

  function handleSliceClick(id: string) {
    const path = findCategoryPath(categories, id);
    if (!path) return;
    const category = path[path.length - 1];
    if (expenseCategories(category.children ?? []).length > 0) {
      setSelectedCategoryId(id);
      setActiveCategory(null);
      return;
    }
    setActiveCategory(category);
  }

  const loading =
    analyticsQuery.isLoading ||
    categoryTreeQuery.isLoading ||
    categorySpendingQuery.isLoading;

  return (
    <div className="-mt-4 space-y-4 pb-8 md:mt-0 md:space-y-5">
      <section className="sticky top-14 z-20 -mx-4 border-y border-line bg-surface/95 px-4 py-3 backdrop-blur md:top-0 md:mx-0 md:rounded-md md:border">
        <div className="flex items-center gap-2">
          <button
            type="button"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-line bg-white text-muted"
            onClick={() => handleMonthChange(shiftMonth(month, -1))}
            title="Previous month"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <button
            type="button"
            className="flex h-10 min-w-0 flex-1 items-center justify-center gap-2 rounded-md border border-line bg-white px-3 text-sm font-semibold text-ink"
            onClick={() => handleMonthChange(monthKey())}
            title="Go to current month"
          >
            <CalendarDays className="h-4 w-4 shrink-0 text-brand-700" />
            <span className="truncate">{monthLabel(month)}</span>
          </button>
          <button
            type="button"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-line bg-white text-muted"
            onClick={() => handleMonthChange(shiftMonth(month, 1))}
            title="Next month"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>
      </section>

      <section className="rounded-md border border-line bg-white p-4 shadow-sm">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase text-brand-700">
              Expense report
            </p>
            <h1 className="mt-1 text-xl font-semibold text-ink">
              {selectedCategory?.name ?? "All parent categories"}
            </h1>
            <p className="mt-1 text-sm text-muted">
              {selectedCategory
                ? `${selectedPercent}% of ${monthLabel(month)} spending`
                : "Parent categories first. Tap one to see subcategories."}
            </p>
          </div>
          {selectedCategory ? (
            <button
              type="button"
              onClick={() => setSelectedCategoryId(null)}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-line bg-surface text-muted"
              title="Back to parent categories"
            >
              <ArrowLeft className="h-4 w-4" />
            </button>
          ) : (
            <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-rose-50 text-rose-600">
              <ArrowDownRight className="h-4 w-4" />
            </span>
          )}
        </div>

        <div className="mt-4 grid grid-cols-3 gap-2">
          <ReportMetric label="Spent" value={totalExpense} loading={loading} />
          <ReportMetric label="Income" value={totalIncome} loading={loading} />
          <ReportMetric label="Avg/day" value={averageSpend} loading={loading} />
        </div>
      </section>

      <ExpenseHierarchyChart
        data={slices}
        selectedId={selectedCategoryId ?? activeCategory?.id}
        title={selectedCategory ? `${selectedCategory.name} subcategories` : "Parent categories"}
        total={selectedCategory ? selectedTotal : totalExpense}
        subtitle={
          selectedCategory
            ? "Tap a subcategory to view transactions."
            : "Tap a parent category to drill down."
        }
        onSliceClick={handleSliceClick}
      />

      {selectedPath.length > 0 ? (
        <section className="rounded-md border border-line bg-white p-3 shadow-sm">
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={resetDrilldown}
              className="rounded-full bg-surface px-3 py-1.5 text-xs font-semibold text-muted"
            >
              All expenses
            </button>
            {selectedPath.map((category) => (
              <button
                key={category.id}
                type="button"
                onClick={() => {
                  setSelectedCategoryId(category.id);
                  setActiveCategory(null);
                }}
                className={cn(
                  "rounded-full px-3 py-1.5 text-xs font-semibold",
                  category.id === selectedCategoryId
                    ? "bg-brand-600 text-white"
                    : "bg-surface text-muted",
                )}
              >
                {category.name}
              </button>
            ))}
          </div>
        </section>
      ) : null}

      <section className="rounded-md border border-line bg-white p-4 shadow-sm">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-sm font-semibold text-ink">Budget vs expense</p>
            <p className="mt-1 text-xs text-muted">
              {monthLabel(month)} plan compared with posted expenses.
            </p>
          </div>
          <span
            className={cn(
              "rounded-full px-3 py-1 text-xs font-semibold",
              Number(budgetSummary?.actual_balance ?? 0) < 0
                ? "bg-rose-50 text-rose-600"
                : "bg-emerald-50 text-emerald-700",
            )}
          >
            Balance {formatCurrency(Number(budgetSummary?.actual_balance ?? 0))}
          </span>
        </div>

        <div className="mt-4 grid grid-cols-3 gap-2">
          <ReportMetric
            label="Total budget"
            value={Number(budgetSummary?.total_budget ?? 0)}
            loading={budgetSummaryQuery.isLoading}
          />
          <ReportMetric
            label="Spent"
            value={Number(budgetSummary?.total_spent ?? 0)}
            loading={budgetSummaryQuery.isLoading}
          />
          <ReportMetric
            label="Planned left"
            value={Number(budgetSummary?.planned_balance ?? 0)}
            loading={budgetSummaryQuery.isLoading}
          />
        </div>

        <div className="mt-4 space-y-2">
          {(budgetSummary?.categories ?? []).length ? (
            budgetSummary.categories.map((item: any) => {
              const budget = Number(item.budget ?? 0);
              const spent = Number(item.spent ?? 0);
              const used = budget > 0 ? Math.min((spent / budget) * 100, 100) : 0;
              const over = spent > budget;
              return (
                <div key={item.category_id} className="rounded-md bg-surface p-3">
                  <div className="flex items-center justify-between gap-3">
                    <span className="min-w-0 truncate text-sm font-semibold text-ink">
                      {item.category_name}
                    </span>
                    <span className={cn("shrink-0 text-sm font-semibold", over ? "text-rose-600" : "text-ink")}>
                      {formatCurrency(spent)} / {formatCurrency(budget)}
                    </span>
                  </div>
                  <div className="mt-2 h-2 rounded-full bg-white">
                    <div
                      className={cn("h-2 rounded-full", over ? "bg-rose-500" : "bg-emerald-600")}
                      style={{ width: `${used}%` }}
                    />
                  </div>
                  <p className={cn("mt-1 text-xs", over ? "text-rose-600" : "text-muted")}>
                    Remaining {formatCurrency(budget - spent)}
                  </p>
                </div>
              );
            })
          ) : (
            <p className="rounded-md border border-dashed border-line p-4 text-sm text-muted">
              No budget plan found for this month.
            </p>
          )}
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

function ReportMetric({
  label,
  value,
  loading,
}: {
  label: string;
  value: number;
  loading: boolean;
}) {
  return (
    <div className="min-w-0 rounded-md bg-surface p-2.5">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className="mt-1 truncate text-sm font-semibold text-ink">
        {loading ? "--" : formatCurrency(value)}
      </p>
    </div>
  );
}
