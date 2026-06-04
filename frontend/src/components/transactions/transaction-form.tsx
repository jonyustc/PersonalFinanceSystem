"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowLeftRight, CalendarDays, ChevronDown, ChevronUp, Save } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { cn, formatCurrency } from "@/lib/utils";
import { fetchTransactions } from "@/services/finance-service";
import { CategoryTreeSelect } from "./category-tree-select";

import type { Account, Category, Transaction, TransactionCreatePayload } from "@/types/api";

function normalizedAccountType(account?: Account) {
  return account?.type?.toLowerCase() ?? "";
}

function isCreditCard(account?: Account) {
  const type = normalizedAccountType(account);
  return type === "card" || type === "credit_card";
}

function accountOptionBalance(account: Account) {
  if (isCreditCard(account)) {
    return `${formatCurrency(account.current_outstanding ?? 0, account.currency)} outstanding`;
  }
  return formatCurrency(account.balance, account.currency);
}

function evaluateAmountExpression(value: string) {
  const expression = value.trim();
  if (!expression) return 0;
  if (!/^[\d\s+\-*/().]+$/.test(expression)) return Number.NaN;
  try {
    const result = Function(`"use strict"; return (${expression})`)();
    return Number.isFinite(result) ? Number(result.toFixed(2)) : Number.NaN;
  } catch {
    return Number.NaN;
  }
}

function localDateTimeParts(value: string) {
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) {
    return { date: value.slice(0, 10), time: value.slice(11, 16) };
  }
  const fallback = new Date();
  const date = value ? new Date(value) : fallback;
  const safeDate = Number.isNaN(date.getTime()) ? fallback : date;
  return {
    date: toLocalDateInputValue(safeDate),
    time: safeDate.toTimeString().slice(0, 5),
  };
}

function combineLocalDateTime(date: string, time: string) {
  return `${date}T${time || "12:00"}`;
}

