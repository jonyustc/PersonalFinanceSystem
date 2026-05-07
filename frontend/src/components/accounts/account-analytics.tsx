"use client";

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { formatCurrency } from "@/lib/utils";

import type { AccountAnalytics } from "@/types/api";

const palette = ["#137f65", "#2563eb", "#d97706", "#7c3aed"];
const currencyTooltip = (value: unknown) => formatCurrency(Number(value ?? 0));

type Props = {
  analytics: AccountAnalytics | null;
};

export function AccountAnalyticsCharts({ analytics }: Props) {
  if (!analytics) {
    return null;
  }

  const distribution = analytics.distribution.map((item) => ({
    name: item.type.toUpperCase(),
    value: Math.abs(Number(item.total)),
  }));
  const debtVsAssets = analytics.debt_vs_assets.map((item) => ({
    label: item.label,
    amount: Number(item.amount),
  }));
  const trend = analytics.net_worth_trend.map((point) => ({
    date: point.date,
    netWorth: Number(point.net_worth),
  }));

  return (
    <div className="grid gap-4 xl:grid-cols-2">
      <section className="rounded-md border border-line bg-white p-4 shadow-soft">
        <h2 className="text-sm font-semibold text-ink">Net Worth Trend</h2>
        <div className="mt-4 h-72">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={trend}>
              <defs>
                <linearGradient id="netWorthFill" x1="0" x2="0" y1="0" y2="1">
                  <stop offset="5%" stopColor="#137f65" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#137f65" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="#e5e7eb" strokeDasharray="3 3" />
              <XAxis dataKey="date" tick={{ fontSize: 12 }} />
              <YAxis tickFormatter={(value) => formatCurrency(Number(value)).replace(".00", "")} tick={{ fontSize: 12 }} />
              <Tooltip formatter={currencyTooltip} />
              <Area dataKey="netWorth" fill="url(#netWorthFill)" stroke="#137f65" strokeWidth={2} />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </section>

      <section className="rounded-md border border-line bg-white p-4 shadow-soft">
        <h2 className="text-sm font-semibold text-ink">Account Distribution</h2>
        <div className="mt-4 h-72">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie data={distribution} dataKey="value" nameKey="name" innerRadius={62} outerRadius={96} paddingAngle={3}>
                {distribution.map((entry, index) => (
                  <Cell key={entry.name} fill={palette[index % palette.length]} />
                ))}
              </Pie>
              <Tooltip formatter={currencyTooltip} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </section>

      <section className="rounded-md border border-line bg-white p-4 shadow-soft xl:col-span-2">
        <h2 className="text-sm font-semibold text-ink">Debt vs Assets</h2>
        <div className="mt-4 h-72">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={debtVsAssets}>
              <CartesianGrid stroke="#e5e7eb" strokeDasharray="3 3" />
              <XAxis dataKey="label" tick={{ fontSize: 12 }} />
              <YAxis tickFormatter={(value) => formatCurrency(Number(value)).replace(".00", "")} tick={{ fontSize: 12 }} />
              <Tooltip formatter={currencyTooltip} />
              <Bar dataKey="amount" radius={[6, 6, 0, 0]} fill="#2563eb" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </section>
    </div>
  );
}
