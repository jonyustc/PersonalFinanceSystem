"use client";

import {
  AlertTriangle,
  CalendarDays,
  Edit3,
  Plus,
  RefreshCw,
  Trash2,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { BudgetForm } from "@/components/budgets/budget-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
import {
  createBudget,
  deleteBudget,
  fetchBudgets,
  fetchCategories,
  updateBudget,
} from "@/services/finance-service";
import type {
  Budget,
  BudgetCreatePayload,
  BudgetUpdatePayload,
  Category,
} from "@/types/api";

const monthNames = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const currentDate = new Date();

export default function BudgetsPage() {
  const [budgets, setBudgets] = useState<Budget[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedMonth, setSelectedMonth] = useState(
    currentDate.getMonth() + 1,
  );
  const [selectedYear, setSelectedYear] = useState(currentDate.getFullYear());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingBudget, setEditingBudget] = useState<Budget | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const categoryById = useMemo(
    () => new Map(categories.map((category) => [category.id, category])),
    [categories],
  );

  const totals = useMemo(
    () =>
      budgets.reduce(
        (acc, budget) => {
          acc.budgeted += Number(budget.amount);
          acc.spent += Number(budget.spent);
          acc.remaining += Number(budget.remaining);
          return acc;
        },
        { budgeted: 0, spent: 0, remaining: 0 },
      ),
    [budgets],
  );

  const yearOptions = useMemo(
    () => [selectedYear - 1, selectedYear, selectedYear + 1],
    [selectedYear],
  );

  const loadCategories = useCallback(async () => {
    try {
      setCategories(await fetchCategories());
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Unable to load categories",
      );
    }
  }, []);

  const loadBudgets = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setBudgets(await fetchBudgets(selectedMonth, selectedYear));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to load budgets");
    } finally {
      setLoading(false);
    }
  }, [selectedMonth, selectedYear]);

  useEffect(() => {
    loadCategories();
  }, [loadCategories]);

  useEffect(() => {
    loadBudgets();
  }, [loadBudgets]);

  function openCreateModal() {
    setEditingBudget(null);
    setModalOpen(true);
  }

  function openEditModal(budget: Budget) {
    setEditingBudget(budget);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingBudget(null);
  }

  async function handleSave(
    payload: BudgetCreatePayload | BudgetUpdatePayload,
  ) {
    setSubmitting(true);
    setError(null);
    try {
      if (editingBudget) {
        await updateBudget(editingBudget.id, payload as BudgetUpdatePayload);
      } else {
        await createBudget(payload as BudgetCreatePayload);
      }
      closeModal();
      await loadBudgets();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to save budget");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDelete(budget: Budget) {
    const confirmed = window.confirm(
      `Delete budget for ${categoryById.get(budget.category_id)?.name ?? "this category"} (${monthNames[budget.month - 1]} ${budget.year})?`,
    );
    if (!confirmed) return;

    setDeletingId(budget.id);
    setError(null);
    try {
      await deleteBudget(budget.id);
      await loadBudgets();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to delete budget");
    } finally {
      setDeletingId(null);
    }
  }

  function progressClass(overspending: boolean, percent: number) {
    if (overspending) return "bg-red-600";
    if (percent >= 0.75) return "bg-amber-500";
    return "bg-brand-600";
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Budgets</h1>
          <p className="mt-1 text-sm text-muted">
            Create monthly budgets, compare spending, and spot overspending
            before it becomes a problem.
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button variant="secondary" onClick={loadBudgets} disabled={loading}>
            <RefreshCw className="h-4 w-4" aria-hidden />
            Refresh
          </Button>
          <Button onClick={openCreateModal} disabled={!categories.length}>
            <Plus className="h-4 w-4" aria-hidden />
            Add budget
          </Button>
        </div>
      </div>

      <section className="grid gap-4 md:grid-cols-4">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Budgets</p>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {budgets.length}
          </p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Total budgeted</p>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {formatCurrency(totals.budgeted)}
          </p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Spent against budgets</p>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {formatCurrency(totals.spent)}
          </p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Remaining</p>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {formatCurrency(totals.remaining)}
          </p>
        </div>
      </section>

      <section className="rounded-lg border border-line bg-white p-4 shadow-soft">
        <div className="grid gap-4 md:grid-cols-3 xl:grid-cols-4">
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">
              Month
            </span>
            <select
              className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              value={selectedMonth}
              onChange={(event) => setSelectedMonth(Number(event.target.value))}
            >
              {monthNames.map((name, index) => (
                <option key={name} value={index + 1}>
                  {name}
                </option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">
              Year
            </span>
            <select
              className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              value={selectedYear}
              onChange={(event) => setSelectedYear(Number(event.target.value))}
            >
              {yearOptions.map((year) => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </label>
          <div className="flex items-end">
            <Button
              className="w-full"
              variant="secondary"
              onClick={() => loadBudgets()}
            >
              <CalendarDays className="h-4 w-4" aria-hidden />
              Apply
            </Button>
          </div>
        </div>
      </section>

      {error ? (
        <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </p>
      ) : null}

      <section className="hidden overflow-hidden rounded-lg border border-line bg-white shadow-soft lg:block">
        <div className="grid grid-cols-[1fr_130px_130px_130px_240px_120px] gap-4 border-b border-line px-5 py-3 text-xs font-semibold uppercase text-muted">
          <span>Category</span>
          <span>Budget</span>
          <span>Spent</span>
          <span>Remaining</span>
          <span>Status</span>
          <span className="text-right">Actions</span>
        </div>
        {loading ? (
          <p className="px-5 py-6 text-sm text-muted">Loading budgets...</p>
        ) : null}
        {!loading && !budgets.length ? (
          <p className="px-5 py-6 text-sm text-muted">
            No budgets for this period.
          </p>
        ) : null}
        {budgets.map((budget) => {
          const category = categoryById.get(budget.category_id);
          const percent = budget.amount
            ? Math.min(
                Math.max(Number(budget.spent) / Number(budget.amount), 0),
                1,
              )
            : 0;
          return (
            <div
              key={budget.id}
              className="grid grid-cols-[1fr_130px_130px_130px_240px_120px] items-center gap-4 border-b border-line px-5 py-4 text-sm last:border-0"
            >
              <div>
                <p className="font-semibold text-ink">
                  {category?.name ?? "Unknown category"}
                </p>
                <p className="text-xs text-muted">
                  {monthNames[budget.month - 1]} {budget.year}
                </p>
              </div>
              <span>{formatCurrency(budget.amount)}</span>
              <span>{formatCurrency(budget.spent)}</span>
              <span>{formatCurrency(budget.remaining)}</span>
              <div className="space-y-2">
                <div className="h-2 overflow-hidden rounded-full bg-slate-100">
                  <div
                    className={`h-full ${progressClass(budget.overspending, percent)}`}
                    style={{ width: `${Math.max(percent * 100, 5)}%` }}
                  />
                </div>
                <p
                  className={`text-sm font-medium ${budget.overspending ? "text-red-700" : "text-slate-600"}`}
                >
                  {budget.overspending ? "Overspending" : "On track"}
                </p>
              </div>
              <div className="flex justify-end gap-2">
                <button
                  className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink"
                  onClick={() => openEditModal(budget)}
                  type="button"
                >
                  <Edit3 className="h-4 w-4" aria-hidden />
                </button>
                <button
                  className="rounded-md p-2 text-muted hover:bg-red-50 hover:text-red-700 disabled:opacity-50"
                  disabled={deletingId === budget.id}
                  onClick={() => handleDelete(budget)}
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
        {loading ? (
          <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">
            Loading budgets...
          </p>
        ) : null}
        {!loading && !budgets.length ? (
          <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">
            No budgets for this period.
          </p>
        ) : null}
        {budgets.map((budget) => {
          const category = categoryById.get(budget.category_id);
          const percent = budget.amount
            ? Math.min(
                Math.max(Number(budget.spent) / Number(budget.amount), 0),
                1,
              )
            : 0;
          return (
            <article
              key={budget.id}
              className="rounded-lg border border-line bg-white p-5 shadow-soft"
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h2 className="font-semibold text-ink">
                    {category?.name ?? "Unknown category"}
                  </h2>
                  <p className="text-sm text-muted">
                    {monthNames[budget.month - 1]} {budget.year}
                  </p>
                </div>
                <span
                  className={`rounded-full px-2 py-1 text-xs font-semibold ${budget.overspending ? "bg-red-50 text-red-700" : "bg-slate-100 text-slate-700"}`}
                >
                  {budget.overspending ? "Overspending" : "On track"}
                </span>
              </div>
              <div className="mt-4 space-y-3">
                <div className="grid grid-cols-2 gap-4 text-sm text-slate-600">
                  <div>
                    <p className="text-xs uppercase text-muted">Budget</p>
                    <p className="font-semibold text-ink">
                      {formatCurrency(budget.amount)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs uppercase text-muted">Spent</p>
                    <p className="font-semibold text-ink">
                      {formatCurrency(budget.spent)}
                    </p>
                  </div>
                  <div className="col-span-2">
                    <p className="text-xs uppercase text-muted">Remaining</p>
                    <p className="font-semibold text-ink">
                      {formatCurrency(budget.remaining)}
                    </p>
                  </div>
                </div>
                <div>
                  <div className="h-2 overflow-hidden rounded-full bg-slate-100">
                    <div
                      className={`h-full ${progressClass(budget.overspending, percent)}`}
                      style={{ width: `${Math.max(percent * 100, 5)}%` }}
                    />
                  </div>
                </div>
                {budget.overspending ? (
                  <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                    <AlertTriangle
                      className="inline h-4 w-4 align-text-bottom"
                      aria-hidden
                    />
                    <span className="ml-2">
                      You are overspending this budget.
                    </span>
                  </div>
                ) : null}
                <div className="flex gap-2">
                  <Button
                    variant="secondary"
                    className="flex-1"
                    onClick={() => openEditModal(budget)}
                  >
                    Edit
                  </Button>
                  <Button
                    className="flex-1"
                    variant="secondary"
                    disabled={deletingId === budget.id}
                    onClick={() => handleDelete(budget)}
                  >
                    Delete
                  </Button>
                </div>
              </div>
            </article>
          );
        })}
      </section>

      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingBudget ? "Edit budget" : "Add budget"}
        description={
          editingBudget
            ? "Adjust the budget amount for this period."
            : "Create a monthly budget for a category."
        }
      >
        <BudgetForm
          categories={categories}
          defaultMonth={selectedMonth}
          defaultYear={selectedYear}
          budget={editingBudget}
          onCancel={closeModal}
          onSubmit={handleSave}
          submitting={submitting}
        />
      </Modal>
    </div>
  );
}
