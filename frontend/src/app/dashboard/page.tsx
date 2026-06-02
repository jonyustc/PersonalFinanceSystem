"use client";

import { AlertCircle, Banknote, CalendarDays, CreditCard, Landmark, ReceiptText, RefreshCw, Wallet, X } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import type { MouseEvent } from "react";

import { Button } from "@/components/ui/button";
import { cn, formatCurrency } from "@/lib/utils";
import { fetchAccounts, fetchSimpleDashboard, fetchTransactions } from "@/services/finance-service";
import type { Account, SimpleDashboardResponse, Transaction } from "@/types/api";

function getCurrentMonth() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function accountTypeLabel(type: string) {
  return type
    .toLowerCase()
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function toNumber(value: number | string | null | undefined) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

function monthRange(month: string) {
  const [year, monthIndex] = month.split("-").map(Number);
  const firstDay = new Date(year, monthIndex - 1, 1);
  const lastDay = new Date(year, monthIndex, 0);
  const format = (date: Date) =>
    `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  return { from: format(firstDay), to: format(lastDay) };
}

function normalizedType(type?: string | null) {
  return type?.toLowerCase() ?? "";
}

function isCreditCardAccount(account?: Account) {
  const type = normalizedType(account?.type);
  return type === "credit_card" || type === "card";
}

function isCardAccount(account?: Account) {
  const type = normalizedType(account?.type);
  return type === "credit_card" || type === "debit_card" || type === "card";
}

function transactionKind(transaction: Transaction) {
  return transaction.transaction_type ?? transaction.type ?? transaction.txn_type;
}

type HistoryView = {
  title: string;
  subtitle: string;
  empty: string;
  filter: (transaction: Transaction) => boolean;
};

export default function DashboardPage() {
  const [month, setMonth] = useState(getCurrentMonth());
  const [data, setData] = useState<SimpleDashboardResponse | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [monthTransactions, setMonthTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [historyLoading, setHistoryLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [historyView, setHistoryView] = useState<HistoryView | null>(null);

  async function loadDashboard(selectedMonth = month) {
    setLoading(true);
    setError(null);
    try {
      setData(await fetchSimpleDashboard(selectedMonth));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load dashboard");
    } finally {
      setLoading(false);
    }
  }

  async function loadHistoryData(selectedMonth = month) {
    setHistoryLoading(true);
    setHistoryError(null);
    try {
      const range = monthRange(selectedMonth);
      const [accountData, transactionData] = await Promise.all([
        fetchAccounts(),
        fetchTransactions({ from_date: range.from, to_date: range.to, limit: 1000 }),
      ]);
      setAccounts(accountData);
      setMonthTransactions(transactionData.items);
    } catch (err) {
      setHistoryError(err instanceof Error ? err.message : "Failed to load transaction history");
    } finally {
      setHistoryLoading(false);
    }
  }

  useEffect(() => {
    loadDashboard(month);
    loadHistoryData(month);
    setHistoryView(null);
  }, [month]);

  useEffect(() => {
    function refreshDashboard() {
      loadDashboard(month);
      loadHistoryData(month);
    }

    window.addEventListener("finance:data-mutated", refreshDashboard);
    return () => window.removeEventListener("finance:data-mutated", refreshDashboard);
  }, [month]);

  const accountMap = useMemo(() => new Map(accounts.map((account) => [account.id, account])), [accounts]);
  const accountMapRef = useRef(accountMap);
  accountMapRef.current = accountMap;

  function showAccountHistory(account: { id: string; name: string; type: string }) {
    setHistoryView({
      title: `${account.name} History`,
      subtitle: `${month} transactions touching this ${accountTypeLabel(account.type).toLowerCase()} account`,
      empty: "No transactions found for this account this month.",
      filter: (transaction) =>
        transaction.account_id === account.id || transaction.transfer_account_id === account.id,
    });
  }

  function showCreditCardHistory(card: { id: string; name: string }) {
    setHistoryView({
      title: `${card.name} Activity`,
      subtitle: `${month} spending and payment activity for this card`,
      empty: "No transactions found for this credit card this month.",
      filter: (transaction) =>
        transaction.account_id === card.id || transaction.transfer_account_id === card.id,
    });
  }

  function showCreditCardSpending(card: { id: string; name: string }) {
    setHistoryView({
      title: `${card.name} Spending`,
      subtitle: `${month} expense transactions from this credit card`,
      empty: "No spending found for this credit card this month.",
      filter: (transaction) => transaction.type === "expense" && transaction.account_id === card.id,
    });
  }

  function showCreditCardPayments(card: { id: string; name: string }) {
    setHistoryView({
      title: `${card.name} Payments`,
      subtitle: `${month} payments made toward this credit card`,
      empty: "No payments found for this credit card this month.",
      filter: (transaction) =>
        transaction.transfer_account_id === card.id &&
        (transactionKind(transaction) === "CARD_PAYMENT" || transaction.type === "transfer"),
    });
  }

  const topCards = useMemo(
    () => [
      {
        label: "Active Balance",
        value: data?.active_accounts_balance.total_balance,
        icon: Wallet,
        tone: "text-emerald-700 bg-emerald-50",
        view: () => {
          const accountIds = new Set(data?.active_accounts_balance.accounts.map((account) => account.id) ?? []);
          return {
            title: "Active Balance History",
            subtitle: `${month} transactions touching active cash, bank, or mobile accounts`,
            empty: "No active account transactions found for this month.",
            filter: (transaction: Transaction) =>
              accountIds.has(transaction.account_id) ||
              Boolean(transaction.transfer_account_id && accountIds.has(transaction.transfer_account_id)),
          };
        },
      },
      {
        label: "Card Spending",
        value: data?.card_summary.total_card_spending,
        icon: CreditCard,
        tone: "text-blue-700 bg-blue-50",
        view: () => ({
          title: "Card Spending History",
          subtitle: `${month} expense transactions from credit or debit cards`,
          empty: "No card spending found for this month.",
          filter: (transaction: Transaction) =>
            transaction.type === "expense" && isCardAccount(accountMapRef.current.get(transaction.account_id)),
        }),
      },
      {
        label: "Card Payment",
        value: data?.card_summary.total_card_payment,
        icon: Banknote,
        tone: "text-teal-700 bg-teal-50",
        view: () => ({
          title: "Card Payment History",
          subtitle: `${month} payments made toward credit cards`,
          empty: "No card payments found for this month.",
          filter: (transaction: Transaction) =>
            transactionKind(transaction) === "CARD_PAYMENT" ||
            Boolean(transaction.transfer_account_id && isCreditCardAccount(accountMapRef.current.get(transaction.transfer_account_id))),
        }),
      },
      {
        label: "Card Outstanding",
        value: data?.card_summary.total_card_outstanding,
        icon: AlertCircle,
        tone: "text-amber-700 bg-amber-50",
        view: () => ({
          title: "Card Outstanding Activity",
          subtitle: `${month} credit-card spending and payment activity`,
          empty: "No credit card activity found for this month.",
          filter: (transaction: Transaction) =>
            (transaction.type === "expense" && isCreditCardAccount(accountMapRef.current.get(transaction.account_id))) ||
            transactionKind(transaction) === "CARD_PAYMENT" ||
            Boolean(transaction.transfer_account_id && isCreditCardAccount(accountMapRef.current.get(transaction.transfer_account_id))),
        }),
      },
    ],
    [data, month, accounts],
  );

  const activeHistoryItems = useMemo(
    () => (historyView ? monthTransactions.filter(historyView.filter) : []),
    [historyView, monthTransactions, accountMap],
  );
  const historyTotal = useMemo(
    () => activeHistoryItems.reduce((sum, transaction) => sum + toNumber(transaction.amount), 0),
    [activeHistoryItems],
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Dashboard</h1>
          <p className="text-sm text-muted">Active cash flow and card exposure for the selected month.</p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <label className="flex h-10 items-center gap-2 rounded-md border border-line bg-white px-3 text-sm text-muted">
            <CalendarDays className="h-4 w-4" />
            <input
              aria-label="Select month"
              className="bg-transparent text-ink outline-none"
              type="month"
              value={month}
              onChange={(event) => setMonth(event.target.value)}
            />
          </label>
          <Button variant="secondary" onClick={() => loadDashboard()} disabled={loading}>
            <RefreshCw className={cn("h-4 w-4", loading && "animate-spin")} />
            Refresh
          </Button>
        </div>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      {loading ? (
        <DashboardSkeleton />
      ) : data ? (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {topCards.map((card) => {
              const Icon = card.icon;
              return (
                <button
                  key={card.label}
                  type="button"
                  onClick={() => setHistoryView(card.view())}
                  className="rounded-md border border-line bg-white p-4 text-left shadow-soft transition hover:border-brand-200 hover:shadow-md focus:outline-none focus:ring-4 focus:ring-brand-100"
                >
                  <div className="flex items-center justify-between gap-3">
                    <p className="text-sm font-medium text-muted">{card.label}</p>
                    <span className={cn("flex h-9 w-9 items-center justify-center rounded-md", card.tone)}>
                      <Icon className="h-4 w-4" />
                    </span>
                  </div>
                  <p className="mt-4 text-2xl font-semibold text-ink">{formatCurrency(card.value ?? 0, "BDT")}</p>
                  <p className="mt-2 text-xs font-medium text-brand-700">View history</p>
                </button>
              );
            })}
          </div>

          <section className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-semibold text-ink">Active Accounts Balance</h2>
              <span className="text-sm text-muted">
                {data.active_accounts_balance.accounts.length} active accounts
              </span>
            </div>

            {data.active_accounts_balance.accounts.length === 0 ? (
              <EmptyState message="No active cash, bank, or mobile banking accounts found." />
            ) : (
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                {data.active_accounts_balance.accounts.map((account) => (
                  <button
                    key={account.id}
                    type="button"
                    onClick={() => showAccountHistory(account)}
                    className="rounded-md border border-line bg-white p-4 text-left shadow-soft transition hover:border-brand-200 hover:shadow-md focus:outline-none focus:ring-4 focus:ring-brand-100"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <h3 className="truncate font-semibold text-ink">{account.name}</h3>
                        <p className="mt-1 text-sm text-muted">{accountTypeLabel(account.type)}</p>
                      </div>
                      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-slate-100 text-slate-700">
                        {account.type === "BANK" ? <Landmark className="h-4 w-4" /> : <Wallet className="h-4 w-4" />}
                      </span>
                    </div>
                    <p className="mt-5 text-xl font-semibold text-ink">
                      {formatCurrency(account.balance, account.currency || "BDT")}
                    </p>
                    <p className="mt-2 text-xs font-medium text-brand-700">View account history</p>
                  </button>
                ))}
              </div>
            )}
          </section>

          <section className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-semibold text-ink">Credit Card Limit vs Spending</h2>
              <span className="text-sm text-muted">{data.card_summary.cards.length} cards</span>
            </div>

            {data.card_summary.cards.length === 0 ? (
              <EmptyState message="No active credit cards found." />
            ) : (
              <div className="grid gap-4 xl:grid-cols-2">
                {data.card_summary.cards.map((card) => {
                  const used = toNumber(card.used_percentage);
                  const highUsage = used > 80;
                  const outstanding = toNumber(card.current_outstanding);
                  const highOutstanding = outstanding > toNumber(card.credit_limit) * 0.8 && toNumber(card.credit_limit) > 0;

                  return (
                    <article
                      key={card.id}
                      onClick={() => showCreditCardHistory(card)}
                      className={cn(
                        "cursor-pointer rounded-md border bg-white p-4 shadow-soft transition hover:border-brand-200 hover:shadow-md",
                        highUsage || highOutstanding ? "border-amber-300" : "border-line",
                      )}
                    >
                      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                        <div>
                          <h3 className="font-semibold text-ink">{card.name}</h3>
                          <p className="mt-1 text-sm text-muted">
                            Limit {formatCurrency(card.credit_limit, "BDT")}
                          </p>
                        </div>
                        <div className="text-left sm:text-right">
                          <p className={cn("text-lg font-semibold", highUsage ? "text-amber-700" : "text-ink")}>
                            {used.toFixed(1)}% used
                          </p>
                          <p className="text-sm text-muted">
                            Available {formatCurrency(card.available_limit, "BDT")}
                          </p>
                        </div>
                      </div>

                      <div className="mt-4 h-2.5 rounded-full bg-slate-100">
                        <div
                          className={cn("h-2.5 rounded-full", highUsage ? "bg-amber-500" : "bg-emerald-600")}
                          style={{ width: `${Math.min(used, 100)}%` }}
                        />
                      </div>

                      <div className="mt-4 grid gap-3 sm:grid-cols-3">
                        <Metric label="Outstanding" value={formatCurrency(card.current_outstanding, "BDT")} warn={highOutstanding} />
                        <Metric
                          label="Monthly spending"
                          value={formatCurrency(card.monthly_spending, "BDT")}
                          onClick={(event) => {
                            event.stopPropagation();
                            showCreditCardSpending(card);
                          }}
                        />
                        <Metric
                          label="Monthly payment"
                          value={formatCurrency(card.monthly_payment, "BDT")}
                          onClick={(event) => {
                            event.stopPropagation();
                            showCreditCardPayments(card);
                          }}
                        />
                      </div>

                      <div className="mt-4 flex flex-wrap gap-2 text-xs text-muted">
                        {card.billing_cycle_day ? <span>Billing day {card.billing_cycle_day}</span> : null}
                        {card.payment_due_day ? <span>Due day {card.payment_due_day}</span> : null}
                      </div>
                      <p className="mt-3 text-xs font-medium text-brand-700">View card activity</p>
                    </article>
                  );
                })}
              </div>
            )}
          </section>
        </>
      ) : (
        <EmptyState message="Dashboard data is unavailable." />
      )}

      <HistoryDrawer
        open={Boolean(historyView)}
        loading={historyLoading}
        error={historyError}
        title={historyView?.title ?? ""}
        subtitle={historyView?.subtitle ?? ""}
        empty={historyView?.empty ?? "No transactions found."}
        transactions={activeHistoryItems}
        accounts={accountMap}
        total={historyTotal}
        month={month}
        onClose={() => setHistoryView(null)}
      />
    </div>
  );
}

function Metric({
  label,
  value,
  warn = false,
  onClick,
}: {
  label: string;
  value: string;
  warn?: boolean;
  onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
}) {
  const className = cn(
    "rounded-md bg-surface p-3 text-left",
    warn && "bg-amber-50",
    onClick && "transition hover:bg-brand-50 focus:outline-none focus:ring-4 focus:ring-brand-100",
  );

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={className}>
        <p className="text-xs font-medium uppercase tracking-normal text-muted">{label}</p>
        <p className={cn("mt-1 text-sm font-semibold", warn ? "text-amber-800" : "text-ink")}>{value}</p>
        <p className="mt-1 text-xs font-medium normal-case text-brand-700">View history</p>
      </button>
    );
  }

  return (
    <div className={className}>
      <p className="text-xs font-medium uppercase tracking-normal text-muted">{label}</p>
      <p className={cn("mt-1 text-sm font-semibold", warn ? "text-amber-800" : "text-ink")}>{value}</p>
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="rounded-md border border-dashed border-line bg-white px-4 py-8 text-center text-sm text-muted">
      {message}
    </div>
  );
}

function HistoryDrawer({
  open,
  loading,
  error,
  title,
  subtitle,
  empty,
  transactions,
  accounts,
  total,
  month,
  onClose,
}: {
  open: boolean;
  loading: boolean;
  error: string | null;
  title: string;
  subtitle: string;
  empty: string;
  transactions: Transaction[];
  accounts: Map<string, Account>;
  total: number;
  month: string;
  onClose: () => void;
}) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-40 bg-slate-950/35 backdrop-blur-sm">
      <aside className="absolute bottom-0 right-0 top-0 flex w-full flex-col bg-white shadow-2xl ring-1 ring-slate-200 sm:max-w-xl">
        <div className="border-b border-line px-5 py-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-ink">{title}</p>
              <p className="mt-1 text-sm text-muted">{subtitle}</p>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="rounded-full p-2 text-slate-500 hover:bg-slate-100"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-3">
            <div className="rounded-md bg-surface p-3">
              <p className="text-xs font-medium uppercase tracking-normal text-muted">Total</p>
              <p className="mt-1 text-lg font-semibold text-ink">{formatCurrency(total, "BDT")}</p>
            </div>
            <div className="rounded-md bg-surface p-3">
              <p className="text-xs font-medium uppercase tracking-normal text-muted">Transactions</p>
              <p className="mt-1 text-lg font-semibold text-ink">{transactions.length}</p>
            </div>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {loading ? (
            <div className="space-y-3">
              {Array.from({ length: 6 }).map((_, index) => (
                <div key={index} className="h-20 animate-pulse rounded-md bg-slate-100" />
              ))}
            </div>
          ) : error ? (
            <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          ) : transactions.length === 0 ? (
            <div className="rounded-md border border-dashed border-line bg-surface px-4 py-8 text-center">
              <ReceiptText className="mx-auto h-8 w-8 text-muted" />
              <p className="mt-3 text-sm text-muted">{empty}</p>
            </div>
          ) : (
            <div className="space-y-3">
              {transactions.map((transaction) => (
                <HistoryTransactionRow
                  key={transaction.id}
                  transaction={transaction}
                  accounts={accounts}
                />
              ))}
            </div>
          )}
        </div>

        <div className="border-t border-line px-5 py-3 text-xs text-muted">
          Showing matching transactions for {month}.
        </div>
      </aside>
    </div>
  );
}

function HistoryTransactionRow({
  transaction,
  accounts,
}: {
  transaction: Transaction;
  accounts: Map<string, Account>;
}) {
  const fromAccount = accounts.get(transaction.account_id);
  const toAccount = transaction.transfer_account_id
    ? accounts.get(transaction.transfer_account_id)
    : undefined;
  const kind = transactionKind(transaction);
  const isExpense = transaction.type === "expense";
  const isIncome = transaction.type === "income";
  const date = new Date(transaction.txn_date);

  return (
    <article className="rounded-md border border-line bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={cn(
                "rounded-full px-2 py-0.5 text-xs font-semibold capitalize",
                kind === "CARD_PAYMENT"
                  ? "bg-teal-50 text-teal-700"
                  : isExpense
                    ? "bg-rose-50 text-rose-700"
                    : isIncome
                      ? "bg-emerald-50 text-emerald-700"
                      : "bg-blue-50 text-blue-700",
              )}
            >
              {kind === "CARD_PAYMENT" ? "Card payment" : transaction.type}
            </span>
            <span className="text-xs text-muted">
              {date.toLocaleDateString("en-US", { month: "short", day: "numeric" })}
            </span>
          </div>

          <h3 className="mt-2 truncate text-sm font-semibold text-ink">
            {transaction.description || transaction.merchant_name || "Transaction"}
          </h3>
          <p className="mt-1 text-xs text-muted">
            {fromAccount?.name ?? "Unknown account"}
            {toAccount ? ` -> ${toAccount.name}` : ""}
          </p>
        </div>

        <p
          className={cn(
            "shrink-0 text-sm font-semibold",
            isExpense ? "text-rose-700" : isIncome ? "text-emerald-700" : "text-ink",
          )}
        >
          {isExpense ? "-" : isIncome ? "+" : ""}
          {formatCurrency(transaction.amount, fromAccount?.currency || "BDT")}
        </p>
      </div>
    </article>
  );
}

function DashboardSkeleton() {
  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="h-32 animate-pulse rounded-md border border-line bg-slate-100" />
        ))}
      </div>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {Array.from({ length: 3 }).map((_, index) => (
          <div key={index} className="h-36 animate-pulse rounded-md border border-line bg-slate-100" />
        ))}
      </div>
      <div className="grid gap-4 xl:grid-cols-2">
        {Array.from({ length: 2 }).map((_, index) => (
          <div key={index} className="h-56 animate-pulse rounded-md border border-line bg-slate-100" />
        ))}
      </div>
    </div>
  );
}
