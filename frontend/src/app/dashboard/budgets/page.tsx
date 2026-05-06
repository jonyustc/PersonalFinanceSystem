"use client";

import { useEffect, useMemo, useState } from "react";

import {
  createBudget,
  fetchBudgets,
  fetchBudgetSummary, // ✅ IMPORTANT
  fetchCategories,
  fetchMonthlyIncome,
  saveMonthlyIncome,
  updateBudget,
} from "@/services/finance-service";

import { BudgetChart } from "@/components/budgets/budget-chart";

/* ================= HELPERS ================= */

function getCurrentMonth() {
  return new Date().toISOString().slice(0, 7);
}

function normalizeIncome(res: any) {
  if (!res) return 0;
  if (typeof res === "number") return res;
  if (res.amount) return Number(res.amount);
  return 0;
}

export default function BudgetsPage() {
  const [income, setIncome] = useState(0);
  const [month] = useState(getCurrentMonth());

  const [budgets, setBudgets] = useState<any[]>([]);
  const [summary, setSummary] = useState<any>(null); // ✅ NEW
  const [categories, setCategories] = useState<any[]>([]);
  const [draft, setDraft] = useState<Record<string, number>>({});

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  /* ================= LOAD ================= */

  useEffect(() => {
    load();
  }, []);

  async function load() {
    try {
      setLoading(true);

      const [b, summaryData, c, inc] = await Promise.all([
        fetchBudgets(month), // edit
        fetchBudgetSummary(month), // chart ✅
        fetchCategories(),
        fetchMonthlyIncome(month),
      ]);

      const safeBudgets = Array.isArray(b) ? b : [];

      setBudgets(safeBudgets);
      setSummary(summaryData); // ✅ IMPORTANT
      setCategories(Array.isArray(c) ? c : []);
      setIncome(normalizeIncome(inc));

      const map: Record<string, number> = {};
      safeBudgets.forEach((item: any) => {
        map[String(item.category_id)] = Number(item.amount);
      });

      setDraft(map);
    } catch (err) {
      console.error("LOAD ERROR:", err);
      alert("Failed to load budget data");
    } finally {
      setLoading(false);
    }
  }

  /* ================= CATEGORY ================= */

  const expenseParents = useMemo(() => {
    return (categories || []).filter(
      (c) => c.type === "expense" && !c.parent_id,
    );
  }, [categories]);

  /* ================= SAVE ================= */

  async function saveAll() {
    try {
      setSaving(true);

      await saveMonthlyIncome({
        month,
        amount: Number(income),
      });

      for (const catId in draft) {
        const amount = Number(draft[catId] || 0);
        if (amount <= 0) continue;

        const existing = budgets.find(
          (b) => String(b.category_id) === String(catId),
        );

        if (existing) {
          await updateBudget(existing.id, { amount });
        } else {
          await createBudget({
            category_id: catId,
            amount,
            month,
          });
        }
      }

      alert("Budget saved successfully");
      await load(); // refresh summary also
    } catch (err) {
      console.error(err);
      alert("Save failed");
    } finally {
      setSaving(false);
    }
  }

  /* ================= UI ================= */

  if (loading) return <p>Loading...</p>;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold">Smart Budget Planner ({month})</h1>

      {/* CATEGORY INPUT */}
      <div className="bg-white p-4 rounded-xl border">
        <h2 className="font-semibold mb-3">Category Budgets</h2>

        {expenseParents.map((cat) => (
          <div key={cat.id} className="flex justify-between py-2 border-b">
            <span>{cat.name}</span>

            <input
              type="number"
              value={draft[cat.id] || 0}
              onChange={(e) =>
                setDraft((prev) => ({
                  ...prev,
                  [cat.id]: Number(e.target.value),
                }))
              }
              className="input w-32"
            />
          </div>
        ))}
      </div>

      {/* SAVE */}
      <div className="flex justify-end">
        <button
          disabled={saving}
          onClick={saveAll}
          className="bg-blue-600 text-white px-5 py-2 rounded-lg"
        >
          {saving ? "Saving..." : "Save Budget"}
        </button>
      </div>

      {/* 🔥 FIXED CHART */}
      <BudgetChart
        data={(summary?.categories || []).map((c: any) => ({
          category_name: c.category_name,
          budget: c.budget,
          spent: c.spent, // ✅ THIS WAS MISSING
        }))}
      />
    </div>
  );
}
