"use client";

import {
  fetchCategories,
  fetchCategorySpending,
} from "@/services/finance-service";
import { useEffect, useState } from "react";

import { CategoryPie } from "@/components/reports/category-pie";
import { formatCurrency } from "@/lib/utils";

import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
} from "recharts";

export default function CategoriesPage() {
  const [categories, setCategories] = useState<any[]>([]);
  const [spending, setSpending] = useState<any[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    load();
  }, []);

  async function load() {
    try {
      const [cats, spend] = await Promise.all([
        fetchCategories(),
        fetchCategorySpending(),
      ]);

      setCategories(cats || []);
      setSpending(spend || []);
    } catch {
      setError("Failed to load category data");
    }
  }

  function getCategoryName(id: string) {
    return categories.find((c) => c.id === id)?.name || "Unknown";
  }

  // 👉 pie chart data
  const pieData = spending.map((c) => ({
    label: getCategoryName(c.label),
    value: Number(c.amount || 0),
  }));

  // 👉 bar chart data
  const barData = spending.map((c) => ({
    name: getCategoryName(c.label),
    amount: Number(c.amount || 0),
  }));

  // 👉 summary
  const total = pieData.reduce((sum, c) => sum + c.value, 0);

  const topCategory =
    pieData.length > 0
      ? pieData.reduce((max, c) => (c.value > max.value ? c : max))
      : null;

  return (
    <div className="space-y-6">
      {/* HEADER */}
      <div>
        <h1 className="text-2xl font-semibold">Categories</h1>
        <p className="text-sm text-gray-500">Category-wise spending analysis</p>
      </div>

      {error && (
        <div className="bg-red-50 text-red-600 p-3 rounded">{error}</div>
      )}

      {/* SUMMARY */}
      <div className="grid gap-4 sm:grid-cols-2">
        <Card title="Total Spending">
          <p className="text-2xl font-semibold">{formatCurrency(total)}</p>
        </Card>

        <Card title="Top Category">
          <p className="text-lg font-medium">{topCategory?.label || "--"}</p>
          <p className="text-sm text-gray-500">
            {formatCurrency(topCategory?.value || 0)}
          </p>
        </Card>
      </div>

      {/* CHARTS */}
      <div className="grid gap-4 lg:grid-cols-2">
        {/* PIE */}
        <CategoryPie data={pieData} />

        {/* BAR */}
        <div className="bg-white p-4 rounded-2xl border shadow-sm">
          <h3 className="mb-3 font-semibold">Category Ranking</h3>

          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={barData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />

              <XAxis dataKey="name" tick={{ fontSize: 12 }} />

              <Tooltip formatter={(v: number) => formatCurrency(v)} />

              <Bar dataKey="amount" fill="#6366f1" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* LIST */}
      <Card title="Category List">
        {spending.length === 0 && (
          <p className="text-sm text-gray-500">No data</p>
        )}

        {spending.map((c) => (
          <Row key={c.label} name={getCategoryName(c.label)} value={c.amount} />
        ))}
      </Card>
    </div>
  );
}

/* ================= UI ================= */

function Card({ title, children }: any) {
  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h2 className="font-semibold mb-3">{title}</h2>
      {children}
    </div>
  );
}

function Row({ name, value }: any) {
  return (
    <div className="flex justify-between py-2 border-b last:border-none">
      <span>{name}</span>
      <span className="font-medium">{formatCurrency(value)}</span>
    </div>
  );
}
