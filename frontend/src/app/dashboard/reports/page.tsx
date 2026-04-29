"use client";

import {
  CalendarDays,
  ChartBar,
  TrendingDown,
  TrendingUp,
  Wallet,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { formatCurrency } from "@/lib/utils";
import {
  fetchCategorySpending,
  fetchIncomeReport,
  fetchMonthlyExpenses,
  fetchNetWorthTrend,
} from "@/services/finance-service";
import type { MonthlyExpenseReport, ReportRow, TrendPoint } from "@/types/api";

const periods = Array.from({ length: 12 }, (_, index) => index + 1);

function ReportBarChart({ data }: { data: ReportRow[] }) {
  const maxAmount = useMemo(
    () => Math.max(1, ...data.map((item) => Number(item.amount))),
    [data],
  );

  return (
    <div className="space-y-3">
      {data.map((item) => (
        <div key={item.label} className="space-y-1">
          <div className="flex items-center justify-between text-sm text-muted">
            <span>{item.label}</span>
            <span className="font-semibold text-ink">
              {formatCurrency(item.amount)}
            </span>
          </div>
          <div className="h-2 rounded-full bg-slate-100">
            <div
              className="h-2 rounded-full bg-brand-600"
              style={{ width: `${(Number(item.amount) / maxAmount) * 100}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}

function TrendTable({ data }: { data: TrendPoint[] }) {
  return (
    <div className="space-y-3">
      {data.length ? (
        data.map((point) => (
          <div
            key={point.period}
            className="flex items-center justify-between rounded-lg border border-line bg-slate-50 p-3"
          >
            <span className="text-sm text-muted">{point.period}</span>
            <span className="text-sm font-semibold text-ink">
              {formatCurrency(point.amount)}
            </span>
          </div>
        ))
      ) : (
        <p className="text-sm text-muted">No trend data available.</p>
      )}
    </div>
  );
}

export default function ReportsPage() {
  const now = new Date();
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [year, setYear] = useState(now.getFullYear());
  const [expenseReport, setExpenseReport] =
    useState<MonthlyExpenseReport | null>(null);
  const [categoryReport, setCategoryReport] = useState<ReportRow[]>([]);
  const [incomeReport, setIncomeReport] = useState<ReportRow[]>([]);
  const [netWorthTrend, setNetWorthTrend] = useState<TrendPoint[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setError(null);
    Promise.all([
      fetchMonthlyExpenses(month, year),
      fetchCategorySpending(),
      fetchIncomeReport(year),
      fetchNetWorthTrend(),
    ])
      .then(([monthly, categories, income, trend]) => {
        setExpenseReport(monthly);
        setCategoryReport(categories);
        setIncomeReport(income);
        setNetWorthTrend(trend);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : "Unable to load reports"),
      );
  }, [month, year]);

  const years = useMemo(() => [year - 1, year, year + 1], [year]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Reports</h1>
          <p className="mt-1 text-sm text-muted">
            Monthly expense, category spending, income summary, and net worth
            trend.
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <label className="inline-flex items-center gap-2 text-sm text-muted">
            <CalendarDays className="h-4 w-4" />
            <select
              value={month}
              onChange={(event) => setMonth(Number(event.target.value))}
              className="rounded-md border border-line bg-white px-3 py-2 text-sm text-ink"
            >
              {periods.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </label>
          <label className="inline-flex items-center gap-2 text-sm text-muted">
            <CalendarDays className="h-4 w-4" />
            <select
              value={year}
              onChange={(event) => setYear(Number(event.target.value))}
              className="rounded-md border border-line bg-white px-3 py-2 text-sm text-ink"
            >
              {years.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </label>
        </div>
      </div>

      {error ? (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <section className="grid gap-4 xl:grid-cols-[1.2fr_0.8fr]">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm text-muted">Monthly expense report</p>
              <h2 className="text-lg font-semibold text-ink">
                {expenseReport
                  ? `${expenseReport.month}/${expenseReport.year}`
                  : "Loading..."}
              </h2>
            </div>
            <div className="inline-flex items-center gap-2 rounded-full border border-line px-3 py-1 text-sm text-muted">
              <TrendingDown className="h-4 w-4" />
              Expense
            </div>
          </div>
          <div className="mt-6 space-y-4">
            <div className="rounded-lg border border-line bg-slate-50 p-4">
              <p className="text-xs uppercase tracking-wide text-muted">
                Total expenses
              </p>
              <p className="mt-2 text-2xl font-semibold text-ink">
                {expenseReport ? formatCurrency(expenseReport.total) : "--"}
              </p>
            </div>
            {expenseReport ? (
              <ReportBarChart data={expenseReport.categories} />
            ) : (
              <p className="text-sm text-muted">
                Loading monthly expense details...
              </p>
            )}
          </div>
        </div>

        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm text-muted">Category spending</p>
              <h2 className="text-lg font-semibold text-ink">All time</h2>
            </div>
            <ChartBar className="h-5 w-5 text-brand-600" />
          </div>
          <div className="mt-6">
            {categoryReport.length ? (
              <ReportBarChart data={categoryReport} />
            ) : (
              <p className="text-sm text-muted">
                Category spending will appear here.
              </p>
            )}
          </div>
        </div>
      </section>

      <section className="grid gap-4 xl:grid-cols-2">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm text-muted">Income report</p>
              <h2 className="text-lg font-semibold text-ink">{year}</h2>
            </div>
            <TrendingUp className="h-5 w-5 text-sky-600" />
          </div>
          <div className="mt-6">
            {incomeReport.length ? (
              <ReportBarChart data={incomeReport} />
            ) : (
              <p className="text-sm text-muted">
                No income history for the selected year.
              </p>
            )}
          </div>
        </div>

        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm text-muted">Net worth trend</p>
              <h2 className="text-lg font-semibold text-ink">
                Recent balances
              </h2>
            </div>
            <Wallet className="h-5 w-5 text-green-600" />
          </div>
          <div className="mt-6">
            <TrendTable data={netWorthTrend} />
          </div>
        </div>
      </section>
    </div>
  );
}
