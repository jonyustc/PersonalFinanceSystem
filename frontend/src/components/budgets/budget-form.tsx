"use client";

import { Button } from "@/components/ui/button";
import type {
  Budget,
  BudgetCreatePayload,
  BudgetUpdatePayload,
  Category,
} from "@/types/api";
import { useEffect, useMemo, useState, type FormEvent } from "react";

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

type BudgetFormProps = {
  categories: Category[];
  defaultMonth: number;
  defaultYear: number;
  budget?: Budget | null;
  onCancel: () => void;
  onSubmit: (
    payload: BudgetCreatePayload | BudgetUpdatePayload,
  ) => Promise<void>;
  submitting: boolean;
};

export function BudgetForm({
  categories,
  defaultMonth,
  defaultYear,
  budget,
  onCancel,
  onSubmit,
  submitting,
}: BudgetFormProps) {
  const isEditing = Boolean(budget);
  const [categoryId, setCategoryId] = useState(
    budget?.category_id ?? categories[0]?.id ?? "",
  );
  const [month, setMonth] = useState(budget?.month ?? defaultMonth);
  const [year, setYear] = useState(budget?.year ?? defaultYear);
  const [amount, setAmount] = useState(budget ? Number(budget.amount) : 0);

  useEffect(() => {
    setCategoryId(budget?.category_id ?? categories[0]?.id ?? "");
    setMonth(budget?.month ?? defaultMonth);
    setYear(budget?.year ?? defaultYear);
    setAmount(budget ? Number(budget.amount) : 0);
  }, [budget, categories, defaultMonth, defaultYear]);

  const yearOptions = useMemo(() => [year - 1, year, year + 1], [year]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!categoryId && !isEditing) return;
    if (amount <= 0) return;

    if (isEditing) {
      await onSubmit({ amount });
    } else {
      await onSubmit({ category_id: categoryId, month, year, amount });
    }
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      {!isEditing ? (
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Category
          </span>
          <select
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={categoryId}
            onChange={(event) => setCategoryId(event.target.value)}
            required
          >
            <option value="">Select category</option>
            {categories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </label>
      ) : (
        <div className="rounded-lg border border-line bg-surface p-4 text-sm text-muted">
          Category:{" "}
          <span className="font-medium text-ink">
            {categories.find((category) => category.id === categoryId)?.name ??
              "Unknown"}
          </span>
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Month</span>
          <select
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={month}
            onChange={(event) => setMonth(Number(event.target.value))}
            disabled={isEditing}
            required
          >
            {monthNames.map((name, index) => (
              <option key={name} value={index + 1}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Year</span>
          <select
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={year}
            onChange={(event) => setYear(Number(event.target.value))}
            disabled={isEditing}
            required
          >
            {yearOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
      </div>

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">
          Budget amount
        </span>
        <input
          className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          type="number"
          value={amount}
          min={0.01}
          step={0.01}
          onChange={(event) => setAmount(Number(event.target.value))}
          required
        />
      </label>

      {isEditing ? (
        <p className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm text-slate-700">
          Category, month, and year cannot be changed after the budget is
          created.
        </p>
      ) : null}

      <div className="flex flex-wrap gap-3 pt-2">
        <Button
          type="button"
          variant="secondary"
          onClick={onCancel}
          disabled={submitting}
        >
          Cancel
        </Button>
        <Button type="submit" disabled={submitting}>
          {isEditing ? "Save budget" : "Create budget"}
        </Button>
      </div>
    </form>
  );
}
