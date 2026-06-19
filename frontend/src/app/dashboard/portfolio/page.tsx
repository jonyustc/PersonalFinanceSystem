"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowDownLeft,
  ArrowUpRight,
  Banknote,
  ChartPie,
  CircleDollarSign,
  Coins,
  Gauge,
  LineChart as LineChartIcon,
  Plus,
  Pencil,
  RefreshCw,
  Sparkles,
  Trash2,
  TrendingUp,
  X,
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { Button } from "@/components/ui/button";
import { cn, formatCurrency } from "@/lib/utils";
import {
  createPortfolioTransaction,
  deletePortfolioTransaction,
  fetchAccounts,
  fetchAnnualPerformance,
  fetchPerformanceSeries,
  fetchPortfolioAnalytics,
  fetchPortfolios,
  fetchPortfolioSummary,
  fetchPortfolioTransactions,
  fetchStocks,
  searchDseStocks,
  refreshStockPrices,
  updatePortfolioTransaction,
} from "@/services/finance-service";
import type {
  Account,
  AnnualPerformanceResponse,
  PerformanceSeriesResponse,
  Portfolio,
  PortfolioAnalyticsResponse,
  PortfolioKind,
  PortfolioSummaryV2,
  PortfolioTransaction,
  PortfolioTxnType,
  Stock,
} from "@/types/api";

function todayValue() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function asNumber(value: string | number | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Portfolio data failed to load";
}

function percentOf(value: string | number | null | undefined, total: string | number | null | undefined) {
  const totalValue = asNumber(total);
  if (totalValue <= 0) return 0;
  return (asNumber(value) / totalValue) * 100;
}

function displayPercent(value: number) {
  return `${value.toFixed(value >= 10 ? 1 : 2)}%`;
}

function signedPercent(value: string | number | null | undefined) {
  const num = asNumber(value);
  return `${num >= 0 ? "+" : ""}${num.toFixed(2)}%`;
}

function formatMultiple(value: string | number | null | undefined) {
  return `${asNumber(value).toFixed(2)}×`;
}

const ADVANCED_STORAGE_KEY = "portfolio:advanced";

const KIND_LABELS: Record<PortfolioKind, string> = {
  long_term_sip: "Long-Term SIP",
  mid_term_trading: "Mid-Term Trading",
  general: "General",
};

const CHART_COLORS = ["#6366f1", "#22c55e", "#f97316", "#ef4444", "#06b6d4"];

function isBrokerAccount(account: Account) {
  const subtype = (account.account_subtype ?? "").trim().toLowerCase().replace(/\s+/g, "_");
  return ["stock_broker", "broker", "stock", "stocks"].includes(subtype);
}

function barWidth(value: number) {
  if (value <= 0) return "0%";
  return `${Math.max(2, Math.min(value, 100))}%`;
}

const txnTypes: { value: PortfolioTxnType; label: string }[] = [
  { value: "buy", label: "Buy" },
  { value: "sell", label: "Sell" },
  { value: "withdraw", label: "Withdraw" },
  { value: "income", label: "Dividend" },
];

type PortfolioTab = "dashboard" | "holding" | "performance" | "transaction" | "dividend" | "market";

const portfolioTabs: { value: PortfolioTab; label: string; mobileLabel: string }[] = [
  { value: "dashboard", label: "Dashboard", mobileLabel: "Dashboard" },
  { value: "holding", label: "Holding", mobileLabel: "Holding" },
  { value: "performance", label: "Performance", mobileLabel: "Perf" },
  { value: "transaction", label: "Transaction", mobileLabel: "Trade" },
  { value: "dividend", label: "Dividend", mobileLabel: "Dividend" },
  { value: "market", label: "Market Price", mobileLabel: "Market" },
];

