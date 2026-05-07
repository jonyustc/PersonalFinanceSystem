"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowLeftRight, Save } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn, formatCurrency } from "@/lib/utils";
import { CategoryTreeSelect } from "./category-tree-select";

import type { Account, Category, TransactionCreatePayload } from "@/types/api";

const schema = z
  .object({
    type: z.enum(["income", "expense", "transfer"]),
    account_id: z.string().min(1, "Account required"),
    transfer_account_id: z.string().optional(),
    category_id: z.string().optional(),
    payment_method: z.string().optional(),
    amount: z.coerce.number().gt(0, "Amount required"),
    txn_date: z.string(),
    merchant_name: z.string().optional(),
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
  recentMerchants?: string[];
  quickCategories?: Category[];
  autoFocusAmount?: boolean;
  onSubmit: (payload: TransactionCreatePayload) => Promise<void>;
  onCancel: () => void;
};

export function TransactionForm({
  accounts,
  categories,
  transaction,
  selectedDate,
  recentMerchants = [],
  quickCategories = [],
  autoFocusAmount = false,
  onSubmit,
  onCancel,
}: Props) {
  const [localCategories, setLocalCategories] = useState<Category[]>([]);
  const amountRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    setLocalCategories(categories || []);
  }, [categories]);

  const {
    register,
    handleSubmit,
    control,
    setValue,
    watch,
    formState: { errors, isSubmitting },
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
      merchant_name: transaction?.merchant_name ?? "",
      is_emergency: transaction?.is_emergency ?? false,
      description: transaction?.description ?? "",
    },
  });

  const type = useWatch({ control, name: "type" });
  const amount = useWatch({ control, name: "amount" });
  const merchantName = useWatch({ control, name: "merchant_name" });
  const categoryId = useWatch({ control, name: "category_id" });
  const fromId = useWatch({ control, name: "account_id" });
  const toId = useWatch({ control, name: "transfer_account_id" });

  const isTransfer = type === "transfer";

  useEffect(() => {
    if (autoFocusAmount && amountRef.current) {
      amountRef.current.focus();
    }
  }, [autoFocusAmount]);

  useEffect(() => {
    if (!transaction && accounts.length && !watch("account_id")) {
      setValue("account_id", accounts[0].id);
    }
  }, [accounts, transaction, setValue, watch]);

  useEffect(() => {
    if (type === "transfer") {
      setValue("category_id", "");
    } else {
      setValue("transfer_account_id", "");
    }
  }, [type, setValue]);

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

  let previewFrom = fromBalance;
  let previewTo = toBalance;

  if (amount > 0) {
    if (type === "expense") {
      previewFrom = fromBalance - amount;
    }

    if (type === "transfer") {
      if (!isFromCard && isToCard) {
        previewFrom = fromBalance - amount;
        previewTo = toBalance + amount;
      } else if (isFromCard && !isToCard) {
        previewFrom = fromBalance - amount;
        previewTo = toBalance + amount;
      } else {
        previewFrom = fromBalance - amount;
        previewTo = toBalance + amount;
      }
    }
  }

  const insufficient =
    !isFromCard &&
    (type === "expense" || isTransfer) &&
    amount > 0 &&
    fromBalance < amount;

  function handleSwap() {
    const from = watch("account_id");
    const to = watch("transfer_account_id");

    setValue("account_id", to || "");
    setValue("transfer_account_id", from || "");
  }

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
      merchant_name: values.merchant_name || null,
      is_emergency: values.is_emergency || false,
      description: values.description || null,
    });
  }

  return (
    <form onSubmit={handleSubmit(submit)} className="space-y-5">
      <div className="grid grid-cols-3 gap-2">
        {(["expense", "income", "transfer"] as const).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setValue("type", option)}
            className={cn(
              "rounded-2xl border px-3 py-3 text-sm font-semibold transition",
              type === option
                ? "border-brand-600 bg-brand-600 text-white"
                : "border-line bg-white text-slate-600 hover:bg-slate-50",
            )}
          >
            {option}
          </button>
        ))}
      </div>

      <div className="rounded-3xl border border-slate-200 bg-slate-50 p-4">
        <label className="block text-sm font-medium text-slate-500">
          Amount
        </label>
        <div className="mt-3 flex items-end gap-3">
          <span className="text-3xl font-semibold text-slate-900">
            {amount ? formatCurrency(amount) : "$0.00"}
          </span>
          <input
            ref={amountRef}
            type="number"
            step="0.01"
            inputMode="decimal"
            placeholder="0.00"
            className="min-w-[130px] flex-1 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-3xl font-semibold text-slate-900 outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100"
            {...register("amount", { valueAsNumber: true })}
          />
        </div>
        {errors.amount && (
          <p className="mt-2 text-sm text-red-600">{errors.amount.message}</p>
        )}
      </div>

      {quickCategories.length > 0 ? (
        <div className="space-y-2">
          <p className="text-sm font-semibold text-slate-900">
            Quick categories
          </p>
          <div className="flex flex-wrap gap-2">
            {quickCategories.map((category) => (
              <button
                key={category.id}
                type="button"
                onClick={() => setValue("category_id", category.id)}
                className={cn(
                  "rounded-full border px-3 py-2 text-sm transition",
                  categoryId === category.id
                    ? "border-brand-600 bg-brand-50 text-brand-700"
                    : "border-line bg-white text-slate-600 hover:bg-slate-50",
                )}
              >
                {category.name}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      {recentMerchants.length > 0 ? (
        <div className="space-y-2">
          <p className="text-sm font-semibold text-slate-900">
            Recent merchants
          </p>
          <div className="flex flex-wrap gap-2">
            {recentMerchants.map((merchant) => (
              <button
                key={merchant}
                type="button"
                onClick={() => setValue("merchant_name", merchant)}
                className="rounded-full border border-line bg-white px-3 py-2 text-sm text-slate-600 hover:border-slate-300"
              >
                {merchant}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <div className="space-y-2">
        <Input
          label="Merchant"
          placeholder="Payee or merchant"
          {...register("merchant_name")}
          value={merchantName}
          onChange={(event) => setValue("merchant_name", event.target.value)}
          error={errors.merchant_name?.message}
        />
      </div>

      <div className="bg-gray-50 p-3 rounded-lg space-y-2">
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
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

      {!isTransfer && (
        <CategoryTreeSelect
          categories={localCategories}
          type={type}
          value={categoryId}
          onChange={(id: string) =>
            setValue("category_id", id, { shouldDirty: true })
          }
          onCreated={(cat: Category) =>
            setLocalCategories((prev) => [...prev, cat])
          }
        />
      )}

      <Input label="Date" type="datetime-local" {...register("txn_date")} />

      <select {...register("payment_method")} className="input">
        <option value="">Payment</option>
        <option value="cash">Cash</option>
        <option value="bank">Bank</option>
        <option value="card">Card</option>
      </select>

      <Input
        label="Note"
        placeholder="Add a short memo"
        {...register("description")}
      />

      <div className="flex justify-end gap-2">
        <Button type="button" onClick={onCancel} variant="secondary">
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
