"use client";

// frontend/src/app/dashboard/funds/[accountId]/page.tsx
// Route: /dashboard/funds/[accountId]

import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
import {
  createTransaction,
  fetchAccounts,
  fetchCategories,
} from "@/services/finance-service";
import {
  fetchFundSummary,
  fetchFundTransactions,
  FUND_TAG_FRIEND,
  FUND_TAG_MINE,
  type FundSummary,
  type FundTransaction,
  type FundTransactions,
} from "@/services/fund-service";
import type { Account, Category } from "@/types/api";
import {
  ArrowDownLeft,
  HelpCircle,
  Plus,
  RefreshCw,
  TrendingDown,
  UserCheck,
  UserCircle2,
  Users,
  Wallet,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";

/* ─────────────────────────────────────────
   TYPES
───────────────────────────────────────── */
type Tab = "overview" | "mine" | "friend" | "untagged";

/* ─────────────────────────────────────────
   PAGE
───────────────────────────────────────── */
export default function FundTrackerPage() {
  const params = useParams();
  const accountId = params?.accountId as string;

  const [summary, setSummary] = useState<FundSummary | null>(null);
  const [breakdown, setBreakdown] = useState<FundTransactions | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [addModalOpen, setAddModalOpen] = useState(false);
  const [defaultMember, setDefaultMember] = useState<"mine" | "friend">("mine");

  const load = useCallback(async () => {
    if (!accountId) return;
    setLoading(true);
    try {
      const [s, b, acc, cats] = await Promise.all([
        fetchFundSummary(accountId),
        fetchFundTransactions(accountId),
        fetchAccounts(),
        fetchCategories(),
      ]);
      setSummary(s);
      setBreakdown(b);
      setAccounts(acc);
      setCategories(cats);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }, [accountId]);

  useEffect(() => {
    load();
  }, [load]);

  function openAdd(member: "mine" | "friend") {
    setDefaultMember(member);
    setAddModalOpen(true);
  }

  async function handleAddExpense(payload: {
    amount: number;
    description: string;
    category_id?: string;
    member: "mine" | "friend";
  }) {
    await createTransaction({
      account_id: accountId,
      type: "expense",
      amount: payload.amount,
      description: payload.description,
      category_id: payload.category_id || null,
      tags: [payload.member === "mine" ? FUND_TAG_MINE : FUND_TAG_FRIEND],
      txn_date: new Date().toISOString(),
    });
    setAddModalOpen(false);
    await load();
  }

  if (loading) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <div className="text-center space-y-3">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-brand-600 border-t-transparent mx-auto" />
          <p className="text-sm text-muted">Loading fund data...</p>
        </div>
      </div>
    );
  }

  if (!summary) {
    return (
      <div className="p-8 text-center">
        <p className="text-muted">Fund account not found or not a fund type.</p>
        <p className="text-sm text-muted mt-2">
          Make sure the account has <code>account_subtype = "fund"</code>.
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl space-y-3 md:space-y-6">
      {/* ── HEADER ── */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2 text-brand-600 mb-1">
            <Users className="h-5 w-5" />
            <span className="text-sm font-semibold uppercase tracking-wide">
              Shared Fund
            </span>
          </div>
          <h1 className="text-2xl font-semibold text-ink">
            {summary.account_name}
          </h1>
          <p className="text-sm text-muted mt-1">
            Shared fund — tracking outstanding settlement and spending between
            you and your friend.
          </p>
        </div>
        <Button variant="secondary" onClick={load}>
          <RefreshCw className="h-4 w-4" />
          Refresh
        </Button>
      </div>

      {/* ── BALANCE HERO ── */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <HeroCard
          label="Fund Balance"
          value={summary.fund_balance}
          currency={summary.currency}
          icon={Wallet}
          color="from-brand-600 to-teal-500"
        />
        <HeroCard
          label="Outstanding"
          value={summary.outstanding_amount}
          currency={summary.currency}
          icon={TrendingDown}
          color={
            summary.outstanding_amount > 0
              ? "from-red-600 to-rose-500"
              : summary.outstanding_amount < 0
                ? "from-green-600 to-emerald-500"
                : "from-slate-600 to-slate-400"
          }
          sub={
            summary.outstanding_amount > 0
              ? "You owe your friend"
              : summary.outstanding_amount < 0
                ? "Friend owes you"
                : "Fund is balanced"
          }
        />
        <HeroCard
          label="Total Contributed"
          value={summary.total_contributed}
          currency={summary.currency}
          icon={ArrowDownLeft}
          color="from-blue-600 to-cyan-500"
        />
        <HeroCard
          label="My Spending"
          value={summary.my_spent}
          currency={summary.currency}
          icon={UserCircle2}
          color="from-violet-600 to-purple-500"
          sub={`${summary.my_spent_pct}% of total`}
        />
        <HeroCard
          label="Friend's Spending"
          value={summary.friend_spent}
          currency={summary.currency}
          icon={UserCheck}
          color="from-amber-600 to-orange-500"
          sub={`${summary.friend_spent_pct}% of total`}
        />
      </div>

      {/* ── VISUAL SPLIT BAR ── */}
      <SpendSplitBar summary={summary} />

      {/* ── QUICK ADD BUTTONS ── */}
      <div className="flex flex-wrap gap-3">
        <button
          onClick={() => openAdd("mine")}
          className="inline-flex items-center gap-2 rounded-md border border-violet-500/30 bg-violet-500/10 px-4 py-2.5 text-sm font-semibold text-violet-700 hover:bg-violet-500/20 transition dark:text-violet-300"
        >
          <Plus className="h-4 w-4" />
          Add My Expense
        </button>
        <button
          onClick={() => openAdd("friend")}
          className="inline-flex items-center gap-2 rounded-md border border-warning/30 bg-warning-soft px-4 py-2.5 text-sm font-semibold text-warning hover:bg-warning/20 transition"
        >
          <Plus className="h-4 w-4" />
          Add Friend's Expense
        </button>
      </div>

      {/* ── TABS ── */}
      <div className="border-b border-line">
        <div className="flex gap-1">
          {(
            [
              { key: "overview", label: "Overview" },
              { key: "mine", label: `Mine (${breakdown?.mine.length ?? 0})` },
              {
                key: "friend",
                label: `Friend's (${breakdown?.friend.length ?? 0})`,
              },
              {
                key: "untagged",
                label: `Untagged (${breakdown?.untagged.length ?? 0})`,
              },
            ] as { key: Tab; label: string }[]
          ).map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`px-4 py-2.5 text-sm font-semibold border-b-2 transition ${
                tab === t.key
                  ? "border-brand-600 text-brand-700"
                  : "border-transparent text-muted hover:text-ink"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── TAB CONTENT ── */}
      {tab === "overview" && <OverviewTab summary={summary} />}
      {tab === "mine" && (
        <TransactionList
          transactions={breakdown?.mine ?? []}
          member="mine"
          emptyText="No expenses tagged as yours yet."
        />
      )}
      {tab === "friend" && (
        <TransactionList
          transactions={breakdown?.friend ?? []}
          member="friend"
          emptyText="No expenses tagged to your friend yet."
        />
      )}
      {tab === "untagged" && (
        <TransactionList
          transactions={breakdown?.untagged ?? []}
          member="untagged"
          emptyText="All expenses are tagged."
        />
      )}

      {/* ── ADD EXPENSE MODAL ── */}
      <Modal
        open={addModalOpen}
        onClose={() => setAddModalOpen(false)}
        title={
          defaultMember === "mine" ? "Add My Expense" : "Add Friend's Expense"
        }
        description="This will be deducted from the fund balance."
      >
        <AddExpenseForm
          member={defaultMember}
          categories={categories.filter((c) => c.type === "expense")}
          onSubmit={handleAddExpense}
          onCancel={() => setAddModalOpen(false)}
        />
      </Modal>
    </div>
  );
}

/* ─────────────────────────────────────────
   SUB-COMPONENTS
───────────────────────────────────────── */

function HeroCard({
  label,
  value,
  currency,
  icon: Icon,
  color,
  sub,
}: {
  label: string;
  value: number;
  currency: string;
  icon: any;
  color: string;
  sub?: string;
}) {
  return (
    <div
      className={`rounded-xl bg-gradient-to-br ${color} p-4 text-white shadow-soft`}
    >
      <div className="flex items-center justify-between mb-3">
        <p className="text-sm font-medium text-white/80">{label}</p>
        <Icon className="h-4 w-4 text-white/60" />
      </div>
      <p className="text-xl font-semibold">{formatCurrency(value, currency)}</p>
      {sub && <p className="text-xs text-white/70 mt-1">{sub}</p>}
    </div>
  );
}

function SpendSplitBar({ summary }: { summary: FundSummary }) {
  const total = summary.total_spent;
  if (total <= 0) return null;

  return (
    <div className="rounded-xl border border-line bg-card p-4 shadow-soft">
      <h3 className="text-sm font-semibold text-ink mb-3">Spending Split</h3>
      <div className="flex h-4 w-full overflow-hidden rounded-full bg-surface">
        <div
          className="h-full bg-violet-500 transition-all"
          style={{ width: `${summary.my_spent_pct}%` }}
          title={`Mine: ${summary.my_spent_pct}%`}
        />
        <div
          className="h-full bg-accent-500 transition-all"
          style={{ width: `${summary.friend_spent_pct}%` }}
          title={`Friend: ${summary.friend_spent_pct}%`}
        />
        {summary.untagged_pct > 0 && (
          <div
            className="h-full bg-muted/40 transition-all"
            style={{ width: `${summary.untagged_pct}%` }}
            title={`Untagged: ${summary.untagged_pct}%`}
          />
        )}
      </div>
      <div className="mt-3 flex flex-wrap gap-4 text-sm">
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-full bg-violet-500 inline-block" />
          <span className="text-muted">Mine</span>
          <span className="font-semibold text-ink">
            {formatCurrency(summary.my_spent)} ({summary.my_spent_pct}%)
          </span>
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-full bg-accent-500 inline-block" />
          <span className="text-muted">Friend</span>
          <span className="font-semibold text-ink">
            {formatCurrency(summary.friend_spent)} ({summary.friend_spent_pct}%)
          </span>
        </span>
        {summary.untagged_spent > 0 && (
          <span className="flex items-center gap-1.5">
            <span className="h-3 w-3 rounded-full bg-muted/40 inline-block" />
            <span className="text-muted">Untagged</span>
            <span className="font-semibold text-ink">
              {formatCurrency(summary.untagged_spent)} ({summary.untagged_pct}%)
            </span>
          </span>
        )}
      </div>
    </div>
  );
}

function OverviewTab({ summary }: { summary: FundSummary }) {
  return (
    <div className="space-y-4">
      {/* Settlement suggestion */}
      <div className="rounded-xl border border-line bg-card p-4 shadow-soft">
        <h3 className="text-sm font-semibold text-ink mb-1">
          Settlement Summary
        </h3>
        <p className="text-sm text-muted mb-3">
          Based on current spending and transfers, here’s what the fund
          currently owes.
        </p>
        <div className="space-y-2 text-sm">
          <Row label="Fund opened with" value={summary.total_contributed} />
          <Row label="Total spent" value={summary.total_spent} negative />
          <Row
            label="Outstanding"
            value={summary.outstanding_amount}
            bold
            highlight={
              summary.outstanding_amount > 0
                ? "red"
                : summary.outstanding_amount < 0
                  ? "green"
                  : undefined
            }
          />
          <p className="text-sm text-muted mb-2">
            {summary.outstanding_amount > 0
              ? "You currently owe your friend this amount."
              : summary.outstanding_amount < 0
                ? "Your friend currently owes you this amount."
                : "The fund is currently balanced between both parties."}
          </p>
          <div className="border-t border-line pt-2 mt-2">
            <Row
              label="Remaining balance"
              value={summary.fund_balance}
              bold
              highlight={summary.fund_balance < 0 ? "red" : "green"}
            />
          </div>
        </div>
      </div>

      {/* Recent activity */}
      <div className="rounded-xl border border-line bg-card p-4 shadow-soft">
        <h3 className="text-sm font-semibold text-ink mb-3">Recent Activity</h3>
        {summary.recent_transactions.length === 0 ? (
          <p className="text-sm text-muted">No transactions yet.</p>
        ) : (
          <div className="space-y-2">
            {summary.recent_transactions.slice(0, 10).map((t) => (
              <TransactionRow key={t.id} transaction={t} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Row({
  label,
  value,
  negative,
  bold,
  highlight,
}: {
  label: string;
  value: number;
  negative?: boolean;
  bold?: boolean;
  highlight?: "green" | "red";
}) {
  return (
    <div className={`flex justify-between ${bold ? "font-semibold" : ""}`}>
      <span className="text-muted">{label}</span>
      <span
        className={
          highlight === "green"
            ? "text-income"
            : highlight === "red"
              ? "text-expense"
              : ""
        }
      >
        {negative ? "-" : ""}
        {formatCurrency(Math.abs(value))}
      </span>
    </div>
  );
}

function TransactionList({
  transactions,
  member,
  emptyText,
}: {
  transactions: FundTransaction[];
  member: "mine" | "friend" | "untagged";
  emptyText: string;
}) {
  if (transactions.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-line bg-card p-8 text-center">
        <p className="text-sm text-muted">{emptyText}</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {transactions.map((t) => (
        <TransactionRow key={t.id} transaction={{ ...t, member }} />
      ))}
    </div>
  );
}

function TransactionRow({ transaction }: { transaction: FundTransaction }) {
  const memberColors = {
    mine: "bg-violet-500/10 text-violet-700 border-violet-500/30 dark:text-violet-300",
    friend: "bg-warning-soft text-warning border-warning/30",
    untagged: "bg-surface text-muted border-line",
  };
  const memberLabels = {
    mine: "Mine",
    friend: "Friend",
    untagged: "Untagged",
  };
  const MemberIcon =
    transaction.member === "mine"
      ? UserCircle2
      : transaction.member === "friend"
        ? UserCheck
        : HelpCircle;

  return (
    <article className="flex items-center justify-between gap-3 rounded-lg border border-line bg-card px-4 py-3 shadow-sm">
      <div className="flex items-center gap-3 min-w-0">
        <div
          className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full border text-xs font-semibold ${
            memberColors[transaction.member]
          }`}
        >
          <MemberIcon className="h-4 w-4" />
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-ink">
            {transaction.merchant_name || transaction.description || "Expense"}
          </p>
          <p className="text-xs text-muted">
            {new Date(transaction.txn_date).toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
              year: "numeric",
            })}
          </p>
        </div>
      </div>
      <div className="flex items-center gap-3 shrink-0">
        <span
          className={`rounded-full border px-2 py-0.5 text-xs font-semibold ${
            memberColors[transaction.member]
          }`}
        >
          {memberLabels[transaction.member]}
        </span>
        <p
          className={`text-sm font-semibold ${
            transaction.type === "income" ? "text-income" : "text-expense"
          }`}
        >
          {transaction.type === "expense" ? "-" : "+"}
          {formatCurrency(transaction.amount)}
        </p>
      </div>
    </article>
  );
}

function AddExpenseForm({
  member,
  categories,
  onSubmit,
  onCancel,
}: {
  member: "mine" | "friend";
  categories: Category[];
  onSubmit: (data: {
    amount: number;
    description: string;
    category_id?: string;
    member: "mine" | "friend";
  }) => Promise<void>;
  onCancel: () => void;
}) {
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [saving, setSaving] = useState(false);
  const [selectedMember, setSelectedMember] = useState<"mine" | "friend">(
    member,
  );

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!amount || Number(amount) <= 0) return;
    setSaving(true);
    try {
      await onSubmit({
        amount: Number(amount),
        description,
        category_id: categoryId || undefined,
        member: selectedMember,
      });
    } finally {
      setSaving(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* Member toggle */}
      <div>
        <p className="mb-2 text-sm font-medium text-ink">Who spent this?</p>
        <div className="grid grid-cols-2 gap-2">
          {(["mine", "friend"] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setSelectedMember(m)}
              className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 text-sm font-semibold transition ${
                selectedMember === m
                  ? m === "mine"
                    ? "border-violet-600 bg-violet-600 text-white"
                    : "border-amber-500 bg-accent-500 text-white"
                  : "border-line bg-card text-muted hover:bg-surface"
              }`}
            >
              {m === "mine" ? (
                <UserCircle2 className="h-4 w-4" />
              ) : (
                <UserCheck className="h-4 w-4" />
              )}
              {m === "mine" ? "Me" : "Friend"}
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="mb-1.5 block text-sm font-medium text-ink">
          Amount
        </label>
        <input
          type="number"
          step="0.01"
          min="0.01"
          required
          autoFocus
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="h-11 w-full rounded-md border border-line bg-card px-3 text-sm outline-none focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          placeholder="0.00"
        />
      </div>

      <div>
        <label className="mb-1.5 block text-sm font-medium text-ink">
          Description
        </label>
        <input
          type="text"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          className="h-11 w-full rounded-md border border-line bg-card px-3 text-sm outline-none focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          placeholder="What was this for?"
        />
      </div>

      <div>
        <label className="mb-1.5 block text-sm font-medium text-ink">
          Category (optional)
        </label>
        <select
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
          className="h-11 w-full rounded-md border border-line bg-card px-3 text-sm outline-none focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
        >
          <option value="">No category</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </div>

      <div className="flex justify-end gap-3 pt-1">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={saving || !amount}>
          <TrendingDown className="h-4 w-4" />
          {saving ? "Saving..." : "Record Expense"}
        </Button>
      </div>
    </form>
  );
}