function toLocalDateInputValue(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function displayDate(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

const schema = z
  .object({
    type: z.enum(["income", "expense", "transfer"]),
    account_id: z.string().min(1, "Account required"),
    transfer_account_id: z.string().optional(),
    category_id: z.string().optional(),
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

type FormInput = z.input<typeof schema>;
type FormValues = z.output<typeof schema>;

type Props = {
  accounts: Account[];
  categories: Category[];
  transaction?: any;
  selectedDate: string;
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
  quickCategories = [],
  autoFocusAmount = false,
  onSubmit,
  onCancel,
}: Props) {
  const [localCategories, setLocalCategories] = useState<Category[]>([]);
  const [amountExpression, setAmountExpression] = useState(String(transaction?.amount ?? ""));
  const [calculatorOpen, setCalculatorOpen] = useState(autoFocusAmount);
  const [noteOpen, setNoteOpen] = useState(Boolean(transaction?.description));
  const [noteSuggestions, setNoteSuggestions] = useState<string[]>([]);
  const amountRef = useRef<HTMLInputElement | null>(null);
  const calculatorRef = useRef<HTMLDivElement | null>(null);
  const lastAutoNoteRef = useRef("");

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
  } = useForm<FormInput, any, FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      type: transaction?.type ?? "expense",
      account_id: transaction?.account_id ?? "",
      transfer_account_id: transaction?.transfer_account_id ?? "",
      category_id: transaction?.category_id ?? "",
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
  const amountNumber = Number(amount || 0);
  const categoryId = useWatch({ control, name: "category_id" });
  const description = useWatch({ control, name: "description" });
  const fromId = useWatch({ control, name: "account_id" });
  const toId = useWatch({ control, name: "transfer_account_id" });
  const txnDate = useWatch({ control, name: "txn_date" });
  const dateParts = localDateTimeParts(txnDate);

  const isTransfer = type === "transfer";
  const activeAccounts = useMemo(
    () => accounts.filter((account) => account.is_active && !account.archived),
    [accounts],
  );

  useEffect(() => {
    if (autoFocusAmount && amountRef.current) {
      amountRef.current.focus();
      setCalculatorOpen(true);
    }
  }, [autoFocusAmount]);

  useEffect(() => {
    if (!calculatorOpen) return;

    function handleOutsideClick(event: MouseEvent) {
      const target = event.target as Node;
      const insideAmountInput = amountRef.current?.contains(target);
      const insideCalculator = calculatorRef.current?.contains(target);

      if (!insideAmountInput && !insideCalculator) {
        applyAmountExpression();
        setCalculatorOpen(false);
      }
    }

    document.addEventListener("mousedown", handleOutsideClick);
    return () => document.removeEventListener("mousedown", handleOutsideClick);
  }, [calculatorOpen, amountExpression]);

  useEffect(() => {
    if (!transaction && activeAccounts.length && !watch("account_id")) {
      setValue("account_id", activeAccounts[0].id);
    }
  }, [activeAccounts, transaction, setValue, watch]);

  useEffect(() => {
    if (type !== "transfer") {
      setValue("transfer_account_id", "");
    }
  }, [type, setValue]);

  const fromAccount = useMemo(
    () => activeAccounts.find((a) => a.id === fromId),
    [activeAccounts, fromId],
  );

  const toAccount = useMemo(
    () => activeAccounts.find((a) => a.id === toId),
    [activeAccounts, toId],
  );

  const isFromCreditCard = isCreditCard(fromAccount);
  const isToCreditCard = isCreditCard(toAccount);
  const isCardPayment = isTransfer && isToCreditCard && !isFromCreditCard;
  const isCardSpendingTransfer = isTransfer && isFromCreditCard && !isToCreditCard;
  const isExpenseLikeTransfer = isCardPayment || isCardSpendingTransfer;
  const categoryType = isExpenseLikeTransfer ? "expense" : type;

  const selectedCategory = useMemo(
    () => localCategories.find((category) => category.id === categoryId),
    [localCategories, categoryId],
  );

  const selectedParentCategory = useMemo(
    () =>
      selectedCategory?.parent_id
        ? localCategories.find((category) => category.id === selectedCategory.parent_id)
        : null,
    [localCategories, selectedCategory],
  );

  const autoNote = useMemo(() => {
    if (!selectedCategory) return "";
    return selectedParentCategory
      ? `${selectedParentCategory.name} - ${selectedCategory.name}`
      : selectedCategory.name;
  }, [selectedCategory, selectedParentCategory]);

  useEffect(() => {
    if (!autoNote || (isTransfer && !isExpenseLikeTransfer)) return;
    const currentNote = description?.trim() ?? "";
    if (!currentNote || currentNote === lastAutoNoteRef.current) {
      setValue("description", autoNote, { shouldDirty: true });
      setNoteOpen(true);
      lastAutoNoteRef.current = autoNote;
    }
  }, [autoNote, description, isTransfer, isExpenseLikeTransfer, setValue]);

  useEffect(() => {
    if (!categoryId || (isTransfer && !isExpenseLikeTransfer)) {
      setNoteSuggestions([]);
      return;
    }

    let active = true;
    fetchTransactions({ category_id: categoryId, type: categoryType, limit: 50 })
      .then((response) => {
        if (!active) return;
        const suggestions = Array.from(
          new Set(
            response.items
              .map((item: Transaction) => item.description?.trim())
              .filter((note): note is string => Boolean(note)),
          ),
        )
          .filter((note) => note !== autoNote)
          .slice(0, 4);
        setNoteSuggestions(suggestions);
      })
      .catch(() => {
        if (active) setNoteSuggestions([]);
      });

    return () => {
      active = false;
    };
  }, [categoryId, categoryType, isTransfer, isExpenseLikeTransfer, autoNote]);

  const fromBalance = Number(fromAccount?.balance || 0);
  const toBalance = Number(toAccount?.balance || 0);
  const fromOutstanding = Number(fromAccount?.current_outstanding ?? 0);
  const toOutstanding = Number(toAccount?.current_outstanding ?? 0);

  let previewFrom = fromBalance;
  let previewTo = toBalance;
  let previewFromOutstanding = fromOutstanding;
  let previewToOutstanding = toOutstanding;

  if (amountNumber > 0) {
    if (type === "expense") {
      if (isFromCreditCard) {
        previewFromOutstanding = fromOutstanding + amountNumber;
      } else {
        previewFrom = fromBalance - amountNumber;
      }
    }

    if (type === "transfer") {
      if (isCardPayment) {
        previewFrom = fromBalance - amountNumber;
        previewToOutstanding = Math.max(toOutstanding - amountNumber, 0);
      } else if (isCardSpendingTransfer) {
        previewFromOutstanding = fromOutstanding + amountNumber;
        previewTo = toBalance + amountNumber;
      } else {
        previewFrom = fromBalance - amountNumber;
        previewTo = toBalance + amountNumber;
      }
    }
  }

  const insufficient =
    !isFromCreditCard &&
    (type === "expense" || isTransfer) &&
    amountNumber > 0 &&
    fromBalance < amountNumber;

  function handleSwap() {
    const from = watch("account_id");
    const to = watch("transfer_account_id");

    setValue("account_id", to || "");
    setValue("transfer_account_id", from || "");
  }

  const amountRegistration = register("amount", { valueAsNumber: true });

  function applyAmountExpression(nextExpression = amountExpression) {
    const result = evaluateAmountExpression(nextExpression);
    if (Number.isFinite(result) && result > 0) {
      setValue("amount", result, { shouldDirty: true, shouldValidate: true });
      setAmountExpression(String(result));
    }
  }

  function appendCalculatorToken(token: string) {
    const next = token === "clear" ? "" : `${amountExpression}${token}`;
    setAmountExpression(next);
    if (token === "clear") {
      setValue("amount", 0, { shouldDirty: true });
      return;
    }
    const result = evaluateAmountExpression(next);
    if (Number.isFinite(result) && result > 0) {
      setValue("amount", result, { shouldDirty: true, shouldValidate: true });
    }
  }

  function setQuickDate(daysOffset: number) {
    const date = new Date();
    date.setDate(date.getDate() + daysOffset);
    setValue("txn_date", combineLocalDateTime(toLocalDateInputValue(date), dateParts.time), {
      shouldDirty: true,
    });
  }

  function nudgeDate(days: number) {
    const [year, month, day] = dateParts.date.split("-").map(Number);
    const date = new Date(year, month - 1, day);
    date.setDate(date.getDate() + days);
    setValue("txn_date", combineLocalDateTime(toLocalDateInputValue(date), dateParts.time), {
      shouldDirty: true,
    });
  }

  async function submit(values: FormValues) {
    await onSubmit({
      account_id: values.account_id,
      transfer_account_id:
        values.type === "transfer" ? values.transfer_account_id || null : null,
      category_id:
        values.type !== "transfer" || isExpenseLikeTransfer ? values.category_id || null : null,
      type: values.type,
      transaction_type: isCardPayment ? "CARD_PAYMENT" : isCardSpendingTransfer ? "CARD_SPENDING" : values.type,
      payment_method: null,
      amount: values.amount,
      txn_date: new Date(values.txn_date).toISOString(),
      merchant_name: null,
      is_emergency: values.is_emergency || false,
      description: values.description || null,
    });
  }

  return (
    <form onSubmit={handleSubmit(submit)} className="flex min-h-full flex-col gap-3 pb-16">
      <div className="grid grid-cols-3 gap-2">
        {(["expense", "income", "transfer"] as const).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setValue("type", option)}
            className={cn(
              "rounded-md border px-3 py-2 text-sm font-semibold capitalize transition",
              type === option
                ? "border-brand-600 bg-brand-600 text-white"
                : "border-line bg-white text-slate-600 hover:bg-slate-50",
            )}
          >
            {option}
          </button>
        ))}
      </div>

      <div className="relative rounded-md border border-slate-200 bg-slate-50 p-3">
        <div className="flex items-center justify-between gap-2">
          <span className="text-sm font-medium text-slate-500">Amount</span>
          <span className="text-xs font-semibold text-muted">
            Tap amount to {calculatorOpen ? "hide" : "calculate"}
          </span>
        </div>
        <div className="mt-2 flex items-center gap-3">
          <span className="min-w-[120px] text-2xl font-semibold text-slate-900">
            {amountNumber ? formatCurrency(amountNumber) : "$0.00"}
          </span>
          <input
            ref={amountRef}
            type="text"
            inputMode="decimal"
            placeholder="1200+250"
            value={amountExpression}
            onClick={() => setCalculatorOpen((current) => !current)}
            onBlur={() => applyAmountExpression()}
            onChange={(event) => {
              setAmountExpression(event.target.value);
              const result = evaluateAmountExpression(event.target.value);
              if (Number.isFinite(result) && result > 0) {
                setValue("amount", result, { shouldDirty: true, shouldValidate: true });
              }
            }}
            className="min-w-[120px] flex-1 rounded-md border border-slate-200 bg-white px-3 py-2 text-xl font-semibold text-slate-900 outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100"
          />
          <input
            className="sr-only"
            type="number"
            {...amountRegistration}
            ref={amountRegistration.ref}
          />
        </div>
        {calculatorOpen ? (
          <div ref={calculatorRef} className="absolute left-3 right-3 top-full z-50 mt-2 grid grid-cols-4 gap-2 rounded-md border border-line bg-white p-3 shadow-2xl">
            {["7", "8", "9", "/", "4", "5", "6", "*", "1", "2", "3", "-", "0", ".", "+", "clear"].map((token) => (
              <button
                key={token}
                type="button"
                onClick={() => appendCalculatorToken(token)}
                className={cn(
                  "h-10 rounded-md border border-line bg-surface text-sm font-semibold text-ink hover:bg-brand-50",
                  token === "clear" && "col-span-4 text-red-600",
                )}
              >
                {token === "clear" ? "Clear" : token}
              </button>
            ))}
          </div>
        ) : null}
        {errors.amount && (
          <p className="mt-2 text-sm text-red-600">{errors.amount.message}</p>
        )}
      </div>

      {quickCategories.length > 0 && (!isTransfer || isExpenseLikeTransfer) ? (
        <div className="space-y-2">
          <p className="text-xs font-semibold text-slate-900">
            Quick categories
          </p>
          <div className="flex flex-wrap gap-2">
            {quickCategories.map((category) => (
              <button
                key={category.id}
                type="button"
                onClick={() => setValue("category_id", category.id)}
                className={cn(
                  "rounded-full border px-3 py-1.5 text-xs transition",
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

      <div className="space-y-2 rounded-md bg-gray-50 p-3">
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <select {...register("account_id")} className="input">
            <option value="">From</option>
            {activeAccounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name} ({accountOptionBalance(a)})
              </option>
            ))}
          </select>

          {isTransfer && (
            <select {...register("transfer_account_id")} className="input">
              <option value="">To</option>
              {activeAccounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({accountOptionBalance(a)})
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

        {fromAccount && amountNumber > 0 && (
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

        {isCardPayment ? (
          <p className="text-amber-600 text-xs">
            This transfer will be saved as a card payment and reduce outstanding.
          </p>
        ) : null}

        {isCardSpendingTransfer ? (
          <p className="text-amber-600 text-xs">
            This transfer will be saved as card spending and outstanding will become {formatCurrency(previewFromOutstanding, fromAccount?.currency)}.
          </p>
        ) : null}

        {type === "expense" && isFromCreditCard ? (
          <p className="text-amber-600 text-xs">
            Card outstanding will become {formatCurrency(previewFromOutstanding, fromAccount?.currency)}.
          </p>
        ) : null}

        {insufficient && (
          <p className="text-red-500 text-xs">⚠️ Insufficient balance</p>
        )}
      </div>

      {(!isTransfer || isExpenseLikeTransfer) && (
        <CategoryTreeSelect
          categories={localCategories}
          type={categoryType}
          value={categoryId}
          onChange={(id: string) =>
            setValue("category_id", id, { shouldDirty: true })
          }
          onCreated={(category: Category) =>
            setLocalCategories((current) => [...current, category])
          }
        />
      )}

      <div className="rounded-md border border-line bg-white p-3">
        <div className="mb-2 flex items-center gap-2 text-sm font-semibold text-ink">
          <CalendarDays className="h-4 w-4 text-brand-600" />
          Date
        </div>
        <div className="mb-2 flex flex-wrap gap-2">
          {[
            { label: "Today", offset: 0 },
            { label: "Yesterday", offset: -1 },
            { label: "Tomorrow", offset: 1 },
          ].map((option) => (
            <button
              key={option.label}
              type="button"
              onClick={() => setQuickDate(option.offset)}
              className="rounded-md border border-line bg-surface px-3 py-1 text-xs font-semibold text-muted"
            >
              {option.label}
            </button>
          ))}
        </div>
        <div className="grid gap-2 sm:grid-cols-[1fr_110px]">
          <div className="flex items-center justify-between rounded-md border border-line bg-surface px-2 py-1.5">
            <button
              type="button"
              className="rounded-md p-1.5 text-muted hover:bg-white"
              onClick={() => nudgeDate(-1)}
              title="Previous day"
            >
              <ChevronDown className="h-4 w-4" />
            </button>
            <span className="text-sm font-semibold text-ink">
              {displayDate(dateParts.date)}
            </span>
            <button
              type="button"
              className="rounded-md p-1.5 text-muted hover:bg-white"
              onClick={() => nudgeDate(1)}
              title="Next day"
            >
              <ChevronUp className="h-4 w-4" />
            </button>
          </div>
          <div className="rounded-md border border-line bg-surface px-3 py-2 text-center text-sm font-semibold text-ink">
            {dateParts.time}
          </div>
        </div>
        <input type="hidden" {...register("txn_date")} />
      </div>

      {noteOpen ? (
        <div className="space-y-2">
          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">Note</span>
            <input
              className="h-10 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition placeholder:text-slate-400 focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
              placeholder="Add a short memo"
              {...register("description")}
            />
          </label>

          {noteSuggestions.length > 0 ? (
            <div className="flex flex-wrap gap-2">
              {noteSuggestions.map((note) => (
                <button
                  key={note}
                  type="button"
                  onClick={() => {
                    setValue("description", note, { shouldDirty: true });
                    setNoteOpen(true);
                  }}
                  className="max-w-full truncate rounded-full border border-line bg-white px-3 py-1.5 text-xs font-medium text-muted transition hover:border-brand-300 hover:text-brand-700"
                  title={note}
                >
                  {note}
                </button>
              ))}
            </div>
          ) : null}
        </div>
      ) : (
        <button
          type="button"
          onClick={() => setNoteOpen(true)}
          className="h-10 rounded-md border border-dashed border-line bg-white text-sm font-semibold text-muted"
        >
          {description ? `Note: ${description}` : "Add note"}
        </button>
      )}

      <div className="sticky bottom-0 z-20 -mx-1 mt-auto flex justify-end gap-2 border-t border-line bg-white/95 px-1 py-2 backdrop-blur">
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
