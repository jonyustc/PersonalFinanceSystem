"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowLeftRight, Save } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { formatCurrency } from "@/lib/utils";
import { CategoryTreeSelect } from "./category-tree-select";

import type { Account, Category, TransactionCreatePayload } from "@/types/api";

/* ================= SCHEMA ================= */

const schema = z
  .object({
    type: z.enum(["income", "expense", "transfer"]),
    account_id: z.string().min(1, "Account required"),
    transfer_account_id: z.string().optional(),
    category_id: z.string().optional(),
    payment_method: z.string().optional(),
    amount: z.coerce.number().gt(0, "Amount required"),
    txn_date: z.string(),
    is_emergency: z.boolean().optional(),
    description: z.string().optional(),
  })
  .refine(
    (data) =>
      data.type !== "transfer" ||
      (data.account_id &&
        data.transfer_account_id &&
        data.account_id !== data.transfer_account_id),
    {
      message: "From & To account must be different",
      path: ["transfer_account_id"],
    },
  );

type FormValues = z.infer<typeof schema>;

type Props = {
  accounts: Account[];
  categories: Category[];
  transaction?: any;
  selectedDate: string;
  onSubmit: (payload: TransactionCreatePayload) => Promise<void>;
  onCancel: () => void;
};

export function TransactionForm({
  accounts,
  categories,
  transaction,
  selectedDate,
  onSubmit,
  onCancel,
}: Props) {
  const [localCategories, setLocalCategories] = useState<Category[]>([]);

  useEffect(() => {
    setLocalCategories(categories || []);
  }, [categories]);

  const {
    register,
    handleSubmit,
    control,
    setValue,
    watch,
    formState: { isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      type: transaction?.type ?? "expense",
      account_id: transaction?.account_id ?? "",
      transfer_account_id: transaction?.transfer_account_id ?? "",
      category_id: transaction?.category_id ?? "",
      payment_method: transaction?.payment_method ?? "",
      amount: Number(transaction?.amount ?? 0),
      txn_date: transaction?.txn_date
        ? new Date(transaction.txn_date).toISOString().slice(0, 16)
        : selectedDate + "T12:00",
      is_emergency: transaction?.is_emergency ?? false,
      description: transaction?.description ?? "",
    },
  });

  const type = useWatch({ control, name: "type" });
  const amount = useWatch({ control, name: "amount" });
  const fromId = useWatch({ control, name: "account_id" });
  const toId = useWatch({ control, name: "transfer_account_id" });

  const isTransfer = type === "transfer";

  /* ================= RESET ================= */

  useEffect(() => {
    if (type === "transfer") {
      setValue("category_id", "");
    } else {
      setValue("transfer_account_id", "");
    }
  }, [type, setValue]);

  /* ================= ACCOUNTS ================= */

  const fromAccount = useMemo(
    () => accounts.find((a) => a.id === fromId),
    [accounts, fromId],
  );

  const toAccount = useMemo(
    () => accounts.find((a) => a.id === toId),
    [accounts, toId],
  );

  const fromBalance = Number(fromAccount?.balance || 0);
  const toBalance = Number(toAccount?.balance || 0);

  const isFromCard = fromAccount?.type === "card";
  const isToCard = toAccount?.type === "card";

  /* ================= BALANCE PREVIEW ================= */

  let previewFrom = fromBalance;
  let previewTo = toBalance;

  if (amount > 0) {
    if (type === "expense") {
      previewFrom = fromBalance - amount; // card → more negative
    }

    if (type === "transfer") {
      // 🔥 BANK → CARD (payment)
      if (!isFromCard && isToCard) {
        previewFrom = fromBalance - amount;
        previewTo = toBalance + amount; // reduce debt
      }

      // 🔥 CARD → BANK (cash advance)
      else if (isFromCard && !isToCard) {
        previewFrom = fromBalance - amount; // more negative
        previewTo = toBalance + amount;
      }

      // normal transfer
      else {
        previewFrom = fromBalance - amount;
        previewTo = toBalance + amount;
      }
    }
  }

  /* ================= INSUFFICIENT ================= */

  const insufficient =
    !isFromCard &&
    (type === "expense" || isTransfer) &&
    amount > 0 &&
    fromBalance < amount;

  /* ================= SWAP ================= */

  function handleSwap() {
    const from = watch("account_id");
    const to = watch("transfer_account_id");

    setValue("account_id", to || "");
    setValue("transfer_account_id", from || "");
  }

  /* ================= SUBMIT ================= */

  async function submit(values: FormValues) {
    await onSubmit({
      account_id: values.account_id,
      transfer_account_id:
        values.type === "transfer" ? values.transfer_account_id || null : null,
      category_id:
        values.type !== "transfer" ? values.category_id || null : null,
      type: values.type,
      payment_method: values.payment_method || null,
      amount: values.amount,
      txn_date: new Date(values.txn_date).toISOString(),
      is_emergency: values.is_emergency || false,
      description: values.description || null,
    });
  }

  /* ================= UI ================= */

  return (
    <form onSubmit={handleSubmit(submit)} className="space-y-5">
      {/* TYPE */}
      <select {...register("type")} className="input">
        <option value="expense">Expense</option>
        <option value="income">Income</option>
        <option value="transfer">Transfer</option>
      </select>

      {/* ACCOUNT */}
      <div className="bg-gray-50 p-3 rounded-lg space-y-2">
        <div className="grid grid-cols-2 gap-2">
          <select {...register("account_id")} className="input">
            <option value="">From</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name} ({formatCurrency(a.balance)})
              </option>
            ))}
          </select>

          {isTransfer && (
            <select {...register("transfer_account_id")} className="input">
              <option value="">To</option>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({formatCurrency(a.balance)})
                </option>
              ))}
            </select>
          )}
        </div>

        {isTransfer && (
          <button
            type="button"
            onClick={handleSwap}
            className="text-xs text-blue-600 flex items-center gap-1"
          >
            <ArrowLeftRight size={14} />
            Swap
          </button>
        )}

        {/* BALANCE PREVIEW */}
        {fromAccount && amount > 0 && (
          <div className="text-xs space-y-1">
            <div>
              From: {formatCurrency(fromBalance)} →{" "}
              <span className={insufficient ? "text-red-500" : ""}>
                {formatCurrency(previewFrom)}
              </span>
            </div>

            {isTransfer && toAccount && (
              <div>
                To: {formatCurrency(toBalance)} →{" "}
                <span className="text-green-600">
                  {formatCurrency(previewTo)}
                </span>
              </div>
            )}
          </div>
        )}

        {insufficient && (
          <p className="text-red-500 text-xs">⚠️ Insufficient balance</p>
        )}
      </div>

      {/* CATEGORY */}
      {!isTransfer && (
        <CategoryTreeSelect
          categories={localCategories}
          type={type}
          value={watch("category_id")}
          onChange={(id: string) =>
            setValue("category_id", id, { shouldDirty: true })
          }
          onCreated={(cat: Category) =>
            setLocalCategories((prev) => [...prev, cat])
          }
        />
      )}

      {/* AMOUNT */}
      <Input type="number" placeholder="Amount" {...register("amount")} />

      {/* DATE */}
      <Input type="datetime-local" {...register("txn_date")} />

      {/* PAYMENT */}
      <select {...register("payment_method")} className="input">
        <option value="">Payment</option>
        <option value="cash">Cash</option>
        <option value="bank">Bank</option>
        <option value="card">Card</option>
      </select>

      {/* DESCRIPTION */}
      <Input placeholder="Note..." {...register("description")} />

      {/* ACTION */}
      <div className="flex justify-end gap-2">
        <Button type="button" onClick={onCancel}>
          Cancel
        </Button>

        <Button type="submit" disabled={isSubmitting}>
          <Save className="h-4 w-4" />
          Save
        </Button>
      </div>
    </form>
  );
}
