"use client";

import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { PieChart as PieChartIcon } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import {
  BudgetSection,
  type BudgetSummary,
} from "@/components/reports/budget-section";
import {
  CategoryBreakdown,
  type CategoryRowDatum,
} from "@/components/reports/category-breakdown";
import { CategoryDonut } from "@/components/reports/category-donut";
import { ExpenseDrilldownDrawer } from "@/components/reports/expense-drilldown-drawer";
import { PeriodControls } from "@/components/reports/period-controls";
import {
  monthKeyFor,
  periodLabel,
  periodStartFor,
  previousRange,
  rangeFromStart,
  shiftPeriodStart,
  trendBuckets,
  type Granularity,
} from "@/components/reports/report-period";
import {
  SPEND_SOURCES,
  SpendingSummaryCard,
  type SpendSource,
} from "@/components/reports/spending-summary-card";
import { TrendChart } from "@/components/reports/trend-chart";
import { EmptyPanel } from "@/components/ui/empty-panel";
import { categoryVisual, CHART_COLORS } from "@/lib/category-visuals";
import {
  fetchBudgetSummary,
  fetchCategorySpending,
  fetchCategoryTree,
  fetchTransactionAnalytics,
  fetchTransactions,
} from "@/services/finance-service";
import type { Category, TransactionAnalytics } from "@/types/api";

const GRANULARITY_NOUN: Record<Granularity, string> = {
  week: "weeks",
  month: "months",
  year: "years",
};

function expenseChildren(category: Category): Category[] {
  return (category.children ?? []).filter(
    (child) => child.type?.toLowerCase() === "expense",
  );
}

