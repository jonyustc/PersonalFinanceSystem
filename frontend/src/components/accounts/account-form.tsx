"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Save } from "lucide-react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { Account, AccountCreatePayload, AccountType, AccountUpdatePayload } from "@/types/api";

const accountTypes: { value: AccountType; label: string }[] = [
  { value: "cash", label: "Cash wallet" },
  { value: "bank", label: "Bank account" },
  { value: "debit_card", label: "Debit card" },
  { value: "credit_card", label: "Credit card" },
  { value: "mobile_banking", label: "Mobile banking" }
];

const schema = z.object({
  name: z.string().min(1, "Account name is required").max(120),
  type: z.enum(["cash", "bank", "debit_card", "credit_card", "mobile_banking"]),
  opening_balance: z.coerce.number().min(0, "Opening balance cannot be negative"),
  currency: z.string().min(3, "Use a 3-letter code").max(3, "Use a 3-letter code"),
  notes: z.string().optional(),
  is_active: z.boolean()
});

type FormValues = z.infer<typeof schema>;

type AccountFormProps = {
  account?: Account | null;
  onSubmit: (payload: AccountCreatePayload | AccountUpdatePayload) => Promise<void>;
  onCancel: () => void;
};

export function AccountForm({ account, onSubmit, onCancel }: AccountFormProps) {
  const isEditing = Boolean(account);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting }
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: account?.name ?? "",
      type: account?.type ?? "cash",
      opening_balance: Number(account?.opening_balance ?? 0),
      currency: account?.currency ?? "USD",
      notes: account?.notes ?? "",
      is_active: account?.is_active ?? true
    }
  });

  async function submit(values: FormValues) {
    const payload = {
      ...values,
      currency: values.currency.toUpperCase(),
      notes: values.notes?.trim() ? values.notes.trim() : null
    };

    if (isEditing) {
      const updatePayload: AccountUpdatePayload = {
        name: payload.name,
        type: payload.type,
        currency: payload.currency,
        notes: payload.notes,
        is_active: payload.is_active
      };
      await onSubmit(updatePayload);
      return;
    }

    await onSubmit(payload);
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit(submit)}>
      <Input label="Account name" error={errors.name?.message} {...register("name")} />

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Account type</span>
        <select
          className="h-11 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          {...register("type")}
        >
          {accountTypes.map((type) => (
            <option key={type.value} value={type.value}>
              {type.label}
            </option>
          ))}
        </select>
      </label>

      <div className="grid gap-4 sm:grid-cols-2">
        <Input
          label="Opening balance"
          type="number"
          step="0.01"
          min="0"
          disabled={isEditing}
          error={errors.opening_balance?.message}
          {...register("opening_balance")}
        />
        <Input label="Currency" maxLength={3} error={errors.currency?.message} {...register("currency")} />
      </div>

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Notes</span>
        <textarea
          className="min-h-24 w-full rounded-md border border-line bg-white px-3 py-2 text-sm outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
          {...register("notes")}
        />
      </label>

      <label className="flex items-center gap-2 text-sm font-medium text-ink">
        <input className="h-4 w-4 rounded border-line text-brand-600" type="checkbox" {...register("is_active")} />
        Active account
      </label>

      <div className="flex justify-end gap-3 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          <Save className="h-4 w-4" aria-hidden />
          {isSubmitting ? "Saving..." : "Save account"}
        </Button>
      </div>
    </form>
  );
}
