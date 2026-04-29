"use client";

import { useEffect, useState } from "react";
import { Banknote, PiggyBank, TrendingDown, TrendingUp } from "lucide-react";

import { StatCard } from "@/components/ui/stat-card";
import { formatCurrency } from "@/lib/utils";
import { fetchDashboard } from "@/services/finance-service";
import type { DashboardResponse } from "@/types/api";

export default function DashboardPage() {
  const [data, setData] = useState<DashboardResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchDashboard().then(setData).catch((err) => setError(err instanceof Error ? err.message : "Unable to load dashboard"));
  }, []);

  if (error) {
    return <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</p>;
  }

  if (!data) {
    return <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">Loading dashboard...</p>;
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-ink">Dashboard</h1>
        <p className="mt-1 text-sm text-muted">A quick read on cash, income, spending, savings, and net worth.</p>
      </div>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Net worth" value={formatCurrency(data.net_worth)} icon={PiggyBank} />
        <StatCard label="Income this month" value={formatCurrency(data.total_income_this_month)} icon={TrendingUp} tone="blue" />
        <StatCard label="Expense this month" value={formatCurrency(data.total_expense_this_month)} icon={TrendingDown} tone="amber" />
        <StatCard label="Bank balance" value={formatCurrency(data.total_bank_balance)} icon={Banknote} />
      </section>

      <section className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <h2 className="text-base font-semibold text-ink">Recent transactions</h2>
          <div className="mt-4 divide-y divide-line">
            {data.recent_transactions.length ? (
              data.recent_transactions.map((transaction) => (
                <div className="flex items-center justify-between gap-4 py-3" key={transaction.id}>
                  <div>
                    <p className="text-sm font-medium capitalize text-ink">{transaction.txn_type}</p>
                    <p className="text-xs text-muted">{transaction.description ?? new Date(transaction.txn_date).toLocaleDateString()}</p>
                  </div>
                  <p className="text-sm font-semibold text-ink">{formatCurrency(transaction.amount)}</p>
                </div>
              ))
            ) : (
              <p className="py-6 text-sm text-muted">No transactions yet.</p>
            )}
          </div>
        </div>

        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <h2 className="text-base font-semibold text-ink">Expense by category</h2>
          <div className="mt-4 space-y-3">
            {data.expense_by_category.length ? (
              data.expense_by_category.map((item) => (
                <div className="flex items-center justify-between gap-4" key={item.label}>
                  <span className="text-sm text-muted">{item.label}</span>
                  <span className="text-sm font-semibold text-ink">{formatCurrency(item.value)}</span>
                </div>
              ))
            ) : (
              <p className="text-sm text-muted">Category spending will appear here.</p>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
