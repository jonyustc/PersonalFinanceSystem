"use client";

import { useEffect, useState } from "react";

import { fetchDashboard } from "@/services/finance-service";

import { IncomeExpenseChart } from "@/components/dashboard/bar-chart";
import { BudgetVsActual } from "@/components/dashboard/budget-vs-actual";
import CardAnalytics from "@/components/dashboard/card-analytics";
import CardDashboard from "@/components/dashboard/card-dashboard";
import { DashboardCards } from "@/components/dashboard/cards";
import { MonthlyTrend } from "@/components/dashboard/line-chart";
import { CategoryPie } from "@/components/dashboard/pie-chart";
import { RecentTransactions } from "@/components/dashboard/recent";

/* ================= HELPERS ================= */

function getCurrentMonth() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function getLastMonth(current: string) {
  const [year, month] = current.split("-").map(Number);
  const d = new Date(year, month - 2);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

/* ================= PAGE ================= */

export default function DashboardPage() {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  const [month, setMonth] = useState(getCurrentMonth());

  /* ================= LOAD ================= */

  useEffect(() => {
    load();
  }, [month]);

  async function load() {
    try {
      setLoading(true);
      const res = await fetchDashboard(month);
      setData(res);
    } catch (e) {
      console.error(e);
      alert("Failed to load dashboard");
    } finally {
      setLoading(false);
    }
  }

  if (loading) return <p>Loading...</p>;

  /* ================= UI ================= */

  return (
    <div className="space-y-6">
      {/* 🔝 HEADER */}
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold">Dashboard</h1>

        <div className="flex items-center gap-2">
          {/* QUICK BUTTONS */}
          <button
            onClick={() => setMonth(getCurrentMonth())}
            className="text-sm px-2 py-1 border rounded"
          >
            This Month
          </button>

          <button
            onClick={() => setMonth(getLastMonth(month))}
            className="text-sm px-2 py-1 border rounded"
          >
            Last Month
          </button>

          {/* MONTH PICKER */}
          <input
            type="month"
            value={month}
            onChange={(e) => setMonth(e.target.value)}
            className="border rounded px-3 py-1"
          />
        </div>
      </div>

      {/* 🔹 TOP SUMMARY */}
      <DashboardCards data={data} />

      {/* 💳 CARD SECTION (VERY IMPORTANT POSITION) */}
      <div className="grid gap-4 lg:grid-cols-2">
        <CardDashboard month={month} />
        <CardAnalytics month={month} />
      </div>

      {/* 📊 CHARTS */}
      <div className="grid gap-4 lg:grid-cols-2">
        <IncomeExpenseChart data={data} />
        <CategoryPie data={data.expense_by_category} />
      </div>

      {/* 📉 BUDGET */}
      <div className="grid gap-4">
        <BudgetVsActual data={data.budget_summary} />
      </div>

      {/* 📈 TREND + RECENT */}
      <div className="grid gap-4 lg:grid-cols-2">
        <MonthlyTrend data={data.monthly_cashflow} />
        <RecentTransactions data={data.recent_transactions} />
      </div>
    </div>
  );
}
