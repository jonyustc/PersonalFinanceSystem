"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowRightLeft, Send } from "lucide-react";
import { useEffect } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { formatCurrency } from "@/lib/utils";

import type { Account, TransferPayload } from "@/types/api";

const schema = z
  .object({
    from_account_id: z.string().min(1, "Choose a source account"),
    to_account_id: z.string().min(1, "Choose a destination account"),
    amount: z.coerce.number().positive("Amount must be greater than zero"),
    fee: z.coerce.number().min(0, "Fee cannot be negative"),
    is_card_payment: z.boolean().optional(),
    notes: z.string().optional(),
  })
  .refine((values) => values.from_account_id !== values.to_account_id, {
    path: ["to_account_id"],
    message: "Choose a different destination",
  });

type FormValues = z.infer<typeof schema>;

type Props = {
  accounts: Account[];
  onSubmit: (payload: TransferPayload) => Promise<void>;
  onCancel: () => void;
};

export function TransferModal({ accounts, onSubmit, onCancel }: Props) {
  const activeAccounts = accounts.filter((account) => account.is_active && !account.archived);
  const {
    register,
    handleSubmit,
    control,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { fee: 0, is_card_payment: false },
  });

  const toAccountId = useWatch({ control, name: "to_account_id" });
  const toAccount = activeAccounts.find((account) => account.id === toAccountId);
  const isCreditCardDestination =
    toAccount?.type?.toLowerCase() === "card" || toAccount?.type?.toLowerCase() === "credit_card";

  useEffect(() => {
    setValue("is_card_payment", Boolean(isCreditCardDestination));
  }, [isCreditCardDestination, setValue]);

  async function submit(values: FormValues) {
    await onSubmit({
      from_account_id: values.from_account_id,
      to_account_id: values.to_account_id,
      amount: values.amount,
      fee: values.fee,
      is_card_payment: Boolean(values.is_card_payment && isCreditCardDestination),
      notes: values.notes?.trim() || null,
    });
  }

  return (
    <form className="space-y-5" onSubmit={handleSubmit(submit)}>
      <div className="rounded-md border border-line bg-surface p-4">
        <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-ink">
          <ArrowRightLeft className="h-4 w-4" />
          Move money between accounts
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">From</span>
            <select className="input h-11" {...register("from_account_id")}>
              <option value="">Select account</option>
              {activeAccounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name} - {formatCurrency(account.balance, account.currency)}
                </option>
              ))}
            </select>
            {errors.from_account_id ? <span className="mt-1 block text-xs text-red-600">{errors.from_account_id.message}</span> : null}
          </label>

          <label className="block">
            <span className="mb-2 block text-sm font-medium text-ink">To</span>
            <select className="input h-11" {...register("to_account_id")}>
              <option value="">Select account</option>
              {activeAccounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name} - {formatCurrency(account.balance, account.currency)}
                </option>
              ))}
            </select>
            {errors.to_account_id ? <span className="mt-1 block text-xs text-red-600">{errors.to_account_id.message}</span> : null}
          </label>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Input label="Amount" type="number" step="0.01" min="0.01" error={errors.amount?.message} {...register("amount")} />
        <Input label="Fee" type="number" step="0.01" min="0" error={errors.fee?.message} {...register("fee")} />
      </div>

      <label className="block">
        <span className="mb-2 block text-sm font-medium text-ink">Notes</span>
        <textarea className="input min-h-24" {...register("notes")} />
      </label>

      {isCreditCardDestination ? (
        <label className="flex items-start gap-3 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          <input className="mt-1" type="checkbox" {...register("is_card_payment")} />
          <span>
            Treat this transfer as a credit card payment. This reduces card outstanding instead of increasing the card balance.
          </span>
        </label>
      ) : null}

      <div className="flex justify-end gap-3">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          <Send className="h-4 w-4" />
          {isSubmitting ? "Transferring..." : "Transfer"}
        </Button>
      </div>
    </form>
  );
}
