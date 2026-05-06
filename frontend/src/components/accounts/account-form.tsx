"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Save } from "lucide-react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

import type {
  Account,
  AccountCreatePayload,
  AccountUpdatePayload,
} from "@/types/api";

// ✅ FIXED TYPES (backend aligned)
const accountTypes = [
  { value: "cash", label: "Cash" },
  { value: "bank", label: "Bank" },
  { value: "card", label: "Card" },
] as const;

const schema = z.object({
  name: z.string().min(1, "Account name is required").max(120),

  // ✅ FIX
  type: z.enum(["cash", "bank", "card"]),

  opening_balance: z.coerce
    .number()
    .min(0, "Opening balance cannot be negative"),

  currency: z.string().min(3, "Use 3-letter code").max(3, "Use 3-letter code"),

  notes: z.string().optional(),
  is_active: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

type Props = {
  account?: Account | null;
  onSubmit: (
    data: AccountCreatePayload | AccountUpdatePayload,
  ) => Promise<void>;
  onCancel: () => void;
};

export function AccountForm({ account, onSubmit, onCancel }: Props) {
  const isEditing = Boolean(account);

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),

    defaultValues: {
      name: account?.name ?? "",
      type: account?.type ?? "cash",

      // ✅ FIX (use balance)
      opening_balance: Number(account?.balance ?? 0),

      currency: account?.currency ?? "USD",
      notes: account?.notes ?? "",
      is_active: account?.is_active ?? true,
    },
  });

  async function submit(values: FormValues) {
    const payload = {
      ...values,
      currency: values.currency.toUpperCase(),
      notes: values.notes?.trim() || null,
    };

    if (isEditing) {
      // ✅ FIX: opening_balance NOT sent in update
      const updatePayload: AccountUpdatePayload = {
        name: payload.name,
        type: payload.type,
        currency: payload.currency,
        notes: payload.notes,
        is_active: payload.is_active,
      };

      await onSubmit(updatePayload);
      return;
    }

    await onSubmit(payload);
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit(submit)}>
      {/* NAME */}
      <Input
        label="Account name"
        error={errors.name?.message}
        {...register("name")}
      />

      {/* TYPE */}
      <label className="block">
        <span className="mb-2 block text-sm font-medium">Account type</span>

        <select className="input" {...register("type")}>
          {accountTypes.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
      </label>

      {/* BALANCE + CURRENCY */}
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

        <Input
          label="Currency"
          maxLength={3}
          error={errors.currency?.message}
          {...register("currency")}
        />
      </div>

      {/* NOTES */}
      <label className="block">
        <span className="mb-2 block text-sm font-medium">Notes</span>

        <textarea className="input" {...register("notes")} />
      </label>

      {/* ACTIVE */}
      <label className="flex items-center gap-2">
        <input type="checkbox" {...register("is_active")} />
        Active account
      </label>

      {/* ACTIONS */}
      <div className="flex justify-end gap-3">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>

        <Button type="submit" disabled={isSubmitting}>
          <Save className="w-4 h-4" />
          {isSubmitting ? "Saving..." : "Save"}
        </Button>
      </div>
    </form>
  );
}
