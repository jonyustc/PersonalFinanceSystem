"use client";

import { formatCurrency } from "@/lib/utils";
import {
  createTransaction,
  fetchAccounts,
  fetchCardAnalytics,
} from "@/services/finance-service";
import { useEffect, useState } from "react";

/* ================= COMPONENT ================= */

export default function CardAnalytics({ month }: { month: string }) {
  const [data, setData] = useState<any>(null);
  const [accounts, setAccounts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    load();
  }, [month]);

  async function load() {
    setLoading(true);
    const [analytics, acc] = await Promise.all([
      fetchCardAnalytics(month),
      fetchAccounts(),
    ]);
    setData(analytics);
    setAccounts(acc);
    setLoading(false);
  }

  if (loading) return <p>Loading insights...</p>;
  if (!data) return null;

  /* ================= AI INSIGHTS ================= */

  function getInsights() {
    const insights = [];

    if (data.payment_ratio < 50) {
      insights.push("⚠️ You are paying too little. Debt will grow.");
    }

    if (data.net_change > 0) {
      insights.push("📈 Your card debt increased this month.");
    }

    if (data.payment_ratio > 90) {
      insights.push("✅ Excellent! You are managing credit well.");
    }

    if (data.spent > data.paid * 2) {
      insights.push("💡 Spending is much higher than payments.");
    }

    return insights;
  }

  /* ================= PAY NOW ================= */

  async function handlePayNow() {
    const bank = accounts.find((a) => a.type !== "card");
    const card = accounts.find((a) => a.type === "card");

    if (!bank || !card) {
      alert("Bank or card account missing");
      return;
    }

    await createTransaction({
      type: "transfer",
      account_id: bank.id,
      transfer_account_id: card.id,
      amount: data.suggested_payment,
      txn_date: new Date().toISOString(),
    });

    alert("Payment successful");
    load();
  }

  /* ================= UI ================= */

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold">💳 Card Insights</h2>

      {/* SUMMARY */}
      <div className="grid grid-cols-3 gap-4">
        <Card title="Spent" value={data.spent} />
        <Card title="Paid" value={data.paid} green />
        <Card title="Debt Change" value={data.net_change} red />
      </div>

      {/* PAYMENT RATIO */}
      <div className="bg-white p-4 rounded-xl border">
        <p className="text-sm text-gray-500">Payment Ratio</p>

        <div className="w-full bg-gray-200 h-3 rounded mt-2">
          <div
            className="bg-green-500 h-3 rounded"
            style={{ width: `${Math.min(data.payment_ratio, 100)}%` }}
          />
        </div>

        <p className="text-sm mt-1">{data.payment_ratio}% paid</p>
      </div>

      {/* 📊 DAILY TREND */}
      <div className="bg-white p-4 rounded-xl border">
        <p className="text-sm text-gray-500">Daily Spending</p>

        {data.daily_trend.map((d: any) => (
          <div key={d.date} className="flex justify-between text-sm">
            <span>{d.date}</span>
            <span>{formatCurrency(d.amount)}</span>
          </div>
        ))}
      </div>

      {/* 🥧 CATEGORY */}
      <div className="bg-white p-4 rounded-xl border">
        <p className="text-sm text-gray-500">Category Breakdown</p>

        {data.category_breakdown.map((c: any) => (
          <div key={c.category} className="flex justify-between text-sm">
            <span>{c.category}</span>
            <span>{formatCurrency(c.amount)}</span>
          </div>
        ))}
      </div>

      {/* 🤖 AI INSIGHTS */}
      <div className="bg-blue-50 border p-3 rounded-lg space-y-1 text-sm">
        {getInsights().map((i, idx) => (
          <p key={idx}>💡 {i}</p>
        ))}
      </div>

      {/* 💸 PAY NOW */}
      {/* <div className="flex justify-between items-center bg-white p-4 border rounded-xl">
        <div>
          <p className="text-sm text-gray-500">Suggested Payment</p>
          <p className="font-semibold">
            {formatCurrency(data.suggested_payment)}
          </p>
        </div>

        <button
          onClick={handlePayNow}
          className="bg-blue-600 text-white px-4 py-2 rounded-lg"
        >
          Pay Now
        </button>
      </div> */}
    </div>
  );
}

/* ================= CARD ================= */

function Card({ title, value, red, green }: any) {
  return (
    <div className="bg-white p-4 rounded-xl border">
      <p className="text-xs text-gray-500">{title}</p>
      <p
        className={`text-lg font-semibold ${
          red ? "text-red-500" : green ? "text-green-600" : ""
        }`}
      >
        {formatCurrency(value)}
      </p>
    </div>
  );
}
