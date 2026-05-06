"use client";

import { Edit3, Plus, RefreshCw, Trash2 } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { AccountForm } from "@/components/accounts/account-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";
import {
  createAccount,
  deleteAccount,
  fetchAccounts,
  updateAccount,
} from "@/services/finance-service";

import type {
  Account,
  AccountCreatePayload,
  AccountUpdatePayload,
} from "@/types/api";

// ✅ FIXED TYPES (backend aligned)
const typeLabels: Record<Account["type"], string> = {
  cash: "Cash",
  bank: "Bank",
  card: "Card",
};

export default function AccountsPage() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [modalOpen, setModalOpen] = useState(false);
  const [editingAccount, setEditingAccount] = useState<Account | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  // ✅ FIX: balance
  const totalBalance = useMemo(
    () => accounts.reduce((total, acc) => total + Number(acc.balance || 0), 0),
    [accounts],
  );

  const loadAccounts = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const data = await fetchAccounts();
      setAccounts(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load accounts");
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

  async function handleSave(
    payload: AccountCreatePayload | AccountUpdatePayload,
  ) {
    try {
      if (editingAccount) {
        await updateAccount(editingAccount.id, payload as AccountUpdatePayload);
      } else {
        await createAccount(payload as AccountCreatePayload);
      }

      closeModal();
      await loadAccounts();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    }
  }

  async function handleDelete(account: Account) {
    if (!confirm(`Delete "${account.name}"?`)) return;

    setDeletingId(account.id);

    try {
      await deleteAccount(account.id);
      await loadAccounts();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Delete failed");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="space-y-6">
      {/* HEADER */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-xl font-semibold">Accounts</h1>
          <p className="text-sm text-gray-500">Manage your accounts</p>
        </div>

        <div className="flex gap-2">
          <Button onClick={loadAccounts} variant="secondary">
            <RefreshCw className="w-4 h-4" />
          </Button>

          <Button onClick={openCreateModal}>
            <Plus className="w-4 h-4" />
            Add
          </Button>
        </div>
      </div>

      {/* STATS */}
      <div className="grid grid-cols-3 gap-4">
        <div className="card">
          <p>Total</p>
          <h2>{accounts.length}</h2>
        </div>

        <div className="card">
          <p>Active</p>
          <h2>{accounts.filter((a) => a.is_active).length}</h2>
        </div>

        <div className="card">
          <p>Balance</p>
          <h2>{formatCurrency(totalBalance)}</h2>
        </div>
      </div>

      {/* ERROR */}
      {error && <div className="text-red-500 text-sm">{error}</div>}

      {/* LIST */}
      <div className="space-y-3">
        {loading && <p>Loading...</p>}

        {!loading && accounts.length === 0 && <p>No accounts found</p>}

        {accounts.map((acc) => (
          <div
            key={acc.id}
            className="border p-4 rounded flex justify-between items-center"
          >
            <div>
              <p className="font-medium">{acc.name}</p>
              <p className="text-sm text-gray-500">
                {typeLabels[acc.type]} • {acc.currency}
              </p>
            </div>

            <div className="flex items-center gap-4">
              <span className="font-semibold">
                {formatCurrency(acc.balance, acc.currency)}
              </span>

              <button onClick={() => openEditModal(acc)}>
                <Edit3 className="w-4 h-4" />
              </button>

              <button
                disabled={deletingId === acc.id}
                onClick={() => handleDelete(acc)}
              >
                <Trash2 className="w-4 h-4 text-red-500" />
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* MODAL */}
      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingAccount ? "Edit Account" : "Add Account"}
      >
        <AccountForm
          account={editingAccount}
          onSubmit={handleSave}
          onCancel={closeModal}
        />
      </Modal>
    </div>
  );
}
