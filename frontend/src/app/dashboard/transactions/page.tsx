"use client";

import { useEffect, useState } from "react";

import {
  createTransaction,
  deleteTransaction,
  fetchAccounts,
  fetchCategories,
  fetchTransactions,
  updateTransaction,
} from "@/services/finance-service";

import { TransactionForm } from "@/components/transactions/transaction-form";
import { Modal } from "@/components/ui/modal";
import { formatCurrency } from "@/lib/utils";

/* ================= DATE HELPERS ================= */

function formatDate(date: Date) {
  return date.toISOString().split("T")[0];
}

function getToday() {
  return formatDate(new Date());
}

/* ================= COMPONENT ================= */

export default function TransactionPage() {
  const [accounts, setAccounts] = useState<any[]>([]);
  const [categories, setCategories] = useState<any[]>([]);
  const [transactions, setTransactions] = useState<any[]>([]);

  const [loading, setLoading] = useState(true);

  // ✅ DATE FILTER (single + range)
  const [fromDate, setFromDate] = useState(getToday());
  const [toDate, setToDate] = useState(getToday());

  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);

  /* ================= LOAD ================= */

  useEffect(() => {
    load();
  }, [fromDate, toDate]);

  async function load() {
    try {
      setLoading(true);

      const [acc, cat, tx] = await Promise.all([
        fetchAccounts(),
        fetchCategories(),
        fetchTransactions({
          from_date: fromDate,
          to_date: toDate,
          limit: 50,
          offset: 0,
        }),
      ]);

      setAccounts(acc || []);
      setCategories(cat || []);
      setTransactions(tx?.items || []);
    } catch (e) {
      console.error(e);
      alert("Failed to load transactions");
    } finally {
      setLoading(false);
    }
  }

  /* ================= DATE NAV ================= */

  function goToday() {
    const today = getToday();
    setFromDate(today);
    setToDate(today);
  }

  function changeDay(offset: number) {
    const d = new Date(fromDate);
    d.setDate(d.getDate() + offset);
    const newDate = formatDate(d);

    setFromDate(newDate);
    setToDate(newDate);
  }

  /* ================= CRUD ================= */

  function openCreate() {
    setEditing(null);
    setModalOpen(true);
  }

  function openEdit(t: any) {
    setEditing(t);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditing(null);
  }

  async function handleSubmit(payload: any) {
    await (editing
      ? updateTransaction(editing.id, payload)
      : createTransaction(payload));

    closeModal();
    await load();
  }

  async function handleDelete(id: string) {
    if (!confirm("Delete this transaction?")) return;

    await deleteTransaction(id);
    await load();
  }

  /* ================= HELPERS ================= */

  function getAccountName(id: string) {
    return accounts.find((a) => a.id === id)?.name || "Unknown";
  }

  function getCategoryName(id: string) {
    return categories.find((c) => c.id === id)?.name || "Unknown";
  }

  /* ================= UI ================= */

  return (
    <div className="space-y-6">
      {/* HEADER */}
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold">Transactions</h1>

        <button
          onClick={openCreate}
          className="bg-blue-600 text-white px-4 py-2 rounded-lg"
        >
          + Add
        </button>
      </div>

      {/* DATE FILTER */}
      <div className="bg-white p-4 rounded-xl border space-y-4">
        {/* RANGE */}
        <div className="flex gap-3 items-center">
          <input
            type="date"
            value={fromDate}
            onChange={(e) => setFromDate(e.target.value)}
            className="border rounded px-3 py-1"
          />

          <span>→</span>

          <input
            type="date"
            value={toDate}
            onChange={(e) => setToDate(e.target.value)}
            className="border rounded px-3 py-1"
          />
        </div>

        {/* QUICK ACTIONS */}
        <div className="flex gap-4">
          <button onClick={goToday} className="text-sm text-blue-600">
            Today
          </button>

          <button
            onClick={() => changeDay(-1)}
            className="text-sm text-gray-600"
          >
            ⬅ Previous
          </button>

          <button
            onClick={() => changeDay(1)}
            className="text-sm text-gray-600"
          >
            Next ➡
          </button>
        </div>
      </div>

      {/* LIST */}
      <div className="bg-white p-4 rounded-xl border">
        {loading && <p>Loading...</p>}

        {!loading && transactions.length === 0 && (
          <p className="text-sm text-gray-500">No transactions</p>
        )}

        {transactions.map((t) => (
          <div
            key={t.id}
            className="flex justify-between items-center py-3 border-b"
          >
            {/* LEFT */}
            <div>
              <p className="font-medium capitalize">{t.type}</p>

              <p className="text-xs text-gray-500">
                {getCategoryName(t.category_id)} •{" "}
                {getAccountName(t.account_id)}
              </p>

              <p className="text-xs text-gray-400">{t.transaction_date}</p>
            </div>

            {/* RIGHT */}
            <div className="flex gap-3 items-center">
              <p
                className={
                  t.type === "income"
                    ? "text-green-600 font-semibold"
                    : "text-red-500 font-semibold"
                }
              >
                {formatCurrency(t.amount)}
              </p>

              <button onClick={() => openEdit(t)}>✏️</button>
              <button onClick={() => handleDelete(t.id)}>🗑</button>
            </div>
          </div>
        ))}
      </div>

      {/* MODAL */}
      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editing ? "Edit Transaction" : "Add Transaction"}
      >
        <TransactionForm
          transaction={editing}
          accounts={accounts}
          categories={categories}
          selectedDate={fromDate}
          onSubmit={handleSubmit}
          onCancel={closeModal}
        />
      </Modal>
    </div>
  );
}
