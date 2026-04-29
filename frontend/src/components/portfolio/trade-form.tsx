"use client";

import { Button } from "@/components/ui/button";
import type { PortfolioTransactionCreatePayload } from "@/types/api";
import { useEffect, useState, type FormEvent } from "react";

type TradeFormProps = {
  defaultType: "buy" | "sell";
  onCancel: () => void;
  onSubmit: (payload: PortfolioTransactionCreatePayload) => Promise<void>;
  submitting: boolean;
};

export function TradeForm({
  defaultType,
  onCancel,
  onSubmit,
  submitting,
}: TradeFormProps) {
  const [txnType, setTxnType] = useState<"buy" | "sell">(defaultType);
  const [symbol, setSymbol] = useState("");
  const [name, setName] = useState("");
  const [exchange, setExchange] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [quantity, setQuantity] = useState(0);
  const [price, setPrice] = useState(0);
  const [fees, setFees] = useState(0);
  const [txnDate, setTxnDate] = useState(() =>
    new Date().toISOString().slice(0, 10),
  );

  useEffect(() => {
    setTxnType(defaultType);
  }, [defaultType]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await onSubmit({
      stock: {
        symbol: symbol.trim().toUpperCase(),
        name: name.trim(),
        exchange: exchange.trim() || null,
        currency: currency.trim().toUpperCase(),
        last_price: price,
      },
      txn_type: txnType,
      quantity,
      price,
      fees,
      txn_date: txnDate,
    });
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Trade type
          </span>
          <select
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={txnType}
            onChange={(event) =>
              setTxnType(event.target.value as "buy" | "sell")
            }
          >
            <option value="buy">Buy</option>
            <option value="sell">Sell</option>
          </select>
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Symbol
          </span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={symbol}
            onChange={(event) => setSymbol(event.target.value)}
            required
          />
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Stock name
          </span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={name}
            onChange={(event) => setName(event.target.value)}
            required
          />
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Exchange
          </span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={exchange}
            onChange={(event) => setExchange(event.target.value)}
          />
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Currency
          </span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            value={currency}
            onChange={(event) => setCurrency(event.target.value)}
            required
          />
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Quantity
          </span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            type="number"
            step="0.000001"
            min="0"
            value={quantity}
            onChange={(event) => setQuantity(Number(event.target.value))}
            required
          />
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Price</span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            type="number"
            step="0.0001"
            min="0"
            value={price}
            onChange={(event) => setPrice(Number(event.target.value))}
            required
          />
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Fees</span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            type="number"
            step="0.01"
            min="0"
            value={fees}
            onChange={(event) => setFees(Number(event.target.value))}
          />
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">
            Trade date
          </span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            type="date"
            value={txnDate}
            onChange={(event) => setTxnDate(event.target.value)}
            required
          />
        </label>
      </div>

      <div className="flex flex-wrap gap-3 pt-2">
        <Button
          type="button"
          variant="secondary"
          onClick={onCancel}
          disabled={submitting}
        >
          Cancel
        </Button>
        <Button
          type="submit"
          disabled={submitting || !symbol || !name || !quantity || !price}
        >
          {txnType === "buy" ? "Buy stock" : "Sell stock"}
        </Button>
      </div>
    </form>
  );
}
