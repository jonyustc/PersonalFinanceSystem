"use client";

import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Save,
  Wallet,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { Button } from "@/components/ui/button";
import { cn, formatCurrency } from "@/lib/utils";
import {
  deleteBudget,
  fetchBudgets,
  fetchBudgetSummary,
  fetchCategories,
  fetchMonthlyIncome,
  saveMonthlyIncome,
  upsertBudget,
} from "@/services/finance-service";
import type { Category } from "@/types/api";

function monthKey(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
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

function normalizeIncome(res: any) {
  return {
    amount: Number(res?.amount ?? 0),
    opening_balance: Number(res?.opening_balance ?? 0),
  };
}

function isExpenseParent(category: Category) {
  return category.type?.toLowerCase() === "expense" && !category.parent_id;
}

export default function BudgetsPage() {
  const [month, setMonth] = useState(monthKey());
  const [income, setIncome] = useState(0);
  const [openingBalance, setOpeningBalance] = useState(0);
  const [budgets, setBudgets] = useState<any[]>([]);
  const [summary, setSummary] = useState<any>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [draft, setDraft] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    load();
  }, [month]);

  async function load() {
    try {
      setLoading(true);
      const [budgetData, summaryData, categoryData, incomeData] =
        await Promise.all([
          fetchBudgets(month),
          fetchBudgetSummary(month),
          fetchCategories(),
          fetchMonthlyIncome(month),
        ]);

      const safeBudgets = Array.isArray(budgetData) ? budgetData : [];
      const monthlyIncome = normalizeIncome(incomeData);
      const map: Record<string, number> = {};
      safeBudgets.forEach((item: any) => {
        map[String(item.category_id)] = Number(item.amount);
      });

      setBudgets(safeBudgets);
      setSummary(summaryData);
      setCategories(Array.isArray(categoryData) ? categoryData : []);
      setIncome(monthlyIncome.amount);
      setOpeningBalance(monthlyIncome.opening_balance);
      setDraft(map);
    } catch (err) {
      console.error("Failed to load budget data", err);
      alert("Failed to load budget data");
    } finally {
      setLoading(false);
    }
  }

  const expenseParents = useMemo(
    () => categories.filter(isExpenseParent),
    [categories],
  );

  const summaryByCategory = useMemo(
    () =>
      new Map<string, any>(
        (summary?.categories ?? []).map((item: any) => [
          String(item.category_id),
          item,
        ]),
      ),
    [summary],
  );

  const totalBudget = useMemo(
    () =>
      expenseParents.reduce(
        (sum, category) => sum + Number(draft[category.id] ?? 0),
        0,
      ),
    [draft, expenseParents],
  );
  const totalBalance = income + openingBalance;
  const plannedBalance = totalBalance - totalBudget;
  const totalSpent = Number(summary?.total_spent ?? 0);
  const actualBalance = totalBalance - totalSpent;

  async function saveAll() {
    try {
      setSaving(true);
      await saveMonthlyIncome({
        month,
        amount: Number(income),
        opening_balance: Number(openingBalance),
      });

      for (const category of expenseParents) {
        const amount = Number(draft[category.id] ?? 0);
        const existing = budgets.find(
          (budget) => String(budget.category_id) === String(category.id),
        );

        if (amount > 0) {
          await upsertBudget({ category_id: category.id, amount, month });
        } else if (existing) {
          await deleteBudget(existing.id);
        }
      }

      await load();
      window.dispatchEvent(new Event("finance:data-mutated"));
    } catch (err) {
      console.error("Save failed", err);
      alert("Save failed");
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 5 }).map((_, index) => (
          <div key={index} className="h-24 animate-pulse rounded-md bg-card" />
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-3 pb-24 md:space-y-5">
      <section className="-mx-3 border-b border-line bg-card px-3 py-3 shadow-sm sm:-mx-4 sm:px-4 md:mx-0 md:rounded-md md:border md:px-4">
        <div className="flex items-center gap-2">
          <button
            type="button"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-line bg-card text-muted"
            onClick={() => setMonth(shiftMonth(month, -1))}
            title="Previous month"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <button
            type="button"
            className="flex h-10 min-w-0 flex-1 items-center justify-center gap-2 rounded-md border border-line bg-card px-3 text-sm font-semibold text-ink"
            onClick={() => setMonth(monthKey())}
            title="Go to current month"
          >
            <CalendarDays className="h-4 w-4 shrink-0 text-brand-700" />
            <span className="truncate">{monthLabel(month)}</span>
          </button>
          <button
            type="button"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-line bg-card text-muted"
            onClick={() => setMonth(shiftMonth(month, 1))}
            title="Next month"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>
      </section>

      <section className="rounded-md border border-line bg-card p-4 shadow-sm">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase text-brand-700">
              Monthly budget plan
            </p>
            <h1 className="mt-1 text-xl font-semibold text-ink">
              Budget {monthLabel(month)}
            </h1>
            <p className="mt-1 text-sm text-muted">
              Plan category cost, then compare with real expense in reports.
            </p>
          </div>
          <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-income-soft text-income">
            <Wallet className="h-4 w-4" />
          </span>
        </div>

        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <MoneyInput
            label="Total income"
            value={income}
            onChange={setIncome}
          />
          <MoneyInput
            label="Last month balance"
            value={openingBalance}
            onChange={setOpeningBalance}
          />
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <PlanMetric label="Total balance" value={totalBalance} />
          <PlanMetric label="Total cost" value={totalBudget} />
          <PlanMetric
            label="Plan balance"
            value={plannedBalance}
            warn={plannedBalance < 0}
          />
          <PlanMetric
            label="Actual balance"
            value={actualBalance}
            warn={actualBalance < 0}
          />
        </div>
      </section>

      <section className="space-y-3">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-base font-semibold text-ink">Category budgets</h2>
          <span className="text-sm text-muted">
            {expenseParents.length} categories
          </span>
        </div>

        {expenseParents.length === 0 ? (
          <div className="rounded-md border border-dashed border-line bg-card p-6 text-center text-sm text-muted">
            Add parent expense categories like Needs, Want, Loan, Investment.
          </div>
        ) : (
          <div className="space-y-3">
            {expenseParents.map((category) => {
              const planned = Number(draft[category.id] ?? 0);
              const item = summaryByCategory.get(String(category.id));
              const spent = Number(item?.spent ?? 0);
              const used = planned > 0 ? Math.min((spent / planned) * 100, 999) : 0;
              const over = planned > 0 && spent > planned;

              return (
                <article
                  key={category.id}
                  className={cn(
                    "rounded-md border bg-card p-4 shadow-sm",
                    over ? "border-expense/30" : "border-line",
                  )}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <h3 className="truncate font-semibold text-ink">
                        {category.name}
                      </h3>
                      <p className="mt-1 text-xs text-muted">
                        Spent {formatCurrency(spent)} of {formatCurrency(planned)}
                      </p>
                    </div>
                    <input
                      type="number"
                      min={0}
                      inputMode="decimal"
                      value={draft[category.id] ?? ""}
                      onChange={(event) =>
                        setDraft((current) => ({
                          ...current,
                          [category.id]: Number(event.target.value || 0),
                        }))
                      }
                      className="h-10 w-32 rounded-md border border-line bg-surface px-3 text-right text-sm font-semibold outline-none focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
                    />
                  </div>
                  <div className="mt-3 h-2 rounded-full bg-surface">
                    <div
                      className={cn(
                        "h-2 rounded-full",
                        over ? "bg-expense" : "bg-income",
                      )}
                      style={{ width: `${Math.min(used, 100)}%` }}
                    />
                  </div>
                  <div className="mt-2 flex items-center justify-between text-xs">
                    <span className={over ? "text-expense" : "text-muted"}>
                      {used.toFixed(0)}% used
                    </span>
                    <span className={over ? "font-semibold text-expense" : "text-muted"}>
                      Remaining {formatCurrency(planned - spent)}
                    </span>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      <div className="sticky bottom-0 z-20 -mx-3 border-t border-line bg-card/95 px-3 py-2.5 backdrop-blur md:mx-0 md:rounded-md md:border md:px-4 md:py-3">
        <Button className="w-full" disabled={saving} onClick={saveAll}>
          <Save className="h-4 w-4" />
          {saving ? "Saving..." : "Save monthly budget"}
        </Button>
      </div>
    </div>
  );
}

function MoneyInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-xs font-semibold text-muted">
        {label}
      </span>
      <input
        type="number"
        min={0}
        inputMode="decimal"
        value={value || ""}
        onChange={(event) => onChange(Number(event.target.value || 0))}
        className="h-11 w-full rounded-md border border-line bg-surface px-3 text-sm font-semibold text-ink outline-none focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
      />
    </label>
  );
}

function PlanMetric({
  label,
  value,
  warn = false,
}: {
  label: string;
  value: number;
  warn?: boolean;
}) {
  return (
    <div className={cn("min-w-0 rounded-md bg-surface p-3", warn && "bg-expense-soft")}>
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className={cn("mt-1 truncate text-sm font-semibold", warn ? "text-expense" : "text-ink")}>
        {formatCurrency(value)}
      </p>
    </div>
  );
}
