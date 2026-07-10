"use client";

import {
  ArrowRightLeft,
  CreditCard,
  Edit3,
  Eye,
  Landmark,
  Plus,
  RefreshCw,
  Trash2,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";

import { AccountAnalyticsCharts } from "@/components/accounts/account-analytics";
import { AccountForm } from "@/components/accounts/account-form";
import { TransferModal } from "@/components/accounts/transfer-modal";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { cn, formatCurrency } from "@/lib/utils";
import {
  createAccount,
  createTransfer,
  deleteAccount,
  fetchAccountAnalytics,
  fetchAccountSummary,
  fetchAccounts,
  updateAccount,
} from "@/services/finance-service";

import type {
  Account,
  AccountAnalytics,
  AccountCreatePayload,
  AccountSummary,
  AccountUpdatePayload,
  TransferPayload,
} from "@/types/api";

const groups = [
  { key: "cash", label: "Cash", icon: Wallet },
  { key: "bank", label: "Bank", icon: Landmark },
  { key: "mobile", label: "Mobile Banking", icon: Wallet },
  { key: "debit", label: "Debit Cards", icon: CreditCard },
  { key: "card", label: "Cards", icon: CreditCard },
] as const;

function normalizedType(account: Account) {
  return account.type.toLowerCase();
}

function isCreditCard(account: Account) {
  return normalizedType(account) === "card" || normalizedType(account) === "credit_card";
}

export default function AccountsPage() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [summary, setSummary] = useState<AccountSummary | null>(null);
  const [analytics, setAnalytics] = useState<AccountAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [accountModalOpen, setAccountModalOpen] = useState(false);
  const [transferModalOpen, setTransferModalOpen] = useState(false);
  const [editingAccount, setEditingAccount] = useState<Account | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const loadAccounts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [accountData, summaryData, analyticsData] = await Promise.all([
        fetchAccounts(),
        fetchAccountSummary(),
        fetchAccountAnalytics(),
      ]);
      setAccounts(accountData);
      setSummary(summaryData);
      setAnalytics(analyticsData);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load accounts");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAccounts();
  }, [loadAccounts]);

  const groupedAccounts = useMemo(() => {
    return {
      cash: accounts.filter(
        (account) =>
          normalizedType(account) === "cash" && account.is_active && !account.archived,
      ),
      bank: accounts.filter(
        (account) =>
          normalizedType(account) === "bank" && account.is_active && !account.archived,
      ),
      mobile: accounts.filter(
        (account) =>
          normalizedType(account) === "mobile_banking" && account.is_active && !account.archived,
      ),
      debit: accounts.filter(
        (account) =>
          normalizedType(account) === "debit_card" && account.is_active && !account.archived,
      ),
      card: accounts.filter(
        (account) =>
          isCreditCard(account) && account.is_active && !account.archived,
      ),
    };
  }, [accounts]);

  function openCreateModal() {
    setEditingAccount(null);
    setAccountModalOpen(true);
  }

  function openEditModal(account: Account) {
    setEditingAccount(account);
    setAccountModalOpen(true);
  }

  function closeAccountModal() {
    setAccountModalOpen(false);
    setEditingAccount(null);
  }

  async function handleSave(
    payload: AccountCreatePayload | AccountUpdatePayload,
  ) {
    try {
      if (editingAccount) {
        await updateAccount(editingAccount.id, payload as AccountUpdatePayload);
      } else {
        await createAccount(payload as AccountCreatePayload);
      }
      closeAccountModal();
      await loadAccounts();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    }
  }

  async function handleTransfer(payload: TransferPayload) {
    try {
      await createTransfer(payload);
      setTransferModalOpen(false);
      await loadAccounts();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Transfer failed");
    }
  }

  async function handleDelete(account: Account) {
    if (!confirm(`Archive "${account.name}"?`)) return;
    setDeletingId(account.id);
    try {
      await deleteAccount(account.id);
      await loadAccounts();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Archive failed");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="space-y-3 md:space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Accounts</h1>
          <p className="text-sm text-muted">
            Balances, credit exposure, transfers, and net worth in one place.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={loadAccounts} variant="secondary">
            <RefreshCw className="h-4 w-4" />
            Refresh
          </Button>
          <Button
            onClick={() => setTransferModalOpen(true)}
            variant="secondary"
          >
            <ArrowRightLeft className="h-4 w-4" />
            Transfer
          </Button>
          <Button onClick={openCreateModal}>
            <Plus className="h-4 w-4" />
            Add Account
          </Button>
        </div>
      </div>

      {error ? (
        <div className="rounded-md border border-expense/30 bg-expense-soft px-4 py-3 text-sm text-expense">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <SummaryCard
          label="Net worth"
          value={summary?.net_worth}
          tone="brand"
        />
        <SummaryCard
          label="Total assets"
          value={summary?.total_assets}
          tone="blue"
        />
        <SummaryCard
          label="Total liabilities"
          value={summary?.liabilities}
          tone="amber"
        />
        <SummaryCard
          label="Credit used"
          value={summary?.credit_used}
          suffix="%"
          tone="violet"
        />
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.1fr)_minmax(360px,0.9fr)]">
        <div className="space-y-5">
          {loading ? (
            <p className="text-sm text-muted">Loading accounts...</p>
          ) : null}
          {!loading && accounts.length === 0 ? (
            <p className="text-sm text-muted">No accounts found.</p>
          ) : null}

          {groups.map((group) => {
            const items = groupedAccounts[group.key];
            if (items.length === 0) return null;
            const Icon = group.icon;
            return (
              <section key={group.key} className="space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-sm font-semibold text-ink">
                    <Icon className="h-4 w-4 text-brand-600" />
                    {group.label}
                  </div>
                  <span className="text-xs font-medium text-muted">
                    {items.length} accounts
                  </span>
                </div>
                <div className="grid gap-3">
                  {items.map((account) => (
                    <AccountRow
                      key={account.id}
                      account={account}
                      deleting={deletingId === account.id}
                      onEdit={() => openEditModal(account)}
                      onDelete={() => handleDelete(account)}
                    />
                  ))}
                </div>
              </section>
            );
          })}
        </div>

        <AccountAnalyticsCharts analytics={analytics} />
      </div>

      <Modal
        open={accountModalOpen}
        onClose={closeAccountModal}
        title={editingAccount ? "Edit Account" : "Add Account"}
      >
        <AccountForm
          account={editingAccount}
          onSubmit={handleSave}
          onCancel={closeAccountModal}
        />
      </Modal>

      <Modal
        open={transferModalOpen}
        onClose={() => setTransferModalOpen(false)}
        title="Transfer Money"
      >
        <TransferModal
          accounts={accounts}
          onSubmit={handleTransfer}
          onCancel={() => setTransferModalOpen(false)}
        />
      </Modal>
    </div>
  );
}

