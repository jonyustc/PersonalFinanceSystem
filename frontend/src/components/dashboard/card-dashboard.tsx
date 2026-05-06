"use client";

import { useEffect, useState } from "react";
import { fetchCardDashboard } from "@/services/finance-service";
import { formatCurrency } from "@/lib/utils";

/* ================= TYPES ================= */

type Props = {
  month: string;
};

/* ================= COMPONENT ================= */

export default function CardDashboard({ month }: Props) {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    load();
  }, [month]);

  async function load() {
    try {
      setLoading(true);
      setError("");

      const res = await fetchCardDashboard(month);
      setData(res);
    } catch (e) {
      console.error(e);
      setError("Failed to load card data");
    } finally {
      setLoading(false);
    }
  }

  if (loading) return <p>Loading card data...</p>;
  if (error) return <p className="text-red-500">{error}</p>;
  if (!data) return null;

  /* ================= UTIL COLOR ================= */

  function getUtilColor(util: number) {
    if (util < 30) return "bg-green-500";
    if (util < 70) return "bg-yellow-500";
    return "bg-red-500";
  }

  /* ================= UI ================= */

  return (
    <div className="space-y-4">
      {/* HEADER */}
      <h2 className="text-lg font-semibold">💳 Credit Cards</h2>

      {/* SUMMARY */}
      <div className="grid grid-cols-3 gap-4">
        <Card title="Outstanding" value={data.total_outstanding} red />
        <Card title="Spent" value={data.monthly_spent} />
        <Card title="Paid" value={data.payments} green />
      </div>

      {/* UTILIZATION */}
      <div className="bg-white p-4 rounded-xl border">
        <p className="text-sm text-gray-500">Utilization</p>

        <div className="w-full bg-gray-200 h-3 rounded mt-2">
          <div
            className={`${getUtilColor(
              data.utilization
            )} h-3 rounded transition-all`}
            style={{ width: `${Math.min(data.utilization, 100)}%` }}
          />
        </div>

        <p className="text-sm mt-1 font-medium">
          {data.utilization}% used
        </p>
      </div>

      {/* CARD LIST */}
      <div className="bg-white p-4 rounded-xl border space-y-3">
        {data.cards.map((c: any) => (
          <div
            key={c.id}
            className="flex justify-between items-center border-b pb-2 last:border-none"
          >
            {/* LEFT */}
            <div>
              <p className="font-medium">{c.name}</p>
              <p className="text-xs text-gray-500">
                Limit: {formatCurrency(c.limit)}
              </p>
            </div>

            {/* RIGHT */}
            <div className="text-right">
              <p className="text-red-500 font-semibold">
                {formatCurrency(c.balance)}
              </p>
              <p className="text-xs text-gray-500">
                {c.utilization.toFixed(1)}%
              </p>
            </div>
          </div>
        ))}

        {data.cards.length === 0 && (
          <p className="text-sm text-gray-500">No card accounts</p>
        )}
      </div>
    </div>
  );
}

/* ================= SMALL CARD ================= */

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