function sourceAmount(
  rows: TransactionAnalytics["account_breakdown"] | undefined,
  label: SpendSource,
): number {
  const row = rows?.find(
    (item) => item.label?.toLowerCase() === label.toLowerCase(),
  );
  const amount = Number(row?.amount ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

function seriesColor(index: number, name: string): string {
  return index < CHART_COLORS.length
    ? CHART_COLORS[index]
    : categoryVisual(name).color;
}

export default function ReportsPage() {
  const queryClient = useQueryClient();

  const [granularity, setGranularity] = useState<Granularity>("month");
  const [periodStart, setPeriodStart] = useState<Date>(() =>
    periodStartFor("month", new Date()),
  );
  const [drillPath, setDrillPath] = useState<string[]>([]);
  const [drawerCategory, setDrawerCategory] = useState<{
    id: string;
    name: string;
  } | null>(null);
  const [drawerSource, setDrawerSource] = useState<SpendSource | null>(null);
  // Captured once per mount; only used to disable navigating into the future.
  const [now] = useState(() => Date.now());

  const range = useMemo(
    () => rangeFromStart(granularity, periodStart),
    [granularity, periodStart],
  );
  const prevRange = useMemo(
    () => previousRange(granularity, periodStart),
    [granularity, periodStart],
  );
  const buckets = useMemo(
    () => trendBuckets(granularity, periodStart),
    [granularity, periodStart],
  );
  const nextDisabled =
    shiftPeriodStart(granularity, periodStart, 1).getTime() > now;

  /* ------------------------------ queries ------------------------------ */

  const analyticsQuery = useQuery({
    queryKey: ["reports", "analytics", granularity, range.fromDate, range.toDate],
    queryFn: () =>
      fetchTransactionAnalytics({
        from_date: range.fromDate,
        to_date: range.toDate,
      }),
  });

  const prevAnalyticsQuery = useQuery({
    queryKey: [
      "reports",
      "analytics-prev",
      granularity,
      prevRange.fromDate,
      prevRange.toDate,
    ],
    queryFn: () =>
      fetchTransactionAnalytics({
        from_date: prevRange.fromDate,
        to_date: prevRange.toDate,
      }),
  });

  const categoryTreeQuery = useQuery({
    queryKey: ["reports", "category-tree"],
    queryFn: fetchCategoryTree,
  });

  const categorySpendingQuery = useQuery({
    queryKey: ["reports", "category-spending", range.fromDate, range.toDate],
    queryFn: () =>
      fetchCategorySpending({
        from_date: range.fromDate,
        to_date: range.toDate,
      }),
  });

  const monthKey = monthKeyFor(periodStart);
  const budgetQuery = useQuery({
    queryKey: ["reports", "budget", monthKey],
    enabled: granularity === "month",
    queryFn: async () => (await fetchBudgetSummary(monthKey)) as BudgetSummary,
  });

  const trendQueries = useQueries({
    queries: buckets.map((bucket) => ({
      queryKey: ["reports", "trend", granularity, bucket.fromDate],
      queryFn: () =>
        fetchTransactionAnalytics({
          from_date: bucket.fromDate,
          to_date: bucket.toDate,
        }),
    })),
  });

  const drillTransactionsQuery = useQuery({
    queryKey: [
      "reports",
      "drill-category",
      drawerCategory?.id,
      range.fromDate,
      range.toDate,
    ],
    enabled: Boolean(drawerCategory),
    queryFn: () =>
      fetchTransactions({
        category_id: drawerCategory?.id,
        from_date: range.fromDate,
        to_date: range.toDate,
        type: "expense",
        limit: 1000,
      }),
  });

  const sourceTransactionsQuery = useQuery({
    queryKey: [
      "reports",
      "drill-source",
      drawerSource,
      range.fromDate,
      range.toDate,
    ],
    enabled: Boolean(drawerSource),
    queryFn: () =>
      fetchTransactions({
        account_source: (drawerSource?.toLowerCase() ?? "cash") as
          | "cash"
          | "bank"
          | "card",
        from_date: range.fromDate,
        to_date: range.toDate,
        type: "expense",
        limit: 1000,
      }),
  });

  // Any transaction/budget mutation elsewhere in the app refreshes reports.
  useEffect(() => {
    const invalidate = () =>
      queryClient.invalidateQueries({ queryKey: ["reports"] });
    window.addEventListener("finance:data-mutated", invalidate);
    return () => window.removeEventListener("finance:data-mutated", invalidate);
  }, [queryClient]);

  /* ------------------------- category roll-up -------------------------- */

  const expenseTree = useMemo(
    () =>
      (categoryTreeQuery.data ?? []).filter(
        (category) => category.type?.toLowerCase() === "expense",
      ),
    [categoryTreeQuery.data],
  );

  const directAmountByCategory = useMemo(() => {
    const map = new Map<string, number>();
    for (const row of categorySpendingQuery.data ?? []) {
      if (!row.id) continue;
      const amount = Number(row.amount);
      if (Number.isFinite(amount)) map.set(row.id, amount);
    }
    return map;
  }, [categorySpendingQuery.data]);

  // Total per category including all descendants.
  const rolledUpTotals = useMemo(() => {
    const totals = new Map<string, number>();
    const visit = (category: Category): number => {
      const own = directAmountByCategory.get(category.id) ?? 0;
      const childTotal = expenseChildren(category).reduce(
        (sum, child) => sum + visit(child),
        0,
      );
      const total = own + childTotal;
      totals.set(category.id, total);
      return total;
    };
    expenseTree.forEach(visit);
    return totals;
  }, [expenseTree, directAmountByCategory]);

  // Category nodes along the current drill path (empty at the top level).
  const drillNodes = useMemo(() => {
    const nodes: Category[] = [];
    let level = expenseTree;
    for (const id of drillPath) {
      const node = level.find((category) => category.id === id);
      if (!node) break;
      nodes.push(node);
      level = expenseChildren(node);
    }
    return nodes;
  }, [expenseTree, drillPath]);

  const levelRows = useMemo<CategoryRowDatum[]>(() => {
    const parent = drillNodes[drillNodes.length - 1];
    const nodes = parent ? expenseChildren(parent) : expenseTree;
    const rows = nodes
      .map((category) => ({
        id: category.id,
        name: category.name,
        amount: rolledUpTotals.get(category.id) ?? 0,
        hasChildren: expenseChildren(category).length > 0,
      }))
      .filter((row) => row.amount > 0);

    // Spend recorded directly on the drilled parent (not on a subcategory).
    if (parent) {
      const direct = directAmountByCategory.get(parent.id) ?? 0;
      if (direct > 0) {
        rows.push({
          id: parent.id,
          name: `${parent.name} (direct)`,
          amount: direct,
          hasChildren: false,
        });
      }
    }

    return rows
      .sort((a, b) => b.amount - a.amount)
      .map((row, index) => ({ ...row, color: seriesColor(index, row.name) }));
  }, [drillNodes, expenseTree, rolledUpTotals, directAmountByCategory]);

  const levelTotal = useMemo(
    () => levelRows.reduce((sum, row) => sum + row.amount, 0),
    [levelRows],
  );

  /* ------------------------------ derived ------------------------------ */

  const analytics = analyticsQuery.data;
  const totalExpense = Number(analytics?.total_expense ?? 0);
  const totalIncome = Number(analytics?.total_income ?? 0);
  const previousSpent = prevAnalyticsQuery.data
    ? Number(prevAnalyticsQuery.data.total_expense ?? 0)
    : null;

  const reportedDailyAverage = Number(analytics?.average_daily_spending ?? 0);
  const dailyAverage =
    Number.isFinite(reportedDailyAverage) && reportedDailyAverage > 0
      ? reportedDailyAverage
      : range.days > 0
        ? totalExpense / range.days
        : 0;

  const sources = useMemo(() => {
    const map = {} as Record<SpendSource, number>;
    for (const source of SPEND_SOURCES) {
      map[source] = sourceAmount(analytics?.account_breakdown, source);
    }
    return map;
  }, [analytics?.account_breakdown]);

  const trendData = buckets.map((bucket, index) => ({
    key: bucket.key,
    label: bucket.label,
    amount: Number(trendQueries[index]?.data?.total_expense ?? 0),
  }));
  const trendLoading = trendQueries.some((query) => query.isLoading);

  const breadcrumb = drillNodes.map((node) => node.name);

  const initialLoading =
    analyticsQuery.isLoading ||
    categoryTreeQuery.isLoading ||
    categorySpendingQuery.isLoading;

  const hasExpenses = totalExpense > 0 || levelTotal > 0;

  /* ------------------------------ handlers ----------------------------- */

  const resetDrill = useCallback(() => {
    setDrillPath([]);
    setDrawerCategory(null);
    setDrawerSource(null);
  }, []);

  function handleGranularityChange(next: Granularity) {
    setGranularity(next);
    setPeriodStart(periodStartFor(next, new Date()));
    resetDrill();
  }

  function handleShift(offset: number) {
    setPeriodStart((start) => shiftPeriodStart(granularity, start, offset));
    resetDrill();
  }

  function handleRowClick(row: CategoryRowDatum) {
    if (row.hasChildren) {
      setDrillPath((path) => [...path, row.id]);
      return;
    }
    setDrawerCategory({ id: row.id, name: row.name });
  }

  function handleBack() {
    setDrillPath((path) => path.slice(0, -1));
  }

  /* ------------------------------- render ------------------------------ */

  return (
    <div className="mx-auto max-w-2xl space-y-3 pb-8 lg:max-w-4xl">
      <PeriodControls
        granularity={granularity}
        label={periodLabel(granularity, range)}
        nextDisabled={nextDisabled}
        onGranularityChange={handleGranularityChange}
        onPrevious={() => handleShift(-1)}
        onNext={() => handleShift(1)}
      />

      {initialLoading ? (
        <>
          <div className="card h-52 animate-pulse" />
          <div className="card h-60 animate-pulse" />
          <div className="card h-64 animate-pulse" />
          <div className="card h-48 animate-pulse" />
        </>
      ) : (
        <>
          <SpendingSummaryCard
            spent={totalExpense}
            income={totalIncome}
            previousSpent={previousSpent}
            dailyAverage={dailyAverage}
            sources={sources}
            onSourceClick={(source) => {
              setDrawerSource(source);
              setDrawerCategory(null);
            }}
          />

          {hasExpenses ? (
            <>
              <TrendChart
                data={trendData}
                loading={trendLoading}
                subtitle={`Last 6 ${GRANULARITY_NOUN[granularity]}`}
              />
              <CategoryDonut rows={levelRows} total={levelTotal} />
              <CategoryBreakdown
                rows={levelRows}
                total={levelTotal}
                breadcrumb={breadcrumb}
                onRowClick={handleRowClick}
                onBack={handleBack}
              />
            </>
          ) : (
            <EmptyPanel
              icon={PieChartIcon}
              title="No expense data"
              body="Transactions you add will show up here"
            />
          )}

          {granularity === "month" ? (
            <BudgetSection
              summary={budgetQuery.data}
              loading={budgetQuery.isLoading}
            />
          ) : null}
        </>
      )}

      <ExpenseDrilldownDrawer
        open={Boolean(drawerCategory)}
        categoryName={drawerCategory?.name ?? "Category"}
        transactions={drillTransactionsQuery.data?.items ?? []}
        loading={drillTransactionsQuery.isFetching}
        onClose={() => setDrawerCategory(null)}
      />
      <ExpenseDrilldownDrawer
        open={Boolean(drawerSource)}
        categoryName={`${drawerSource ?? "Source"} spent`}
        transactions={sourceTransactionsQuery.data?.items ?? []}
        loading={sourceTransactionsQuery.isFetching}
        onClose={() => setDrawerSource(null)}
      />
    </div>
  );
}