function SummaryCard({
  label,
  value,
  suffix,
  tone,
}: {
  label: string;
  value?: string;
  suffix?: string;
  tone: "brand" | "blue" | "amber" | "violet";
}) {
  const tones = {
    brand: "from-brand-600 to-teal-500",
    blue: "from-blue-600 to-cyan-500",
    amber: "from-amber-600 to-orange-500",
    violet: "from-violet-600 to-fuchsia-500",
  };

  return (
    <section
      className={cn(
        "rounded-md bg-gradient-to-br p-4 text-white shadow-soft",
        tones[tone],
      )}
    >
      <p className="text-sm font-medium text-white/80">{label}</p>
      <p className="mt-3 text-2xl font-semibold">
        {suffix
          ? `${Number(value ?? 0).toFixed(1)}${suffix}`
          : formatCurrency(value ?? 0)}
      </p>
    </section>
  );
}

function AccountRow({
  account,
  deleting,
  onEdit,
  onDelete,
}: {
  account: Account;
  deleting: boolean;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const cardDetails = account.card_details;
  const creditLimit = Number(account.credit_limit ?? cardDetails?.credit_limit ?? 0);
  const currentOutstanding = Number(
    account.current_outstanding ??
      (isCreditCard(account) ? Math.abs(Number(account.opening_balance ?? account.balance ?? 0)) : 0),
  );
  const availableLimit = Math.max(creditLimit - currentOutstanding, 0);
  const utilization =
    isCreditCard(account) && creditLimit > 0
      ? (currentOutstanding / creditLimit) * 100
      : 0;

  return (
    <article className="rounded-md border border-line bg-card p-4 shadow-soft">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex min-w-0 gap-3">
          <div
            className="mt-1 flex h-10 w-10 shrink-0 items-center justify-center rounded-md text-white"
            style={{ backgroundColor: account.color ?? "#137f65" }}
          >
            {isCreditCard(account) || normalizedType(account) === "debit_card" ? (
              <CreditCard className="h-5 w-5" />
            ) : normalizedType(account) === "bank" ? (
              <Landmark className="h-5 w-5" />
            ) : (
              <Wallet className="h-5 w-5" />
            )}
          </div>
          <div className="min-w-0">
            <h3 className="truncate font-semibold text-ink">{account.name}</h3>
            <p className="text-sm text-muted">
              {[
                account.institution_name,
                account.account_subtype,
                account.currency,
              ]
                .filter(Boolean)
                .join(" - ")}
            </p>
            {isCreditCard(account) && (cardDetails || account.credit_limit) ? (
              <div className="mt-3 w-full max-w-sm">
                <div className="mb-1 flex justify-between text-xs text-muted">
                  <span>
                    {formatCurrency(
                      availableLimit,
                      account.currency,
                    )}{" "}
                    available
                  </span>
                  <span>{utilization.toFixed(1)}% used</span>
                </div>
                <div className="h-2 rounded-full bg-surface">
                  <div
                    className="h-2 rounded-full bg-accent-500"
                    style={{ width: `${Math.min(utilization, 100)}%` }}
                  />
                </div>
                <p className="mt-2 text-xs text-muted">
                  Limit{" "}
                  {formatCurrency(creditLimit, account.currency)}
                  {account.billing_cycle_day ?? cardDetails?.statement_day
                    ? ` - Statement ${account.billing_cycle_day ?? cardDetails?.statement_day}`
                    : ""}
                  {account.payment_due_day ?? cardDetails?.due_day ? ` - Due ${account.payment_due_day ?? cardDetails?.due_day}` : ""}
                </p>
              </div>
            ) : null}
          </div>
        </div>

        <div className="flex items-center justify-between gap-4 sm:justify-end">
          <div className="text-right">
            <p
              className={cn(
                "text-lg font-semibold",
                Number(account.balance) < 0 ? "text-expense" : "text-ink",
              )}
            >
              {formatCurrency(isCreditCard(account) ? currentOutstanding : account.balance, account.currency)}
            </p>
            <p className="text-xs text-muted">
              {isCreditCard(account) ? "Outstanding " : "Opening "}
              {formatCurrency(account.opening_balance, account.currency)}
            </p>
          </div>
          <div className="flex gap-1">
            {account.account_subtype === "fund" ? (
              <Link
                href={`/dashboard/funds/${account.id}`}
                className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink"
                title="View fund details"
              >
                <Eye className="h-4 w-4" />
              </Link>
            ) : null}
            <button
              className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink"
              onClick={onEdit}
              type="button"
              title="Edit account"
            >
              <Edit3 className="h-4 w-4" />
            </button>
            <button
              className="rounded-md p-2 text-expense hover:bg-expense-soft"
              disabled={deleting}
              onClick={onDelete}
              type="button"
              title="Archive account"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </article>
  );
}
