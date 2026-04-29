"use client";

import {
  ArrowDownRight,
  ArrowUpRight,
  CalendarDays,
  Plus,
  RefreshCw,
  TrendingUp,
  WalletCards,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { DividendForm } from "@/components/portfolio/dividend-form";
import { TradeForm } from "@/components/portfolio/trade-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
import {
  addDividend,
  createTrade,
  fetchPortfolioSummary,
  listDividends,
} from "@/services/finance-service";
import type {
  DividendResponse,
  PortfolioSummary,
  PortfolioTransactionCreatePayload,
} from "@/types/api";

function formatQuantity(value: string) {
  return Number(value).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 6,
  });
}

export default function PortfolioPage() {
  const [summary, setSummary] = useState<PortfolioSummary | null>(null);
  const [dividends, setDividends] = useState<DividendResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modal, setModal] = useState<"trade" | "dividend" | null>(null);
  const [tradeType, setTradeType] = useState<"buy" | "sell">("buy");
  const [submitting, setSubmitting] = useState(false);

  const holdings = summary?.holdings ?? [];

  const allocation = useMemo(
    () =>
      holdings
        .map((holding) => ({
          symbol: holding.stock.symbol,
          value: Number(holding.market_value),
          color: "bg-brand-600",
        }))
        .sort((a, b) => b.value - a.value),
    [holdings],
  );

  const profitLossRows = useMemo(
    () =>
      holdings
        .map((holding) => ({
          symbol: holding.stock.symbol,
          value: Number(holding.unrealized_profit_loss),
        }))
        .sort((a, b) => Math.abs(b.value) - Math.abs(a.value)),
    [holdings],
  );

  const stockById = useMemo(
    () =>
      new Map(
        summary?.holdings.map((holding) => [
          holding.stock.id,
          holding.stock.symbol,
        ]),
      ),
    [summary],
  );

  const totalDividends = useMemo(
    () => dividends.reduce((sum, dividend) => sum + Number(dividend.amount), 0),
    [dividends],
  );

  const loadSummary = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setSummary(await fetchPortfolioSummary());
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Unable to load portfolio summary",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  const loadDividends = useCallback(async () => {
    try {
      setDividends(await listDividends());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to load dividends");
    }
  }, []);

  useEffect(() => {
    loadSummary();
    loadDividends();
  }, [loadSummary, loadDividends]);

  function openTrade(type: "buy" | "sell") {
    setTradeType(type);
    setModal("trade");
  }

  function openDividend() {
    setModal("dividend");
  }

  function closeModal() {
    setModal(null);
  }

  async function handleTrade(payload: PortfolioTransactionCreatePayload) {
    setSubmitting(true);
    setError(null);
    try {
      await createTrade(payload);
      closeModal();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to record trade");
      setSubmitting(false);
      return;
    }

    try {
      await loadSummary();
    } catch (err) {
      setError(
        err instanceof Error
          ? `Trade saved, but portfolio refresh failed: ${err.message}`
          : "Trade saved, but portfolio refresh failed",
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDividend(payload: {
    stock_id: string;
    amount: number;
    payment_date: string;
    notes?: string | null;
  }) {
    setSubmitting(true);
    setError(null);
    try {
      await addDividend(payload);
      closeModal();
      await loadDividends();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to add dividend");
    } finally {
      setSubmitting(false);
    }
  }

  const maxAllocation = Math.max(...allocation.map((item) => item.value), 1);
  const maxProfitLoss = Math.max(
    ...profitLossRows.map((item) => Math.abs(item.value)),
    1,
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Portfolio</h1>
          <p className="mt-1 text-sm text-muted">
            Buy and sell stocks, review holdings, track profit and dividends,
            and inspect market allocation.
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button
            variant="secondary"
            onClick={() => Promise.all([loadSummary(), loadDividends()])}
            disabled={loading}
          >
            <RefreshCw className="h-4 w-4" aria-hidden />
            Refresh
          </Button>
          <Button variant="secondary" onClick={() => openTrade("buy")}>
            <Plus className="h-4 w-4" aria-hidden />
            Buy stock
          </Button>
          <Button variant="secondary" onClick={() => openTrade("sell")}>
            <ArrowDownRight className="h-4 w-4" aria-hidden />
            Sell stock
          </Button>
          <Button onClick={openDividend}>
            <CalendarDays className="h-4 w-4" aria-hidden />
            Add dividend
          </Button>
        </div>
      </div>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Market value</p>
            <WalletCards className="h-4 w-4 text-brand-700" aria-hidden />
          </div>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {formatCurrency(summary?.total_market_value ?? 0)}
          </p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Cost basis</p>
            <TrendingUp className="h-4 w-4 text-cyan-700" aria-hidden />
          </div>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {formatCurrency(summary?.total_cost_basis ?? 0)}
          </p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Unrealized P/L</p>
            <ArrowUpRight className="h-4 w-4 text-emerald-700" aria-hidden />
          </div>
          <p
            className={`mt-2 text-2xl font-semibold ${summary?.total_unrealized_profit_loss && Number(summary.total_unrealized_profit_loss) < 0 ? "text-red-700" : "text-ink"}`}
          >
            {formatCurrency(summary?.total_unrealized_profit_loss ?? 0)}
          </p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted">Realized P/L</p>
            <ArrowUpRight className="h-4 w-4 text-emerald-700" aria-hidden />
          </div>
          <p
            className={`mt-2 text-2xl font-semibold ${summary?.total_realized_profit_loss && Number(summary.total_realized_profit_loss) < 0 ? "text-red-700" : "text-ink"}`}
          >
            {formatCurrency(summary?.total_realized_profit_loss ?? 0)}
          </p>
        </div>
      </section>

      {error ? (
        <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </p>
      ) : null}

      <section className="grid gap-4 xl:grid-cols-[1.4fr_0.6fr]">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <h2 className="text-base font-semibold text-ink">Holdings</h2>
          <p className="mt-2 text-sm text-muted">
            Current positions, average buy price, market value, and profit or
            loss.
          </p>
          <div className="mt-5 overflow-hidden rounded-lg border border-line">
            <div className="grid grid-cols-[1.4fr_110px_110px_110px_125px_125px] gap-4 border-b border-line bg-slate-50 px-5 py-3 text-xs font-semibold uppercase text-muted">
              <span>Stock</span>
              <span>Qty</span>
              <span>Avg price</span>
              <span>Price</span>
              <span>Market value</span>
              <span>Unrealized</span>
            </div>
            {loading ? (
              <p className="px-5 py-6 text-sm text-muted">
                Loading holdings...
              </p>
            ) : null}
            {!loading && !holdings.length ? (
              <p className="px-5 py-6 text-sm text-muted">
                No holdings in your portfolio yet.
              </p>
            ) : null}
            {holdings.map((holding) => (
              <div
                key={holding.stock.id}
                className="grid grid-cols-[1.4fr_110px_110px_110px_125px_125px] items-center gap-4 border-b border-line px-5 py-4 text-sm last:border-0"
              >
                <div>
                  <p className="font-semibold text-ink">
                    {holding.stock.symbol}
                  </p>
                  <p className="text-xs text-muted">{holding.stock.name}</p>
                </div>
                <span>{formatQuantity(holding.quantity)}</span>
                <span>
                  {formatCurrency(
                    holding.avg_buy_price,
                    holding.stock.currency,
                  )}
                </span>
                <span>
                  {formatCurrency(
                    holding.stock.last_price,
                    holding.stock.currency,
                  )}
                </span>
                <span>
                  {formatCurrency(holding.market_value, holding.stock.currency)}
                </span>
                <span
                  className={
                    Number(holding.unrealized_profit_loss) < 0
                      ? "text-red-700"
                      : "text-emerald-700"
                  }
                >
                  {formatCurrency(
                    holding.unrealized_profit_loss,
                    holding.stock.currency,
                  )}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="space-y-4">
          <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
            <h2 className="text-base font-semibold text-ink">
              Market allocation
            </h2>
            <div className="mt-5 space-y-4">
              {allocation.length ? (
                allocation.map((item) => (
                  <div key={item.symbol} className="space-y-2">
                    <div className="flex items-center justify-between text-sm text-muted">
                      <span>{item.symbol}</span>
                      <span>{formatCurrency(item.value)}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-slate-100">
                      <div
                        className="h-full bg-brand-600"
                        style={{
                          width: `${(item.value / maxAllocation) * 100}%`,
                        }}
                      />
                    </div>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted">
                  Add trades to populate allocation.
                </p>
              )}
            </div>
          </div>
          <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
            <h2 className="text-base font-semibold text-ink">
              Unrealized profit & loss
            </h2>
            <div className="mt-5 space-y-4">
              {profitLossRows.length ? (
                profitLossRows.map((item) => {
                  const ratio = Math.abs(item.value) / maxProfitLoss;
                  return (
                    <div key={item.symbol} className="space-y-2">
                      <div className="flex items-center justify-between text-sm text-muted">
                        <span>{item.symbol}</span>
                        <span
                          className={`${item.value < 0 ? "text-red-700" : "text-emerald-700"}`}
                        >
                          {formatCurrency(item.value)}
                        </span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-slate-100">
                        <div
                          className={`h-full ${item.value < 0 ? "bg-red-500" : "bg-emerald-500"}`}
                          style={{ width: `${Math.max(ratio * 100, 5)}%` }}
                        />
                      </div>
                    </div>
                  );
                })
              ) : (
                <p className="text-sm text-muted">
                  Unrealized P/L appears once you have holdings.
                </p>
              )}
            </div>
          </div>
        </div>
      </section>

      <section className="rounded-lg border border-line bg-white p-5 shadow-soft">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="text-base font-semibold text-ink">
              Dividend history
            </h2>
            <p className="mt-1 text-sm text-muted">
              Track dividend payouts and cash flow from holdings.
            </p>
          </div>
          <div className="rounded-lg border border-line bg-slate-50 px-3 py-2 text-sm text-slate-700">
            Total dividends: {formatCurrency(totalDividends)}
          </div>
        </div>

        <div className="mt-5 overflow-hidden rounded-lg border border-line">
          <div className="grid grid-cols-[1fr_110px_130px_1.2fr] gap-4 border-b border-line bg-slate-50 px-5 py-3 text-xs font-semibold uppercase text-muted">
            <span>Stock</span>
            <span>Amount</span>
            <span>Date</span>
            <span>Notes</span>
          </div>
          {loading ? (
            <p className="px-5 py-6 text-sm text-muted">Loading dividends...</p>
          ) : null}
          {!loading && !dividends.length ? (
            <p className="px-5 py-6 text-sm text-muted">
              No dividends recorded yet.
            </p>
          ) : null}
          {dividends.map((dividend) => (
            <div
              key={dividend.id}
              className="grid grid-cols-[1fr_110px_130px_1.2fr] items-center gap-4 border-b border-line px-5 py-4 text-sm last:border-0"
            >
              <span className="font-semibold text-ink">
                {stockById.get(dividend.stock_id) ?? dividend.stock_id}
              </span>
              <span>{formatCurrency(dividend.amount)}</span>
              <span>
                {new Date(dividend.payment_date).toLocaleDateString()}
              </span>
              <span className="text-muted">{dividend.notes ?? "—"}</span>
            </div>
          ))}
        </div>
      </section>

      <Modal
        open={modal !== null}
        onClose={closeModal}
        title={
          modal === "trade"
            ? `${tradeType === "buy" ? "Buy" : "Sell"} stock`
            : "Add dividend"
        }
        description={
          modal === "trade"
            ? "Enter a stock trade and record price, quantity, and fees."
            : "Record a dividend payout for one of your holdings."
        }
      >
        {modal === "trade" ? (
          <TradeForm
            defaultType={tradeType}
            onCancel={closeModal}
            onSubmit={handleTrade}
            submitting={submitting}
          />
        ) : null}
        {modal === "dividend" && summary ? (
          <DividendForm
            holdings={summary.holdings}
            onCancel={closeModal}
            onSubmit={handleDividend}
            submitting={submitting}
          />
        ) : null}
      </Modal>
    </div>
  );
}
