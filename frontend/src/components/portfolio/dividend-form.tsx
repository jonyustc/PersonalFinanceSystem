"use client";

import { Button } from "@/components/ui/button";
import type { DividendCreatePayload, StockHolding } from "@/types/api";
import { useState, type FormEvent } from "react";

type DividendFormProps = {
  holdings: StockHolding[];
  onCancel: () => void;
  onSubmit: (payload: DividendCreatePayload) => Promise<void>;
  submitting: boolean;
};

export function DividendForm({
  holdings,
  onCancel,
  onSubmit,
  submitting,
}: DividendFormProps) {
  const [stockId, setStockId] = useState(holdings[0]?.stock?.id ?? "");
  const [amount, setAmount] = useState(0);
  const [paymentDate, setPaymentDate] = useState(() =>
    new Date().toISOString().slice(0, 10),
  );
  const [notes, setNotes] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const selected = holdings.find((holding) => holding.stock.id === stockId);
    if (!selected) return;

    await onSubmit({
      stock_id: selected.stock.id,
      amount,
      payment_date: paymentDate,
      notes: notes.trim() || undefined,
    });
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Stock</span>
        <select
          className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          value={stockId}
          onChange={(event) => setStockId(event.target.value)}
          required
        >
          <option value="">Select stock</option>
          {holdings.map((holding) => (
            <option key={holding.stock.id} value={holding.stock.id}>
              {holding.stock.symbol} — {holding.stock.name}
            </option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Amount</span>
        <input
          className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          type="number"
          step="0.01"
          min="0"
          value={amount}
          onChange={(event) => setAmount(Number(event.target.value))}
          required
        />
      </label>

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">
          Payment date
        </span>
        <input
          className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          type="date"
          value={paymentDate}
          onChange={(event) => setPaymentDate(event.target.value)}
          required
        />
      </label>

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Notes</span>
        <textarea
          className="min-h-[88px] w-full rounded-md border border-line bg-white px-3 py-2 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          value={notes}
          onChange={(event) => setNotes(event.target.value)}
        />
      </label>

      <div className="flex flex-wrap gap-3 pt-2">
        <Button
          type="button"
          variant="secondary"
          onClick={onCancel}
          disabled={submitting}
        >
          Cancel
        </Button>
        <Button type="submit" disabled={submitting || !stockId || !amount}>
          Add dividend
        </Button>
      </div>
    </form>
  );
}
