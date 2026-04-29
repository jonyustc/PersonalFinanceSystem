"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Edit3, Plus, RefreshCw, Trash2 } from "lucide-react";

import { AccountForm } from "@/components/accounts/account-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
import { createAccount, deleteAccount, fetchAccounts, updateAccount } from "@/services/finance-service";
import type { Account, AccountCreatePayload, AccountUpdatePayload } from "@/types/api";

const typeLabels: Record<Account["type"], string> = {
  cash: "Cash wallet",
  bank: "Bank account",
  debit_card: "Debit card",
  credit_card: "Credit card",
  mobile_banking: "Mobile banking"
};

export default function AccountsPage() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingAccount, setEditingAccount] = useState<Account | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const totalBalance = useMemo(
    () => accounts.reduce((total, account) => total + Number(account.current_balance), 0),
    [accounts]
  );

  const loadAccounts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setAccounts(await fetchAccounts());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to load accounts");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAccounts();
  }, [loadAccounts]);

  function openCreateModal() {
    setEditingAccount(null);
    setModalOpen(true);
  }

  function openEditModal(account: Account) {
    setEditingAccount(account);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingAccount(null);
  }

  async function handleSave(payload: AccountCreatePayload | AccountUpdatePayload) {
    if (editingAccount) {
      await updateAccount(editingAccount.id, payload as AccountUpdatePayload);
    } else {
      await createAccount(payload as AccountCreatePayload);
    }
    closeModal();
    await loadAccounts();
  }

  async function handleDelete(account: Account) {
    const confirmed = window.confirm(`Delete "${account.name}"? This cannot be undone.`);
    if (!confirmed) return;

    setDeletingId(account.id);
    setError(null);
    try {
      await deleteAccount(account.id);
      await loadAccounts();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to delete account");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Accounts</h1>
          <p className="mt-1 text-sm text-muted">Cash, cards, bank, and mobile banking accounts.</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button variant="secondary" onClick={loadAccounts} disabled={loading}>
            <RefreshCw className="h-4 w-4" aria-hidden />
            Refresh
          </Button>
          <Button onClick={openCreateModal}>
            <Plus className="h-4 w-4" aria-hidden />
            Add account
          </Button>
        </div>
      </div>

      <section className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Total accounts</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{accounts.length}</p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Active accounts</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{accounts.filter((account) => account.is_active).length}</p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Total balance</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{formatCurrency(totalBalance)}</p>
        </div>
      </section>

      {error ? <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</p> : null}

      <section className="hidden overflow-hidden rounded-lg border border-line bg-white shadow-soft lg:block">
        <div className="grid grid-cols-[1.1fr_150px_140px_150px_120px] gap-4 border-b border-line px-5 py-3 text-xs font-semibold uppercase text-muted">
          <span>Name</span>
          <span>Type</span>
          <span>Currency</span>
          <span className="text-right">Balance</span>
          <span className="text-right">Actions</span>
        </div>
        {loading ? <p className="px-5 py-6 text-sm text-muted">Loading accounts...</p> : null}
        {!loading && !accounts.length ? <p className="px-5 py-6 text-sm text-muted">No accounts yet.</p> : null}
        {accounts.map((account) => (
          <div
            className="grid grid-cols-[1.1fr_150px_140px_150px_120px] items-center gap-4 border-b border-line px-5 py-4 text-sm last:border-0"
            key={account.id}
          >
            <div className="min-w-0">
              <p className="truncate font-semibold text-ink">{account.name}</p>
              <p className="truncate text-xs text-muted">{account.notes || (account.is_active ? "Active" : "Inactive")}</p>
            </div>
            <span className="text-muted">{typeLabels[account.type]}</span>
            <span className="font-medium text-ink">{account.currency}</span>
            <span className="text-right font-semibold text-ink">{formatCurrency(account.current_balance, account.currency)}</span>
            <div className="flex justify-end gap-2">
              <button className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink" onClick={() => openEditModal(account)} type="button">
                <Edit3 className="h-4 w-4" aria-hidden />
              </button>
              <button
                className="rounded-md p-2 text-muted hover:bg-red-50 hover:text-red-700 disabled:opacity-50"
                disabled={deletingId === account.id}
                onClick={() => handleDelete(account)}
                type="button"
              >
                <Trash2 className="h-4 w-4" aria-hidden />
              </button>
            </div>
          </div>
        ))}
      </section>

      <section className="grid gap-4 lg:hidden">
        {loading ? <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">Loading accounts...</p> : null}
        {!loading && !accounts.length ? <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">No accounts yet.</p> : null}
        {accounts.map((account) => (
          <article className="rounded-lg border border-line bg-white p-5 shadow-soft" key={account.id}>
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0">
                <p className="text-sm font-medium text-muted">{typeLabels[account.type]}</p>
                <h2 className="mt-1 truncate text-lg font-semibold text-ink">{account.name}</h2>
              </div>
              <span className="rounded-md bg-brand-50 px-2 py-1 text-xs font-semibold text-brand-700">{account.currency}</span>
            </div>
            <p className="mt-4 text-2xl font-semibold text-ink">{formatCurrency(account.current_balance, account.currency)}</p>
            <p className="mt-2 text-sm text-muted">{account.notes || (account.is_active ? "Active" : "Inactive")}</p>
            <div className="mt-4 flex gap-2">
              <Button className="flex-1" variant="secondary" onClick={() => openEditModal(account)}>
                <Edit3 className="h-4 w-4" aria-hidden />
                Edit
              </Button>
              <Button className="flex-1" variant="secondary" disabled={deletingId === account.id} onClick={() => handleDelete(account)}>
                <Trash2 className="h-4 w-4" aria-hidden />
                Delete
              </Button>
            </div>
          </article>
        ))}
      </section>

      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingAccount ? "Edit account" : "Add account"}
        description={editingAccount ? "Update account details without changing transaction-managed balances." : "Create a new cash, bank, card, or mobile banking account."}
      >
        <AccountForm account={editingAccount} onCancel={closeModal} onSubmit={handleSave} />
      </Modal>
    </div>
  );
}