export default function PortfolioPage() {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    txn_type: "buy" as PortfolioTxnType,
    stock_id: "",
    new_stock_name: "",
    new_stock_symbol: "",
    broker_account_id: "",
    quantity: "",
    price: "",
    fees: "",
    txn_date: todayValue(),
    notes: "",
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<PortfolioTransaction | null>(null);
  const [activeTab, setActiveTab] = useState<PortfolioTab>("dashboard");
  const [selectedPortfolioId, setSelectedPortfolioId] = useState<string>("");
  const [advanced, setAdvanced] = useState(false);

  // Persist the Advanced Investor Analytics preference per the spec.
  useEffect(() => {
    if (typeof window === "undefined") return;
    setAdvanced(window.localStorage.getItem(ADVANCED_STORAGE_KEY) === "1");
  }, []);
  function toggleAdvanced() {
    setAdvanced((current) => {
      const next = !current;
      if (typeof window !== "undefined") {
        window.localStorage.setItem(ADVANCED_STORAGE_KEY, next ? "1" : "0");
      }
      return next;
    });
  }

  const portfolioId = selectedPortfolioId || null;

  const portfoliosQuery = useQuery({ queryKey: ["portfolio", "portfolios"], queryFn: fetchPortfolios });
  const summaryQuery = useQuery({
    queryKey: ["portfolio", "summary", portfolioId],
    queryFn: () => fetchPortfolioSummary(portfolioId),
  });
  const transactionsQuery = useQuery({
    queryKey: ["portfolio", "transactions", portfolioId],
    queryFn: () => fetchPortfolioTransactions(100, portfolioId),
  });
  const analyticsQuery = useQuery({
    queryKey: ["portfolio", "analytics", portfolioId],
    queryFn: () => fetchPortfolioAnalytics(portfolioId),
    enabled: activeTab === "performance",
  });
  const annualQuery = useQuery({
    queryKey: ["portfolio", "annual", portfolioId],
    queryFn: () => fetchAnnualPerformance(portfolioId),
    enabled: activeTab === "performance",
  });
  const seriesQuery = useQuery({
    queryKey: ["portfolio", "series", portfolioId],
    queryFn: () => fetchPerformanceSeries(portfolioId),
    enabled: activeTab === "performance",
  });
  const stocksQuery = useQuery({ queryKey: ["portfolio", "stocks"], queryFn: fetchStocks });
  const accountsQuery = useQuery({ queryKey: ["accounts"], queryFn: fetchAccounts });
  const needsStock = ["buy", "sell", "income"].includes(form.txn_type);
  const isTrade = ["buy", "sell"].includes(form.txn_type);
  const dseQuery = useQuery({
    queryKey: ["portfolio", "dse-search", form.new_stock_symbol],
    queryFn: () => searchDseStocks(form.new_stock_symbol),
    enabled: needsStock && !form.stock_id && form.new_stock_symbol.trim().length >= 2,
  });

  const summary = summaryQuery.data;
  const transactions = transactionsQuery.data ?? [];
  const stocks = stocksQuery.data ?? [];
  const portfolios = useMemo(() => portfoliosQuery.data ?? [], [portfoliosQuery.data]);
  const portfolioNameById = useMemo(
    () => new Map(portfolios.map((portfolio) => [portfolio.id, portfolio.name])),
    [portfolios],
  );

  // When a broker-account portfolio is selected, default new trades to that account.
  useEffect(() => {
    const selected = portfolios.find((portfolio) => portfolio.id === selectedPortfolioId);
    if (selected?.broker_account_id) {
      setForm((current) => ({ ...current, broker_account_id: selected.broker_account_id as string }));
    }
  }, [selectedPortfolioId, portfolios]);
  const brokerAccounts = useMemo(
    () => (accountsQuery.data ?? []).filter((account) => isBrokerAccount(account) && account.is_active && !account.archived),
    [accountsQuery.data],
  );
  const selectedStock = stocks.find((stock) => stock.id === form.stock_id);
  const dataError = summaryQuery.error ?? transactionsQuery.error ?? stocksQuery.error ?? accountsQuery.error;

  async function refresh() {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["portfolio"] }),
      queryClient.invalidateQueries({ queryKey: ["accounts"] }),
    ]);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const useNewStock = needsStock && !form.stock_id && form.new_stock_name.trim();
      const payload = {
        txn_type: form.txn_type,
        portfolio_id: portfolioId,
        stock_id: form.stock_id || null,
        stock: useNewStock
          ? {
              symbol: (form.new_stock_symbol || form.new_stock_name).trim().toUpperCase(),
              name: form.new_stock_name.trim(),
              exchange: "DSE",
              currency: "BDT",
              last_price: asNumber(form.price),
            }
          : null,
        broker_account_id: form.broker_account_id || null,
        quantity: isTrade ? asNumber(form.quantity) : form.txn_type === "income" ? 1 : 0,
        price: asNumber(form.price),
        fees: form.fees ? asNumber(form.fees) : null,
        txn_date: form.txn_date,
        notes: form.notes || null,
      };
      if (editing) {
        await updatePortfolioTransaction(editing.id, payload);
      } else {
        await createPortfolioTransaction(payload);
      }
      setForm((current) => ({
        ...current,
        quantity: "",
        price: "",
        fees: "",
        notes: "",
        new_stock_name: "",
        new_stock_symbol: "",
      }));
      setEditing(null);
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Transaction save failed");
    } finally {
      setSaving(false);
    }
  }

  function editTransaction(transaction: PortfolioTransaction) {
    setEditing(transaction);
    setForm({
      txn_type: transaction.txn_type,
      stock_id: transaction.stock_id ?? "",
      new_stock_name: "",
      new_stock_symbol: "",
      broker_account_id: transaction.broker_account_id ?? "",
      quantity: transaction.quantity === "0.000000" ? "" : String(asNumber(transaction.quantity)),
      price: String(asNumber(transaction.price)),
      fees: transaction.fees === "0.00" ? "" : String(asNumber(transaction.fees)),
      txn_date: transaction.txn_date,
      notes: transaction.notes ?? "",
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function cancelEdit() {
    setEditing(null);
    setForm((current) => ({
      ...current,
      txn_type: "buy",
      stock_id: "",
      new_stock_name: "",
      new_stock_symbol: "",
      quantity: "",
      price: "",
      fees: "",
      notes: "",
      txn_date: todayValue(),
    }));
  }

  async function removeTransaction(transaction: PortfolioTransaction) {
    if (!confirm(`Delete ${transaction.txn_type} ${transaction.stock?.name ?? "transaction"}?`)) return;
    await deletePortfolioTransaction(transaction.id);
    if (editing?.id === transaction.id) cancelEdit();
    await refresh();
  }

  return (
    <div className="min-w-0 max-w-full overflow-x-hidden space-y-3 md:space-y-6">
      <section className="-mx-3 border-b border-line bg-white px-3 py-3 shadow-sm sm:-mx-4 sm:px-4 md:mx-0 md:rounded-md md:border md:px-4 md:py-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold text-ink md:text-2xl">Stock Portfolio</h1>
            <p className="text-xs text-muted md:text-sm">Broker cash, holdings, trades, and dividends.</p>
          </div>
          <Button variant="secondary" onClick={refresh}>
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
        <PortfolioControls
          portfolios={portfolios}
          selectedPortfolioId={selectedPortfolioId}
          onSelect={setSelectedPortfolioId}
          advanced={advanced}
          onToggleAdvanced={toggleAdvanced}
        />
        <div className="mt-2 md:mt-3">
          <PortfolioTabs activeTab={activeTab} onChange={setActiveTab} />
        </div>
      </section>

      {error ? <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</div> : null}
      {dataError ? <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{errorMessage(dataError)}</div> : null}

      {activeTab === "dashboard" ? (
        <>
          <section className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <Metric label="Total Investment" value={summary?.total_investment} icon={Banknote} />
            <Metric label="Current Value" value={summary?.current_equity_value} icon={Coins} />
            <Metric label="Total Return" value={summary?.total_return} icon={TrendingUp} warn={asNumber(summary?.total_return) < 0} />
            <Metric label="Portfolio Value" value={summary?.total_portfolio_value} icon={Gauge} />
          </section>

          <section className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <Metric label="Realized Gain" value={summary?.total_realized_profit} icon={CircleDollarSign} warn={asNumber(summary?.total_realized_profit) < 0} />
            <Metric label="Unrealized Gain" value={summary?.total_unrealized_gain} icon={LineChartIcon} warn={asNumber(summary?.total_unrealized_gain) < 0} />
            <Metric label="Dividend Income" value={summary?.total_dividend_income} icon={Coins} />
            <PercentMetric label="ROI" value={summary?.roi_percent} />
          </section>

          {advanced ? <AdvancedInvestorPanel summary={summary} /> : null}

          <section className="grid gap-3 lg:grid-cols-2">
            <PortfolioSnapshot summary={summary} />
            <BrokerAccountsPanel summary={summary} accounts={brokerAccounts} />
          </section>
        </>
      ) : null}

      {activeTab === "holding" ? <HoldingsSection summary={summary} loading={summaryQuery.isLoading} advanced={advanced} /> : null}

      {activeTab === "performance" ? (
        <PerformanceSection
          series={seriesQuery.data}
          annual={annualQuery.data}
          analytics={analyticsQuery.data}
          advanced={advanced}
          loading={seriesQuery.isLoading || annualQuery.isLoading}
        />
      ) : null}

      {activeTab === "transaction" ? (
        <>
          <section className="rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-ink">{editing ? "Edit Stock Transaction" : "Add Stock Transaction"}</h2>
              {editing ? (
                <button
                  type="button"
                  onClick={cancelEdit}
                  className="inline-flex h-8 items-center gap-1 rounded-md border border-line bg-white px-2 text-xs font-semibold text-muted"
                >
                  <X className="h-3.5 w-3.5" />
                  Cancel
                </button>
              ) : (
                <span className="text-xs text-muted">BDT</span>
              )}
            </div>

            <form onSubmit={submit} className="space-y-3">
              <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
                {txnTypes.map((type) => (
                  <button
                    key={type.value}
                    type="button"
                    onClick={() => setForm((current) => ({ ...current, txn_type: type.value }))}
                    className={cn(
                      "h-9 min-w-0 rounded-md border px-1 text-xs font-semibold",
                      form.txn_type === type.value ? "border-brand-600 bg-brand-600 text-white" : "border-line bg-surface text-muted",
                    )}
                  >
                    {type.label}
                  </button>
                ))}
              </div>

              <div className="grid gap-2 md:grid-cols-2">
                <div>
                  <label className="mb-1 block text-[11px] font-semibold text-muted">Portfolio (broker account)</label>
                  <select
                    value={form.broker_account_id}
                    onChange={(event) => setForm((current) => ({ ...current, broker_account_id: event.target.value }))}
                    className="input w-full"
                  >
                    <option value="">My Portfolio (no broker account)</option>
                    {brokerAccounts.map((account: Account) => (
                      <option key={account.id} value={account.id}>
                        {account.name} ({formatCurrency(account.balance, account.currency)})
                      </option>
                    ))}
                  </select>
                </div>

                {needsStock ? (
                  <select
                    value={form.stock_id}
                    onChange={(event) => setForm((current) => ({ ...current, stock_id: event.target.value }))}
                    className="input"
                  >
                    <option value="">New stock</option>
                    {stocks.map((stock: Stock) => (
                      <option key={stock.id} value={stock.id}>
                        {stock.name} ({stock.symbol})
                      </option>
                    ))}
                  </select>
                ) : null}
              </div>

              {needsStock && !form.stock_id ? (
                <div className="space-y-2">
                  <div className="grid gap-2 md:grid-cols-2">
                    <input
                      className="input"
                      placeholder="DSE trading code"
                      value={form.new_stock_symbol}
                      onChange={(event) => setForm((current) => ({ ...current, new_stock_symbol: event.target.value.toUpperCase() }))}
                    />
                    <input
                      className="input"
                      placeholder="Stock name from DSE"
                      value={form.new_stock_name}
                      onChange={(event) => setForm((current) => ({ ...current, new_stock_name: event.target.value }))}
                    />
                  </div>
                  {dseQuery.data?.length ? (
                    <div className="grid gap-2 md:grid-cols-2">
                      {dseQuery.data.map((stock) => (
                        <button
                          key={stock.symbol}
                          type="button"
                          onClick={() =>
                            setForm((current) => ({
                              ...current,
                              new_stock_symbol: stock.symbol,
                              new_stock_name: stock.name,
                              price: String(asNumber(stock.last_price)),
                            }))
                          }
                          className="min-w-0 rounded-md border border-line bg-surface p-2 text-left hover:border-brand-600"
                        >
                          <span className="block truncate text-xs font-semibold text-ink">{stock.symbol}</span>
                          <span className="block truncate text-xs text-muted">{stock.name}</span>
                        </button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ) : null}

              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 md:grid-cols-4">
                {isTrade ? (
                  <input
                    className="input"
                    inputMode="decimal"
                    placeholder="Quantity"
                    value={form.quantity}
                    onChange={(event) => setForm((current) => ({ ...current, quantity: event.target.value }))}
                  />
                ) : null}
                <input
                  className="input"
                  inputMode="decimal"
                  placeholder={form.txn_type === "income" ? "Dividend amount" : form.txn_type === "deposit" || form.txn_type === "withdraw" ? "Amount" : "Price/share"}
                  value={form.price}
                  onChange={(event) => setForm((current) => ({ ...current, price: event.target.value }))}
                />
                {isTrade ? (
                  <input
                    className="input"
                    inputMode="decimal"
                    placeholder="Broker fee"
                    value={form.fees}
                    onChange={(event) => setForm((current) => ({ ...current, fees: event.target.value }))}
                  />
                ) : null}
                <input
                  className="input"
                  type="date"
                  value={form.txn_date}
                  onChange={(event) => setForm((current) => ({ ...current, txn_date: event.target.value }))}
                />
              </div>

              <input
                className="input"
                placeholder={selectedStock ? `Note for ${selectedStock.name}` : "Note"}
                value={form.notes}
                onChange={(event) => setForm((current) => ({ ...current, notes: event.target.value }))}
              />

              <Button type="submit" disabled={saving}>
                <Plus className="h-4 w-4" />
                {saving ? "Saving..." : editing ? "Update Transaction" : "Save Transaction"}
              </Button>
            </form>
          </section>

          <TransactionsSection
            transactions={transactions}
            loading={transactionsQuery.isLoading}
            portfolioNameById={portfolioNameById}
            onEdit={editTransaction}
            onDelete={removeTransaction}
          />
        </>
      ) : null}

      {activeTab === "dividend" ? <DividendReportPanel summary={summary} /> : null}

      {activeTab === "market" ? (
        <MarketPriceSection
          stocks={stocks}
          loading={stocksQuery.isLoading}
          onSaved={refresh}
        />
      ) : null}
    </div>
  );
}

function PortfolioTabs({ activeTab, onChange }: { activeTab: PortfolioTab; onChange: (tab: PortfolioTab) => void }) {
  return (
    <section className="rounded-md border border-line bg-white p-1 shadow-sm">
      <div className="grid grid-cols-3 gap-1 sm:grid-cols-6">
        {portfolioTabs.map((tab) => (
          <button
            key={tab.value}
            type="button"
            onClick={() => onChange(tab.value)}
            className={cn(
              "h-9 min-w-0 rounded-md px-1.5 text-[11px] font-semibold transition sm:text-xs",
              activeTab === tab.value ? "bg-brand-600 text-white shadow-sm" : "bg-surface text-muted hover:text-ink",
            )}
          >
            <span className="block truncate sm:hidden">{tab.mobileLabel}</span>
            <span className="hidden truncate sm:block">{tab.label}</span>
          </button>
        ))}
      </div>
    </section>
  );
}

function PortfolioSnapshot({ summary }: { summary?: PortfolioSummaryV2 }) {
  return (
    <Panel title="Portfolio Snapshot">
      <div className="grid grid-cols-2 gap-2 text-xs">
        <Mini label="Deposited" value={formatCurrency(summary?.invested_capital ?? 0, "BDT")} />
        <Mini label="Cost Basis" value={formatCurrency(summary?.active_cost_basis ?? 0, "BDT")} />
        <Mini label="Dividend" value={formatCurrency(summary?.dividend_income ?? 0, "BDT")} />
        <Mini label="Return" value={`${asNumber(summary?.return_percent).toFixed(1)}%`} danger={asNumber(summary?.return_percent) < 0} />
      </div>
    </Panel>
  );
}

function BrokerAccountsPanel({ summary, accounts }: { summary?: PortfolioSummaryV2; accounts: Account[] }) {
  const brokerAccounts = summary?.broker_accounts.length ? summary.broker_accounts : accounts;

  return (
    <Panel title="Broker Accounts">
      {!brokerAccounts.length ? (
        <p className="text-sm text-muted">Create an account with subtype stock_broker, then transfer funds into it.</p>
      ) : (
        brokerAccounts.map((account) => (
          <div key={account.id} className="flex min-w-0 items-center justify-between gap-3 rounded-md bg-surface p-2 text-sm">
            <span className="min-w-0 truncate font-medium text-ink">{account.name}</span>
            <span className="shrink-0">{formatCurrency(account.balance, account.currency)}</span>
          </div>
        ))
      )}
    </Panel>
  );
}

function HoldingsSection({ summary, loading, advanced }: { summary?: PortfolioSummaryV2; loading: boolean; advanced: boolean }) {
  const totalPortfolio = asNumber(summary?.total_portfolio_value);
  const cashPercent = percentOf(summary?.cash_balance, summary?.total_portfolio_value);
  const equityPercent = percentOf(summary?.current_equity_value, summary?.total_portfolio_value);
  const sortedHoldings = [...(summary?.holdings ?? [])].sort(
    (first, second) => asNumber(second.market_value) - asNumber(first.market_value),
  );

  return (
    <section className="min-w-0 space-y-3">
      <div className="rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
        <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h2 className="text-sm font-semibold text-ink">Holdings Allocation</h2>
            <p className="text-xs text-muted">Cash and stock weight inside your portfolio.</p>
          </div>
          <span className="inline-flex w-fit items-center gap-1 rounded-md bg-surface px-2 py-1 text-xs font-semibold text-muted">
            <ChartPie className="h-3.5 w-3.5" />
            {summary?.holdings.length ?? 0} stocks
          </span>
        </div>

        {loading ? (
          <p className="text-sm text-muted">Loading holdings...</p>
        ) : totalPortfolio <= 0 ? (
          <p className="text-sm text-muted">No portfolio allocation yet.</p>
        ) : (
          <>
            <div className="grid gap-2 sm:grid-cols-3">
              <AllocationMetric label="Portfolio" value={formatCurrency(summary?.total_portfolio_value ?? 0, "BDT")} icon={Gauge} />
              <AllocationMetric label="Stock holdings" value={displayPercent(equityPercent)} subValue={formatCurrency(summary?.current_equity_value ?? 0, "BDT")} />
              <AllocationMetric label="Cash" value={displayPercent(cashPercent)} subValue={formatCurrency(summary?.cash_balance ?? 0, "BDT")} tone="cash" />
            </div>

            <div className="mt-4 h-3 overflow-hidden rounded-full bg-slate-100">
              <div className="flex h-full">
                <div className="bg-brand-600" style={{ width: barWidth(equityPercent) }} />
                <div className="bg-amber-500" style={{ width: barWidth(cashPercent) }} />
              </div>
            </div>
            <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
              <span className="inline-flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-full bg-brand-600" />
                Stocks {displayPercent(equityPercent)}
              </span>
              <span className="inline-flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-full bg-amber-500" />
                Cash {displayPercent(cashPercent)}
              </span>
            </div>
          </>
        )}
      </div>

      {loading ? (
        null
      ) : !sortedHoldings.length ? (
        <div className="rounded-md border border-dashed border-line bg-white px-4 py-8 text-center text-sm text-muted">No holdings yet.</div>
      ) : (
        <div className="grid min-w-0 gap-3 xl:grid-cols-2">
          {sortedHoldings.map((holding) => {
            const holdingPercent = percentOf(holding.market_value, summary?.total_portfolio_value);
            const gainPercent = asNumber(holding.unrealized_percent);
            const loss = asNumber(holding.unrealized_profit_loss) < 0;

            return (
            <article key={holding.stock.id} className="min-w-0 rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
              <div className="flex min-w-0 items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex min-w-0 items-center gap-2">
                    <p className="truncate text-sm font-semibold text-ink">{holding.stock.name}</p>
                    <span className="shrink-0 rounded bg-surface px-1.5 py-0.5 text-[11px] font-semibold text-muted">{holding.stock.symbol}</span>
                  </div>
                  <p className="mt-1 text-xs text-muted">
                    {holding.quantity} shares · Broker cost {formatCurrency(holding.broker_cost_basis ?? holding.avg_buy_price, holding.stock.currency)}
                  </p>
                </div>
                <div className="shrink-0 text-right">
                  <p className="text-sm font-semibold text-ink">{formatCurrency(holding.market_value, holding.stock.currency)}</p>
                  <p className="text-xs font-semibold text-brand-700">{displayPercent(holdingPercent)}</p>
                </div>
              </div>

              <div className="mt-3 h-2 rounded-full bg-slate-100">
                <div className="h-2 rounded-full bg-brand-600" style={{ width: barWidth(holdingPercent) }} />
              </div>

              <div className="mt-3 grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
                <Mini label="Market Price" value={formatCurrency(holding.market_price ?? 0, holding.stock.currency)} />
                <Mini label="Unrealized" value={formatCurrency(holding.unrealized_profit_loss, holding.stock.currency)} danger={loss} />
                <Mini label="Gain %" value={displayPercent(gainPercent)} danger={loss} />
                <Mini label="Realized" value={formatCurrency(holding.realized_profit_loss, holding.stock.currency)} danger={asNumber(holding.realized_profit_loss) < 0} />
                <Mini label="Dividend" value={formatCurrency(holding.dividend_income, holding.stock.currency)} />
                <Mini label="Total Return" value={formatCurrency(holding.total_return ?? holding.total_profit_loss, holding.stock.currency)} danger={asNumber(holding.total_return ?? holding.total_profit_loss) < 0} />
              </div>

              {advanced ? (
                <div className="mt-3 grid grid-cols-2 gap-2 rounded-md bg-indigo-50/60 p-2 text-xs sm:grid-cols-4">
                  <Mini label="Effective Cost" value={formatCurrency(holding.effective_cost_basis ?? 0, holding.stock.currency)} />
                  <Mini label="Net Capital" value={formatCurrency(holding.net_capital_invested ?? 0, holding.stock.currency)} />
                  <Mini label="Capital Recovery" value={displayPercent(asNumber(holding.capital_recovery_percent))} />
                  <Mini label="Wealth Multiple" value={formatMultiple(holding.wealth_multiple)} />
                </div>
              ) : null}
            </article>
          )})}
        </div>
      )}
    </section>
  );
}

function AllocationMetric({
  label,
  value,
  subValue,
  icon: Icon,
  tone = "stock",
}: {
  label: string;
  value: string;
  subValue?: string;
  icon?: any;
  tone?: "stock" | "cash";
}) {
  return (
    <div className={cn("rounded-md p-3", tone === "cash" ? "bg-amber-50" : "bg-surface")}>
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs font-medium text-muted">{label}</p>
        {Icon ? <Icon className="h-4 w-4 text-brand-600" /> : null}
      </div>
      <p className="mt-1 text-base font-semibold text-ink">{value}</p>
      {subValue ? <p className="mt-0.5 truncate text-xs text-muted">{subValue}</p> : null}
    </div>
  );
}

function DividendReportPanel({ summary }: { summary?: PortfolioSummaryV2 }) {
  const rows = [...(summary?.dividend_report ?? [])].sort((a, b) => b.year - a.year || a.stock_name.localeCompare(b.stock_name));
  return (
    <Panel title="Dividend Report">
      {!rows.length ? (
        <p className="text-sm text-muted">No dividends recorded.</p>
      ) : (
        rows.map((row, index) => (
          <div key={`${row.stock_id}-${row.year}-${row.source ?? "manual"}-${index}`} className="rounded-md bg-surface p-2 text-sm">
            <div className="flex min-w-0 items-center justify-between gap-3">
              <span className="min-w-0 truncate font-semibold text-ink">
                {row.stock_name} - {row.year}
              </span>
              <span className="shrink-0 font-semibold">{formatCurrency(row.dividend_gain, "BDT")}</span>
            </div>
            <p className="mt-1 text-xs text-muted">
              {(row.source ?? "manual").toUpperCase()}
              {row.record_date ? ` · Record ${row.record_date}` : ""}
              {row.eligible_quantity ? ` · ${asNumber(row.eligible_quantity).toFixed(4)} shares` : ""}
              {row.cash_dividend_percent ? ` · ${asNumber(row.cash_dividend_percent).toFixed(2)}% cash` : ""}
            </p>
          </div>
        ))
      )}
    </Panel>
  );
}

function TransactionsSection({
  transactions,
  loading,
  portfolioNameById,
  onEdit,
  onDelete,
}: {
  transactions: PortfolioTransaction[];
  loading: boolean;
  portfolioNameById: Map<string, string>;
  onEdit: (transaction: PortfolioTransaction) => void;
  onDelete: (transaction: PortfolioTransaction) => void;
}) {
  return (
    <section className="rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
      <h2 className="mb-3 text-sm font-semibold text-ink">Transaction List</h2>
      {loading ? (
        <p className="text-sm text-muted">Loading transactions...</p>
      ) : !transactions.length ? (
        <p className="text-sm text-muted">No stock transactions yet.</p>
      ) : (
        <div className="space-y-2">
          {transactions.map((transaction) => {
            const positive = asNumber(transaction.cash_flow) >= 0;
            return (
              <article key={transaction.id} className="rounded-md border border-line bg-white p-3">
                <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div className="flex min-w-0 items-center gap-3">
                    <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-md", positive ? "bg-emerald-50 text-emerald-700" : "bg-rose-50 text-rose-700")}>
                      {positive ? <ArrowDownLeft className="h-4 w-4" /> : <ArrowUpRight className="h-4 w-4" />}
                    </span>
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold capitalize text-ink">
                        {transaction.txn_type} {transaction.stock?.name ?? ""}
                      </p>
                      <p className="text-xs text-muted">{transaction.txn_date} - {transaction.notes || "No note"}</p>
                      <span className="mt-1 inline-flex items-center rounded bg-brand-50 px-1.5 py-0.5 text-[10px] font-semibold text-brand-700">
                        {(transaction.portfolio_id && portfolioNameById.get(transaction.portfolio_id)) || "Unassigned"}
                      </span>
                    </div>
                  </div>
                  <p className={cn("max-w-full truncate text-sm font-semibold sm:shrink-0 sm:text-right", positive ? "text-emerald-700" : "text-rose-700")}>
                    {positive ? "+" : "-"}{formatCurrency(Math.abs(asNumber(transaction.cash_flow)), transaction.stock?.currency || "BDT")}
                  </p>
                </div>
                <div className="mt-3 flex justify-end gap-2">
                  <button
                    type="button"
                    onClick={() => onEdit(transaction)}
                    className="inline-flex h-8 items-center gap-1 rounded-md border border-line bg-white px-2 text-xs font-semibold text-muted hover:text-brand-700"
                  >
                    <Pencil className="h-3.5 w-3.5" />
                    Edit
                  </button>
                  <button
                    type="button"
                    onClick={() => onDelete(transaction)}
                    className="inline-flex h-8 items-center gap-1 rounded-md border border-red-200 bg-red-50 px-2 text-xs font-semibold text-red-700 hover:bg-red-100"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                    Delete
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}

function Metric({ label, value, icon: Icon, warn = false }: { label: string; value?: string; icon: any; warn?: boolean }) {
  return (
    <div className="rounded-md border border-line bg-white p-3 shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs font-medium text-muted">{label}</p>
        <Icon className={cn("h-4 w-4", warn ? "text-rose-600" : "text-brand-600")} />
      </div>
      <p className={cn("mt-2 truncate text-sm font-semibold md:text-lg", warn ? "text-rose-700" : "text-ink")}>
        {formatCurrency(value ?? 0, "BDT")}
      </p>
    </div>
  );
}

function PercentMetric({ label, value }: { label: string; value?: string }) {
  const negative = asNumber(value) < 0;
  return (
    <div className="rounded-md border border-line bg-white p-3 shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs font-medium text-muted">{label}</p>
        <TrendingUp className={cn("h-4 w-4", negative ? "text-rose-600" : "text-brand-600")} />
      </div>
      <p className={cn("mt-2 truncate text-sm font-semibold md:text-lg", negative ? "text-rose-700" : "text-ink")}>
        {signedPercent(value)}
      </p>
    </div>
  );
}

function Mini({ label, value, danger = false }: { label: string; value: string; danger?: boolean }) {
  return (
    <div>
      <p className="text-muted">{label}</p>
      <p className={cn("truncate font-semibold", danger ? "text-rose-700" : "text-ink")}>{value}</p>
    </div>
  );
}

function MarketPriceSection({
  stocks,
  loading,
  onSaved,
}: {
  stocks: Stock[];
  loading: boolean;
  onSaved: () => Promise<void>;
}) {
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function refreshPrices() {
    setRefreshing(true);
    setError(null);
    setNotice(null);
    try {
      const result = await refreshStockPrices();
      await onSaved();
      const missing = result.missing_symbols.length ? ` Missing: ${result.missing_symbols.join(", ")}.` : "";
      setNotice(`Updated ${result.updated} prices from ${result.source}.${missing}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Market price refresh failed");
    } finally {
      setRefreshing(false);
    }
  }

  return (
    <section className="rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
      <div className="mb-3 flex items-center justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-ink">Current Market Price</h2>
          <p className="text-xs text-muted">Fetch latest DSE LTP to refresh equity value and P/L.</p>
        </div>
        <Button type="button" variant="secondary" onClick={refreshPrices} disabled={refreshing || stocks.length === 0}>
          <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
          {refreshing ? "Fetching" : "Fetch DSE"}
        </Button>
      </div>
      {error ? <p className="mb-2 rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">{error}</p> : null}
      {notice ? <p className="mb-2 rounded-md bg-emerald-50 px-3 py-2 text-xs text-emerald-700">{notice}</p> : null}
      {loading ? (
        <p className="text-sm text-muted">Loading stocks...</p>
      ) : stocks.length === 0 ? (
        <p className="text-sm text-muted">No stock master data yet.</p>
      ) : (
        <div className="grid min-w-0 gap-2 md:grid-cols-2 xl:grid-cols-3">
          {stocks.map((stock) => (
            <article key={stock.id} className="rounded-md bg-surface p-2.5">
              <div className="mb-2 flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-ink">{stock.name}</p>
                  <p className="text-xs text-muted">{stock.symbol}</p>
                </div>
                <p className="shrink-0 text-xs font-semibold text-muted">
                  {formatCurrency(stock.last_price, stock.currency)}
                </p>
              </div>
              <p className="text-xs text-muted">Exchange: {stock.exchange || "DSE"} · Currency: {stock.currency}</p>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
      <h2 className="mb-3 text-sm font-semibold text-ink">{title}</h2>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

function PortfolioControls({
  portfolios,
  selectedPortfolioId,
  onSelect,
  advanced,
  onToggleAdvanced,
}: {
  portfolios: Portfolio[];
  selectedPortfolioId: string;
  onSelect: (id: string) => void;
  advanced: boolean;
  onToggleAdvanced: () => void;
}) {
  return (
    <div className="mt-2 flex flex-col gap-1 md:mt-3">
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={selectedPortfolioId}
          onChange={(event) => onSelect(event.target.value)}
          className="input h-9 max-w-[18rem] flex-1"
          aria-label="Select portfolio"
        >
          <option value="">All Portfolios</option>
          {portfolios.map((portfolio) => (
            <option key={portfolio.id} value={portfolio.id}>
              {portfolio.name} · {KIND_LABELS[portfolio.kind]}
            </option>
          ))}
        </select>
        <button
          type="button"
          onClick={onToggleAdvanced}
          className={cn(
            "inline-flex h-9 items-center gap-1 rounded-md border px-2 text-xs font-semibold transition",
            advanced ? "border-brand-600 bg-brand-600 text-white" : "border-line bg-white text-muted hover:text-brand-700",
          )}
          aria-pressed={advanced}
        >
          <Sparkles className="h-3.5 w-3.5" />
          Advanced
        </button>
      </div>
      <p className="text-[11px] text-muted">Each broker account is a portfolio — a trade joins the portfolio of its broker account.</p>
    </div>
  );
}

function AdvancedInvestorPanel({ summary }: { summary?: PortfolioSummaryV2 }) {
  return (
    <section className="rounded-md border border-indigo-200 bg-indigo-50/60 p-3 shadow-sm md:p-4">
      <div className="mb-3 flex items-center gap-2">
        <Sparkles className="h-4 w-4 text-indigo-600" />
        <h2 className="text-sm font-semibold text-ink">Advanced Investor Analytics</h2>
      </div>
      <div className="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
        <Mini label="Net Capital Invested" value={formatCurrency(summary?.net_capital_invested ?? 0, "BDT")} />
        <Mini label="Capital Recovery" value={displayPercent(asNumber(summary?.capital_recovery_percent))} />
        <Mini label="Wealth Multiple" value={formatMultiple(summary?.wealth_multiple)} />
        <Mini label="Withdrawals" value={formatCurrency(summary?.total_withdrawals ?? 0, "BDT")} />
      </div>
    </section>
  );
}

function PerformanceSection({
  series,
  annual,
  analytics,
  advanced,
  loading,
}: {
  series?: PerformanceSeriesResponse;
  annual?: AnnualPerformanceResponse;
  analytics?: PortfolioAnalyticsResponse;
  advanced: boolean;
  loading: boolean;
}) {
  const growth = (series?.growth ?? []).map((point) => ({
    period: point.period,
    value: asNumber(point.portfolio_value),
    return: asNumber(point.cumulative_return),
  }));
  const composition = (series?.return_composition ?? [])
    .map((row) => ({ label: row.label, value: asNumber(row.value) }))
    .filter((row) => row.value !== 0);
  const annualReturn = (series?.annual_return ?? []).map((row) => ({
    year: String(row.year),
    percent: asNumber(row.annual_return_percent),
  }));
  const annualRows = [...(annual?.rows ?? [])].sort((a, b) => b.year - a.year);

  if (loading) {
    return <p className="text-sm text-muted">Loading performance analytics...</p>;
  }

  return (
    <section className="min-w-0 space-y-3">
      <div className="grid gap-3 lg:grid-cols-2">
        <ChartCard title="Portfolio Growth" icon={TrendingUp}>
          {growth.length ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={growth} margin={{ left: 4, right: 8, top: 8, bottom: 4 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#eef2f7" />
                <XAxis dataKey="period" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} width={56} tickFormatter={(v) => compactNumber(v)} />
                <Tooltip formatter={(value) => formatCurrency(Number(value ?? 0), "BDT")} />
                <Line type="monotone" dataKey="value" stroke="#6366f1" strokeWidth={2} dot={false} name="Portfolio Value" />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <EmptyChart />
          )}
        </ChartCard>

        <ChartCard title="Total Return Growth" icon={LineChartIcon}>
          {growth.length ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={growth} margin={{ left: 4, right: 8, top: 8, bottom: 4 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#eef2f7" />
                <XAxis dataKey="period" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} width={56} tickFormatter={(v) => compactNumber(v)} />
                <Tooltip formatter={(value) => formatCurrency(Number(value ?? 0), "BDT")} />
                <Line type="monotone" dataKey="return" stroke="#22c55e" strokeWidth={2} dot={false} name="Cumulative Return" />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <EmptyChart />
          )}
        </ChartCard>

        <ChartCard title="Return Composition" icon={ChartPie}>
          {composition.length ? (
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie data={composition} dataKey="value" nameKey="label" innerRadius={55} outerRadius={90}>
                  {composition.map((_, index) => (
                    <Cell key={index} fill={CHART_COLORS[index % CHART_COLORS.length]} />
                  ))}
                </Pie>
                <Legend />
                <Tooltip formatter={(value) => formatCurrency(Number(value ?? 0), "BDT")} />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <EmptyChart />
          )}
        </ChartCard>

        <ChartCard title="Annual Return %" icon={LineChartIcon}>
          {annualReturn.length ? (
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={annualReturn} margin={{ left: 4, right: 8, top: 8, bottom: 4 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#eef2f7" />
                <XAxis dataKey="year" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} width={44} tickFormatter={(v) => `${v}%`} />
                <Tooltip formatter={(value) => `${Number(value ?? 0).toFixed(2)}%`} />
                <Bar dataKey="percent" radius={[4, 4, 0, 0]}>
                  {annualReturn.map((row, index) => (
                    <Cell key={index} fill={row.percent >= 0 ? "#22c55e" : "#ef4444"} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <EmptyChart />
          )}
        </ChartCard>
      </div>

      <AnnualPerformanceTable rows={annualRows} />

      {advanced ? <AdvancedAnalyticsPanel analytics={analytics} /> : null}
    </section>
  );
}

function ChartCard({ title, icon: Icon, children }: { title: string; icon: any; children: React.ReactNode }) {
  return (
    <div className="min-w-0 rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
      <div className="mb-2 flex items-center gap-2">
        <Icon className="h-4 w-4 text-brand-600" />
        <h3 className="text-sm font-semibold text-ink">{title}</h3>
      </div>
      {children}
    </div>
  );
}

function EmptyChart() {
  return <p className="py-10 text-center text-sm text-muted">Not enough data yet.</p>;
}

function compactNumber(value: number) {
  const abs = Math.abs(value);
  if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
  return String(Math.round(value));
}

function AnnualPerformanceTable({ rows }: { rows: AnnualPerformanceResponse["rows"] }) {
  return (
    <div className="min-w-0 rounded-md border border-line bg-white p-3 shadow-sm md:p-4">
      <h3 className="mb-3 text-sm font-semibold text-ink">Annual Performance Report</h3>
      {!rows.length ? (
        <p className="text-sm text-muted">No yearly activity yet.</p>
      ) : (
        <div className="-mx-1 overflow-x-auto">
          <table className="w-full min-w-[640px] border-collapse text-xs">
            <thead>
              <tr className="text-left text-muted">
                <th className="px-2 py-1.5 font-medium">Year</th>
                <th className="px-2 py-1.5 text-right font-medium">Beginning</th>
                <th className="px-2 py-1.5 text-right font-medium">New Invest</th>
                <th className="px-2 py-1.5 text-right font-medium">Realized</th>
                <th className="px-2 py-1.5 text-right font-medium">Dividend</th>
                <th className="px-2 py-1.5 text-right font-medium">Unrealized</th>
                <th className="px-2 py-1.5 text-right font-medium">Ending</th>
                <th className="px-2 py-1.5 text-right font-medium">Total Return</th>
                <th className="px-2 py-1.5 text-right font-medium">Return %</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => {
                const negative = asNumber(row.total_return) < 0;
                return (
                  <tr key={row.year} className="border-t border-line">
                    <td className="px-2 py-1.5 font-semibold text-ink">{row.year}</td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(row.beginning_value, "BDT")}</td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(row.new_investment, "BDT")}</td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(row.realized_gain, "BDT")}</td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(row.dividend_income, "BDT")}</td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(row.unrealized_gain, "BDT")}</td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(row.ending_value, "BDT")}</td>
                    <td className={cn("px-2 py-1.5 text-right font-semibold", negative ? "text-rose-700" : "text-emerald-700")}>
                      {formatCurrency(row.total_return, "BDT")}
                    </td>
                    <td className={cn("px-2 py-1.5 text-right font-semibold", negative ? "text-rose-700" : "text-emerald-700")}>
                      {signedPercent(row.annual_return_percent)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function AdvancedAnalyticsPanel({ analytics }: { analytics?: PortfolioAnalyticsResponse }) {
  const xirr = analytics?.portfolio_xirr_percent;
  return (
    <section className="space-y-3 rounded-md border border-indigo-200 bg-indigo-50/60 p-3 shadow-sm md:p-4">
      <div className="flex items-center gap-2">
        <Sparkles className="h-4 w-4 text-indigo-600" />
        <h3 className="text-sm font-semibold text-ink">Advanced Investor Analytics</h3>
      </div>
      <div className="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
        <Mini label="Portfolio XIRR" value={xirr == null ? "—" : signedPercent(xirr)} />
        <Mini label="CAGR" value={analytics ? signedPercent(analytics.cagr_percent) : "—"} />
        <Mini label="Win Rate" value={analytics ? displayPercent(asNumber(analytics.win_rate_percent)) : "—"} />
        <Mini
          label="Profit Factor"
          value={analytics?.profit_factor == null ? "—" : asNumber(analytics.profit_factor).toFixed(2)}
        />
        <Mini label="Avg Gain" value={analytics ? signedPercent(analytics.average_gain_percent) : "—"} />
        <Mini label="Avg Loss" value={analytics ? signedPercent(analytics.average_loss_percent) : "—"} />
        <Mini
          label="Avg Holding"
          value={analytics ? `${Math.round(asNumber(analytics.average_holding_period_days))} d` : "—"}
        />
        <Mini label="Turnover" value={analytics ? formatMultiple(analytics.portfolio_turnover_ratio) : "—"} />
        <Mini
          label="Best Trade"
          value={analytics?.best_trade ? `${analytics.best_trade.symbol} ${formatCurrency(analytics.best_trade.profit, "BDT")}` : "—"}
        />
        <Mini
          label="Worst Trade"
          value={analytics?.worst_trade ? `${analytics.worst_trade.symbol} ${formatCurrency(analytics.worst_trade.profit, "BDT")}` : "—"}
          danger={asNumber(analytics?.worst_trade?.profit) < 0}
        />
        <Mini label="Trades" value={analytics ? String(analytics.total_trades) : "—"} />
        <Mini
          label="Win / Loss"
          value={analytics ? `${analytics.winning_trades} / ${analytics.losing_trades}` : "—"}
        />
      </div>

      {analytics?.stock_xirr?.length ? (
        <div className="-mx-1 overflow-x-auto">
          <table className="w-full min-w-[360px] border-collapse text-xs">
            <thead>
              <tr className="text-left text-muted">
                <th className="px-2 py-1.5 font-medium">Stock</th>
                <th className="px-2 py-1.5 text-right font-medium">Stock-wise XIRR</th>
              </tr>
            </thead>
            <tbody>
              {analytics.stock_xirr.map((row) => (
                <tr key={row.stock_id} className="border-t border-indigo-100">
                  <td className="px-2 py-1.5 font-semibold text-ink">{row.symbol}</td>
                  <td className="px-2 py-1.5 text-right">{row.xirr_percent == null ? "—" : signedPercent(row.xirr_percent)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </section>
  );
}
