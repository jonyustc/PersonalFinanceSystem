"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { CreditCard, Landmark, Palette, Save, Smartphone, Wallet } from "lucide-react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

import type {
  Account,
  AccountCreatePayload,
  AccountUpdatePayload,
} from "@/types/api";

const accountTypes = [
  { value: "cash", label: "Cash", icon: Wallet },
  { value: "bank", label: "Bank", icon: Landmark },
  { value: "mobile_banking", label: "Mobile", icon: Smartphone },
  { value: "debit_card", label: "Debit", icon: CreditCard },
  { value: "credit_card", label: "Credit", icon: CreditCard },
] as const;

const iconOptions = ["wallet", "landmark", "credit-card", "piggy-bank", "building-2"];
const colorOptions = ["#137f65", "#2563eb", "#7c3aed", "#d97706", "#dc2626", "#0f766e"];

function normalizeFormType(type?: Account["type"]): FormValues["type"] {
  const value = type?.toLowerCase();
  if (value === "card" || value === "credit_card") return "credit_card";
  if (value === "debit_card") return "debit_card";
  if (value === "mobile_banking") return "mobile_banking";
  if (value === "bank") return "bank";
  return "cash";
}

const schema = z
  .object({
    name: z.string().min(1, "Account name is required").max(120),
    type: z.enum(["cash", "bank", "mobile_banking", "debit_card", "credit_card"]),
    opening_balance: z.coerce.number(),
    currency: z.string().min(3, "Use 3-letter code").max(3, "Use 3-letter code"),
    institution_name: z.string().max(120).optional(),
    account_subtype: z.string().max(30).optional(),
    color: z.string().optional(),
    icon: z.string().optional(),
    notes: z.string().optional(),
    is_active: z.boolean(),
    credit_limit: z.coerce.number().min(0).optional(),
    statement_day: z.coerce.number().min(1).max(31).optional().or(z.literal("").transform(() => undefined)),
    due_day: z.coerce.number().min(1).max(31).optional().or(z.literal("").transform(() => undefined)),
  })
  .superRefine((values, ctx) => {
    if (values.type !== "credit_card" && values.opening_balance < 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["opening_balance"],
        message: "Only cards can start with a negative balance",
      });
    }
  });

type FormInput = z.input<typeof schema>;
type FormValues = z.output<typeof schema>;

type Props = {
  account?: Account | null;
  onSubmit: (data: AccountCreatePayload | AccountUpdatePayload) => Promise<void>;
  onCancel: () => void;
};

export function AccountForm({ account, onSubmit, onCancel }: Props) {
  const isEditing = Boolean(account);
  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<FormInput, any, FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: account?.name ?? "",
      type: normalizeFormType(account?.type),
      opening_balance: Number(account?.opening_balance ?? account?.balance ?? 0),
      currency: account?.currency ?? "BDT",
      institution_name: account?.institution_name ?? "",
      account_subtype: account?.account_subtype ?? "",
      color: account?.color ?? colorOptions[0],
      icon: account?.icon ?? "wallet",
      notes: account?.notes ?? "",
      is_active: account?.is_active ?? true,
      credit_limit: Number(account?.credit_limit ?? account?.card_details?.credit_limit ?? 0),
      statement_day: account?.billing_cycle_day ?? account?.card_details?.statement_day ?? undefined,
      due_day: account?.payment_due_day ?? account?.card_details?.due_day ?? undefined,
    },
  });

  const selectedType = watch("type");

  async function submit(values: FormValues) {
    const basePayload = {
      name: values.name.trim(),
      type: values.type,
      currency: values.currency.toUpperCase(),
      institution_name: values.institution_name?.trim() || null,
      account_subtype: values.account_subtype?.trim() || null,
      color: values.color || null,
      icon: values.icon || null,
      notes: values.notes?.trim() || null,
      is_active: values.is_active,
      credit_limit: values.type === "credit_card" ? Number(values.credit_limit ?? 0) : null,
      billing_cycle_day: values.type === "credit_card" && values.statement_day ? Number(values.statement_day) : null,
      payment_due_day: values.type === "credit_card" && values.due_day ? Number(values.due_day) : null,
      card_details:
        values.type === "credit_card"
          ? {
              credit_limit: Number(values.credit_limit ?? 0),
              statement_day: values.statement_day ? Number(values.statement_day) : null,
              due_day: values.due_day ? Number(values.due_day) : null,
            }
          : null,
      opening_balance: values.opening_balance,
    };
    await onSubmit(basePayload);
  }

  return (
    <form className="space-y-5" onSubmit={handleSubmit(submit)}>
      <Input label="Account name" error={errors.name?.message} {...register("name")} />

      <div>
        <span className="mb-2 block text-sm font-medium text-ink">Account type</span>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
          {accountTypes.map((type) => {
            const Icon = type.icon;
            const active = selectedType === type.value;
            return (
              <label
                key={type.value}
                className={cn(
                  "flex h-11 cursor-pointer items-center justify-center gap-2 rounded-md border text-sm font-semibold",
                  active ? "border-brand-600 bg-brand-50 text-brand-700" : "border-line bg-card text-muted",
                )}
              >
                <input className="sr-only" type="radio" value={type.value} {...register("type")} />
                <Icon className="h-4 w-4" />
                {type.label}
              </label>
            );
          })}
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Input
          label={selectedType === "credit_card" ? "Opening available limit" : "Opening balance"}
          type="number"
          step="0.01"
          error={errors.opening_balance?.message}
          {...register("opening_balance")}
        />
        <Input label="Currency" maxLength={3} error={errors.currency?.message} {...register("currency")} />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Input label="Institution" {...register("institution_name")} />
        <Input label="Subtype" placeholder="Checking, savings, rewards" {...register("account_subtype")} />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-2 flex items-center gap-2 text-sm font-medium text-ink">
            <Palette className="h-4 w-4" />
            Color
          </span>
          <select className="input h-11" {...register("color")}>
            {colorOptions.map((color) => (
              <option key={color} value={color}>
                {color}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Icon</span>
          <select className="input h-11" {...register("icon")}>
            {iconOptions.map((icon) => (
              <option key={icon} value={icon}>
                {icon}
              </option>
            ))}
          </select>
        </label>
      </div>

      {selectedType === "credit_card" ? (
        <div className="grid gap-4 rounded-md border border-line bg-surface p-4 sm:grid-cols-3">
          <Input label="Credit limit" type="number" step="0.01" min="0" {...register("credit_limit")} />
          <Input label="Statement day" type="number" min="1" max="31" error={errors.statement_day?.message} {...register("statement_day")} />
          <Input label="Due day" type="number" min="1" max="31" error={errors.due_day?.message} {...register("due_day")} />
        </div>
      ) : null}

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Notes</span>
        <textarea className="input min-h-24" {...register("notes")} />
      </label>

      <label className="flex items-center gap-2 text-sm font-medium text-ink">
        <input type="checkbox" {...register("is_active")} />
        Active account
      </label>

      <div className="flex justify-end gap-3">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          <Save className="h-4 w-4" />
          {isSubmitting ? "Saving..." : "Save"}
        </Button>
      </div>
    </form>
  );
}
