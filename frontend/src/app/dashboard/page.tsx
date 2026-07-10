"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowUpDown, CreditCard, TrendingDown, Wallet } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

import { AccountsStrip } from "@/components/dashboard/accounts-strip";
import { BudgetProgressCard } from "@/components/dashboard/budget-progress-card";
import { CreditCardTile } from "@/components/dashboard/credit-card-tile";
import { MonthStepper } from "@/components/dashboard/month-stepper";
import { NetWorthHero } from "@/components/dashboard/net-worth-hero";
import { TodayActivityList } from "@/components/dashboard/today-activity-list";
import { MetricCard } from "@/components/ui/metric-card";
import { SectionHeader } from "@/components/ui/section-header";
import { formatMoney, signedMoney } from "@/lib/money";
import {
  fetchAccounts,
  fetchAccountSummary,
  fetchBudgetSummary,
  fetchCategories,
  fetchSimpleDashboard,
  fetchTransactionAnalytics,
  fetchTransactions,
} from "@/services/finance-service";

/* ========================= helpers ========================= */

function isoDate(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
    date.getDate(),
  ).padStart(2, "0")}`;
}

function getCurrentMonth() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function monthRange(month: string) {
  const [year, monthNumber] = month.split("-").map(Number);
  return {
    from: isoDate(new Date(year, monthNumber - 1, 1)),
    to: isoDate(new Date(year, monthNumber, 0)),
  };
}

function toNumber(value: string | number | null | undefined) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

// GET /budgets/summary — shape from backend BudgetSummaryResponse
// (fetchBudgetSummary is untyped in finance-service, so it's typed here).
type BudgetSummaryResponse = {
  month: string;
  income: number;
  opening_balance: number;
  total_balance: number;
  total_budget: number;
  total_spent: number;
  planned_balance: number;
  actual_balance: number;
  categories: {
    category_id: string;
    category_name: string;
    budget: number;
    spent: number;
    remaining: number;
    used_percentage: number;
    overspending: boolean;
  }[];
};

/* ========================= page ========================= */

export default function DashboardPage() {
  const queryClient = useQueryClient();
  const [month, setMonth] = useState(getCurrentMonth);
  const [today] = useState(() => isoDate(new Date()));
  const range = useMemo(() => monthRange(month), [month]);

  const summaryQuery = useQuery({
    queryKey: ["account-summary"],
    queryFn: fetchAccountSummary,
  });

  const simpleQuery = useQuery({
    queryKey: ["dashboard", "simple", month],
    queryFn: () => fetchSimpleDashboard(month),
  });

  const analyticsQuery = useQuery({
    queryKey: ["analytics", range.from, range.to],
    queryFn: () => fetchTransactionAnalytics({ from_date: range.from, to_date: range.to }),
  });

  const budgetQuery = useQuery({
    queryKey: ["budget-summary", month],
    queryFn: () => fetchBudgetSummary(month) as Promise<BudgetSummaryResponse>,
  });

  const accountsQuery = useQuery({
    queryKey: ["accounts"],
    queryFn: fetchAccounts,
  });

  const categoriesQuery = useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
  });

  const todayQuery = useQuery({
    queryKey: ["transactions", "today", today],
    queryFn: () => fetchTransactions({ from_date: today, to_date: today, limit: 8 }),
  });

  // The global add-transaction FAB dispatches this event after every mutation.
  useEffect(() => {
    function refresh() {
      queryClient.invalidateQueries({ queryKey: ["account-summary"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
      queryClient.invalidateQueries({ queryKey: ["analytics"] });
      queryClient.invalidateQueries({ queryKey: ["budget-summary"] });
      queryClient.invalidateQueries({ queryKey: ["accounts"] });
      queryClient.invalidateQueries({ queryKey: ["categories"] });
      queryClient.invalidateQueries({ queryKey: ["transactions"] });
    }

    window.addEventListener("finance:data-mutated", refresh);
    return () => window.removeEventListener("finance:data-mutated", refresh);
  }, [queryClient]);

  const accountMap = useMemo(
    () => new Map((accountsQuery.data ?? []).map((account) => [account.id, account])),
    [accountsQuery.data],
  );
  const categoryMap = useMemo(
    () => new Map((categoriesQuery.data ?? []).map((category) => [category.id, category])),
    [categoriesQuery.data],
  );

  const summary = summaryQuery.data;
  const simple = simpleQuery.data;
  const analytics = analyticsQuery.data;
  const budget = budgetQuery.data;
  const todayTransactions = (todayQuery.data?.items ?? []).slice(0, 8);

  const netCashflow = analytics
    ? toNumber(analytics.total_income) - toNumber(analytics.total_expense)
    : 0;
  const cardOutstanding = toNumber(simple?.card_summary.total_card_outstanding);

  const todayLabel = new Date().toLocaleDateString("en-US", {
    weekday: "long",
    month: "short",
    day: "numeric",
  });

  const initialLoading =
    (summaryQuery.isLoading || simpleQuery.isLoading || analyticsQuery.isLoading) &&
    !summary &&
    !simple;

  if (initialLoading) {
    return <DashboardSkeleton />;
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4 lg:max-w-5xl">
      {/* 1. Net worth hero */}
      {summaryQuery.isError ? (
        <ErrorCard message="Couldn't load your net worth." onRetry={() => summaryQuery.refetch()} />
      ) : summary ? (
        <NetWorthHero
          netWorth={toNumber(summary.net_worth)}
          assets={toNumber(summary.total_assets)}
          liabilities={toNumber(summary.liabilities)}
        />
      ) : null}

      {/* Month stepper */}
      <div className="flex items-center justify-between px-1">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">This month</p>
        <MonthStepper month={month} onChange={setMonth} />
      </div>

      {/* 2. Metric grid */}
      {simpleQuery.isError && analyticsQuery.isError ? (
        <ErrorCard
          message="Couldn't load this month's numbers."
          onRetry={() => {
            simpleQuery.refetch();
            analyticsQuery.refetch();
          }}
        />
      ) : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <MetricCard
            icon={ArrowUpDown}
            label="Cash flow"
            value={signedMoney(netCashflow)}
            caption="Income − expense this month"
            tone={netCashflow >= 0 ? "income" : "expense"}
          />
          <MetricCard
            icon={TrendingDown}
            label="Spent this month"
            value={formatMoney(toNumber(analytics?.total_expense))}
            caption={`${formatMoney(toNumber(analytics?.average_daily_spending))} / day avg`}
            tone="expense"
          />
          <MetricCard
            icon={Wallet}
            label="Active balance"
            value={formatMoney(toNumber(simple?.active_accounts_balance.total_balance))}
            caption="Cash · bank · mobile"
            tone="brand"
          />
          <MetricCard
            icon={CreditCard}
            label="Card outstanding"
            value={formatMoney(cardOutstanding)}
            caption={
              simple ? `Across ${simple.card_summary.cards.length} cards` : undefined
            }
            tone={cardOutstanding > 0 ? "expense" : "default"}
          />
        </div>
      )}

      {/* 3. Monthly budget progress */}
      {budget ? (
        <BudgetProgressCard totalBudget={budget.total_budget} totalSpent={budget.total_spent} />
      ) : null}

      {/* 4. Active accounts */}
      {simple && simple.active_accounts_balance.accounts.length > 0 ? (
        <section className="space-y-2">
          <SectionHeader title="Accounts" subtitle="Cash · bank · mobile" />
          <AccountsStrip accounts={simple.active_accounts_balance.accounts} />
        </section>
      ) : null}

      {/* 5. Credit cards */}
      {simple && simple.card_summary.cards.length > 0 ? (
        <section className="space-y-2">
          <SectionHeader title="Credit cards" subtitle="Utilization this cycle" />
          <div className="space-y-3">
            {simple.card_summary.cards.map((card) => (
              <CreditCardTile key={card.id} card={card} />
            ))}
          </div>
        </section>
      ) : null}

      {/* 6. Today's activity */}
      <section className="space-y-2">
        <SectionHeader
          title="Today's activity"
          subtitle={todayLabel}
          action={
            <Link
              href="/dashboard/transactions"
              className="shrink-0 text-xs font-semibold text-brand-700 hover:underline"
            >
              View all
            </Link>
          }
        />
        {todayQuery.isLoading ? (
          <div className="card h-40 animate-pulse bg-surface" />
        ) : todayQuery.isError ? (
          <ErrorCard
            message="Couldn't load today's transactions."
            onRetry={() => todayQuery.refetch()}
          />
        ) : (
          <TodayActivityList
            transactions={todayTransactions}
            accounts={accountMap}
            categories={categoryMap}
          />
        )}
      </section>
    </div>
  );
}

/* ========================= states ========================= */

function ErrorCard({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="card flex items-center justify-between gap-3 p-4">
      <p className="min-w-0 text-sm text-muted">{message}</p>
      <button
        type="button"
        onClick={onRetry}
        className="shrink-0 rounded-full border border-line px-3 py-1.5 text-xs font-semibold text-brand-700 transition hover:border-brand-600/40"
      >
        Retry
      </button>
    </div>
  );
}

function DashboardSkeleton() {
  return (
    <div className="mx-auto max-w-2xl space-y-4 lg:max-w-5xl">
      <div className="h-36 animate-pulse rounded-2xl bg-line/70" />
      <div className="flex justify-end">
        <div className="h-9 w-44 animate-pulse rounded-full bg-line/70" />
      </div>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="h-32 animate-pulse rounded-2xl bg-line/70" />
        ))}
      </div>
      <div className="h-24 animate-pulse rounded-2xl bg-line/70" />
      <div className="-mx-3 flex gap-3 overflow-hidden px-3">
        {Array.from({ length: 3 }).map((_, index) => (
          <div key={index} className="h-24 min-w-[160px] animate-pulse rounded-2xl bg-line/70" />
        ))}
      </div>
      <div className="h-64 animate-pulse rounded-2xl bg-line/70" />
    </div>
  );
}
