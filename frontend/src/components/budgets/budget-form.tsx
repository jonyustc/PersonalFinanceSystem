"use client";

import { Button } from "@/components/ui/button";
import { useMemo, useState } from "react";

export function BudgetForm({
  categories = [],
  budget,
  onSubmit,
  onCancel,
}: any) {
  const isEdit = !!budget;

  const [category_id, setCategoryId] = useState(budget?.category_id || "");
  const [amount, setAmount] = useState(budget?.amount || 0);

  const [income, setIncome] = useState(0);

  /* ================= 50/30/20 ================= */

  const needs = useMemo(() => income * 0.5, [income]);
  const wants = useMemo(() => income * 0.3, [income]);
  const savings = useMemo(() => income * 0.2, [income]);

  /* ================= QUICK SELECT ================= */

  function applyRule(type: string) {
    if (type === "needs") setAmount(needs);
    if (type === "wants") setAmount(wants);
    if (type === "savings") setAmount(savings);
  }

  function applyPercent(p: number) {
    if (!income) return;
    setAmount((income * p) / 100);
  }

  /* ================= SUBMIT ================= */

  async function submit(e: any) {
    e.preventDefault();

    if (!amount) return;

    if (isEdit) {
      await onSubmit({ amount });
    } else {
      await onSubmit({
        category_id,
        amount,
        period: "monthly",
      });
    }
  }

  /* ================= CATEGORY GROUP ================= */

  const expenseCategories = categories.filter((c: any) => c.type === "expense");

  /* ================= UI ================= */

  return (
    <form onSubmit={submit} className="space-y-5">
      {/* INCOME INPUT */}
      {!isEdit && (
        <div className="bg-surface p-3 rounded-lg">
          <p className="text-sm text-muted mb-1">Monthly Income</p>
          <input
            type="number"
            value={income}
            onChange={(e) => setIncome(Number(e.target.value))}
            className="input"
            placeholder="Enter income"
          />
        </div>
      )}

      {/* RULE SUGGESTION */}
      {!isEdit && income > 0 && (
        <div className="grid grid-cols-3 gap-2 text-sm">
          <button
            type="button"
            onClick={() => applyRule("needs")}
            className="rounded-lg border border-line bg-brand-600/10 p-2 text-ink hover:bg-brand-600/20"
          >
            Needs (50%)
            <br />
            {needs.toFixed(0)}
          </button>

          <button
            type="button"
            onClick={() => applyRule("wants")}
            className="rounded-lg border border-line bg-warning-soft p-2 text-ink hover:bg-warning/20"
          >
            Wants (30%)
            <br />
            {wants.toFixed(0)}
          </button>

          <button
            type="button"
            onClick={() => applyRule("savings")}
            className="rounded-lg border border-line bg-income-soft p-2 text-ink hover:bg-income/20"
          >
            Savings (20%)
            <br />
            {savings.toFixed(0)}
          </button>
        </div>
      )}

      {/* CATEGORY */}
      {!isEdit && (
        <select
          value={category_id}
          onChange={(e) => setCategoryId(e.target.value)}
          className="input"
        >
          <option value="">Select category</option>

          {expenseCategories.map((c: any) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      )}

      {/* AMOUNT */}
      <div className="space-y-2">
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(Number(e.target.value))}
          className="input"
          placeholder="Budget amount"
        />

        {/* QUICK % */}
        {!isEdit && income > 0 && (
          <div className="flex gap-2 text-xs">
            {[10, 20, 30, 50].map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => applyPercent(p)}
                className="px-2 py-1 bg-surface rounded"
              >
                {p}%
              </button>
            ))}
          </div>
        )}
      </div>

      {/* ACTION */}
      <div className="flex gap-2 justify-end">
        <Button type="button" onClick={onCancel}>
          Cancel
        </Button>

        <Button type="submit">
          {isEdit ? "Update Budget" : "Create Budget"}
        </Button>
      </div>
    </form>
  );
}
