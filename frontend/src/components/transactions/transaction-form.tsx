"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Save } from "lucide-react";
import { useMemo } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { Account, Category, Transaction, TransactionCreatePayload, TransactionUpdatePayload } from "@/types/api";

const schema = z.object({
  txn_type: z.enum(["income", "expense"]),
  account_id: z.string().min(1, "Choose an account"),
  category_id: z.string().min(1, "Choose a category"),
  amount: z.coerce.number().gt(0, "Amount must be greater than zero"),
  txn_date: z.string().min(1, "Choose a date"),
  description: z.string().optional(),
  tags: z.string().optional()
});

type FormValues = z.infer<typeof schema>;

type TransactionFormProps = {
  transaction?: Transaction | null;
  accounts: Account[];
  categories: Category[];
  defaultType?: "income" | "expense";
  onSubmit: (payload: TransactionCreatePayload | TransactionUpdatePayload) => Promise<void>;
  onCancel: () => void;
};

function toDateTimeLocal(value?: string) {
  const date = value ? new Date(value) : new Date();
  const offsetMs = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offsetMs).toISOString().slice(0, 16);
}

export function TransactionForm({
  transaction,
  accounts,
  categories,
  defaultType = "expense",
  onSubmit,
  onCancel
}: TransactionFormProps) {
  const isEditing = Boolean(transaction);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isSubmitting }
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      txn_type: transaction?.txn_type === "income" ? "income" : transaction?.txn_type === "expense" ? "expense" : defaultType,
      account_id: transaction?.account_id ?? "",
      category_id: transaction?.category_id ?? "",
      amount: Number(transaction?.amount ?? 0),
      txn_date: toDateTimeLocal(transaction?.txn_date),
      description: transaction?.description ?? "",
      tags: transaction?.tags?.join(", ") ?? ""
    }
  });

  const selectedType = useWatch({ control, name: "txn_type" });
  const filteredCategories = useMemo(
    () => categories.filter((category) => category.type === selectedType),
    [categories, selectedType]
  );

  async function submit(values: FormValues) {
    const payload: TransactionCreatePayload = {
      account_id: values.account_id,
      category_id: values.category_id,
      transfer_account_id: null,
      txn_type: values.txn_type,
      amount: values.amount,
      txn_date: new Date(values.txn_date).toISOString(),
      description: values.description?.trim() ? values.description.trim() : null,
      tags: values.tags
        ? values.tags
            .split(",")
            .map((tag) => tag.trim())
            .filter(Boolean)
        : []
    };
    await onSubmit(payload);
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit(submit)}>
      <div className="grid grid-cols-2 gap-2 rounded-md bg-surface p-1">
        <label className="cursor-pointer">
          <input className="peer sr-only" type="radio" value="expense" {...register("txn_type")} />
          <span className="block rounded-md px-3 py-2 text-center text-sm font-semibold text-muted peer-checked:bg-white peer-checked:text-ink peer-checked:shadow-sm">
            Expense
          </span>
        </label>
        <label className="cursor-pointer">
          <input className="peer sr-only" type="radio" value="income" {...register("txn_type")} />
          <span className="block rounded-md px-3 py-2 text-center text-sm font-semibold text-muted peer-checked:bg-white peer-checked:text-ink peer-checked:shadow-sm">
            Income
          </span>
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Account</span>
          <select
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            {...register("account_id")}
          >
            <option value="">Select account</option>
            {accounts.map((account) => (
              <option key={account.id} value={account.id}>
                {account.name}
              </option>
            ))}
          </select>
          {errors.account_id ? <span className="mt-1 block text-xs text-red-600">{errors.account_id.message}</span> : null}
        </label>

        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Category</span>
          <select
            className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            {...register("category_id")}
          >
            <option value="">Select category</option>
            {filteredCategories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
          {errors.category_id ? <span className="mt-1 block text-xs text-red-600">{errors.category_id.message}</span> : null}
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Input label="Amount" type="number" min="0.01" step="0.01" error={errors.amount?.message} {...register("amount")} />
        <Input label="Date" type="datetime-local" error={errors.txn_date?.message} {...register("txn_date")} />
      </div>

      <Input label="Description" error={errors.description?.message} {...register("description")} />
      <Input label="Tags" placeholder="food, salary, bills" error={errors.tags?.message} {...register("tags")} />

      {!accounts.length || !filteredCategories.length ? (
        <p className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">
          Add at least one account and one {selectedType} category before saving.
        </p>
      ) : null}

      <div className="flex justify-end gap-3 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={isSubmitting || !accounts.length || !filteredCategories.length}>
          <Save className="h-4 w-4" aria-hidden />
          {isSubmitting ? "Saving..." : isEditing ? "Save changes" : "Add transaction"}
        </Button>
      </div>
    </form>
  );
}
