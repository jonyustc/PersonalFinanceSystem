"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import {
  ArrowLeftRight,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Delete,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";

import { cn, formatCurrency } from "@/lib/utils";
import { formatMoney } from "@/lib/money";
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

function dayLabel(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(year, month - 1, day);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const diff = Math.round((date.getTime() - today.getTime()) / 86400000);
  if (diff === 0) return "Today";
  if (diff === -1) return "Yesterday";
  if (diff === 1) return "Tomorrow";
  return date.toLocaleDateString("en-US", { weekday: "long" });
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

// Keypad layout mirrors the mobile app: AC / DEL / OK row, then digits with
// operator column. "x" maps to "*" for evaluation.
const KEYPAD_ROWS: string[][] = [
  ["7", "8", "9", "/"],
  ["4", "5", "6", "x"],
  ["1", "2", "3", "-"],
  ["0", "00", ".", "+"],
];

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
  const [keypadOpen, setKeypadOpen] = useState(autoFocusAmount);
  const [noteOpen, setNoteOpen] = useState(Boolean(transaction?.description));
  const [noteSuggestions, setNoteSuggestions] = useState<string[]>([]);
  const [datePickerOpen, setDatePickerOpen] = useState(false);
  const [touchDevice, setTouchDevice] = useState(false);
  const amountRef = useRef<HTMLInputElement | null>(null);
  const lastAutoNoteRef = useRef("");

  // On touch devices the custom keypad is the input method — suppress the OS keyboard.
  useEffect(() => {
    setTouchDevice(window.matchMedia("(pointer: coarse)").matches);
  }, []);

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
    if (!transaction && activeAccounts.length && !watch("account_id")) {
      setValue("account_id", activeAccounts[0].id);
    }
  }, [activeAccounts, transaction, setValue, watch]);

  useEffect(() => {
    if (type !== "transfer") {
      setValue("transfer_account_id", "");
    } else if (!transaction && !watch("transfer_account_id")) {
      // Default transfer destination = second account, like the mobile app
      const second = activeAccounts.find((account) => account.id !== watch("account_id"));
      if (second) setValue("transfer_account_id", second.id);
    }
  }, [type, transaction, activeAccounts, setValue, watch]);

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

  // Smart default: first matching parent category, like the mobile app.
  // Also re-defaults when switching type leaves a mismatched category selected.
  useEffect(() => {
    if (transaction || isTransfer || !localCategories.length) return;
    const selected = localCategories.find((category) => category.id === categoryId);
    if (selected && selected.type === categoryType) return;
    const first = localCategories.find(
      (category) => category.type === categoryType && !category.parent_id,
    );
    if (first) {
      setValue("category_id", first.id, { shouldDirty: false });
    }
  }, [transaction, isTransfer, localCategories, categoryId, categoryType, setValue]);

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

  function syncAmountFromExpression(expression: string) {
    const result = evaluateAmountExpression(expression);
    if (Number.isFinite(result) && result > 0) {
      setValue("amount", result, { shouldDirty: true, shouldValidate: true });
    } else if (!expression.trim()) {
      setValue("amount", 0, { shouldDirty: true });
    }
  }

  function applyAmountExpression(nextExpression = amountExpression) {
    const result = evaluateAmountExpression(nextExpression);
    if (Number.isFinite(result) && result > 0) {
      setValue("amount", result, { shouldDirty: true, shouldValidate: true });
      setAmountExpression(String(result));
    }
  }

  function pressKey(token: string) {
    if (token === "ac") {
      setAmountExpression("");
      setValue("amount", 0, { shouldDirty: true });
      return;
    }
    if (token === "del") {
      const next = amountExpression.slice(0, -1);
      setAmountExpression(next);
      syncAmountFromExpression(next);
      return;
    }
    if (token === "ok") {
      applyAmountExpression();
      setKeypadOpen(false);
      return;
    }
    const value = token === "x" ? "*" : token;
    const next = `${amountExpression}${value}`;
    setAmountExpression(next);
    syncAmountFromExpression(next);
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

  const amountTone =
    type === "income" ? "text-income" : type === "expense" ? "text-expense" : "text-brand-700";

  const hasOperator = /[+\-*/]/.test(amountExpression.slice(1));

  return (
    <form onSubmit={handleSubmit(submit)} className="flex min-h-full flex-col gap-3 pb-2">
      {/* TYPE TABS — Flutter-style uppercase tab bar with bottom indicator */}
      <div className="grid grid-cols-3 border-b border-line">
        {(["expense", "income", "transfer"] as const).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setValue("type", option)}
            className={cn(
              "border-b-[3px] px-2 pb-2.5 pt-1 text-[13px] font-extrabold uppercase tracking-wide transition",
              type === option
                ? "border-brand-600 text-brand-700"
                : "border-transparent text-muted hover:text-ink",
            )}
          >
            {option}
          </button>
        ))}
      </div>

      {/* AMOUNT HEADER — tap to toggle the keypad */}
      <div
        className={cn(
          "rounded-xl border bg-surface px-4 py-3 transition",
          keypadOpen ? "border-brand-600" : "border-line",
        )}
        onClick={() => {
          setKeypadOpen(true);
          amountRef.current?.focus();
        }}
      >
        <div className="flex items-center justify-between gap-3">
          <span className="text-sm font-medium text-muted">Amount</span>
          <input
            ref={amountRef}
            type="text"
            inputMode={touchDevice ? "none" : "decimal"}
            placeholder="0"
            value={amountExpression}
            onFocus={() => setKeypadOpen(true)}
            onBlur={() => applyAmountExpression()}
            onChange={(event) => {
              setAmountExpression(event.target.value);
              syncAmountFromExpression(event.target.value);
            }}
            className={cn(
              "money min-w-0 flex-1 bg-transparent text-right text-4xl font-semibold outline-none placeholder:text-muted/50",
              amountTone,
            )}
          />
          <input className="sr-only" type="number" {...amountRegistration} ref={amountRegistration.ref} />
        </div>
        {hasOperator && amountNumber > 0 ? (
          <p className="money text-right text-sm font-medium text-muted">
            = {formatMoney(amountNumber, fromAccount?.currency)}
          </p>
        ) : null}
        {errors.amount && (
          <p className="mt-1 text-right text-xs font-medium text-expense">{errors.amount.message}</p>
        )}
      </div>

      {/* DATE STRIP — ‹ Today · date · time › */}
      <div className="flex items-center rounded-xl bg-surface border border-line px-1 py-1">
        <button
          type="button"
          onClick={() => nudgeDate(-1)}
          className="rounded-lg p-2 text-muted hover:bg-white"
          aria-label="Previous day"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <button
          type="button"
          onClick={() => setDatePickerOpen((current) => !current)}
          className="min-w-0 flex-1 text-center"
        >
          <span className="text-sm font-semibold text-ink">{dayLabel(dateParts.date)}</span>
          <span className="ml-2 text-xs text-muted">
            {dateParts.date} · {dateParts.time}
          </span>
        </button>
        <button
          type="button"
          onClick={() => setDatePickerOpen((current) => !current)}
          className="rounded-lg p-2 text-brand-700 hover:bg-white"
          aria-label="Pick date"
        >
          <CalendarDays className="h-4 w-4" />
        </button>
        <button
          type="button"
          onClick={() => nudgeDate(1)}
          className="rounded-lg p-2 text-muted hover:bg-white"
          aria-label="Next day"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
        <input type="hidden" {...register("txn_date")} />
      </div>

      {datePickerOpen ? (
        <div className="grid grid-cols-[1fr_120px] gap-2">
          <input
            type="date"
            className="input h-11"
            value={dateParts.date}
            onChange={(event) =>
              setValue("txn_date", combineLocalDateTime(event.target.value, dateParts.time), {
                shouldDirty: true,
              })
            }
          />
          <input
            type="time"
            className="input h-11"
            value={dateParts.time}
            onChange={(event) =>
              setValue("txn_date", combineLocalDateTime(dateParts.date, event.target.value), {
                shouldDirty: true,
              })
            }
          />
        </div>
      ) : null}

      {/* QUICK CATEGORIES */}
      {quickCategories.length > 0 && (!isTransfer || isExpenseLikeTransfer) ? (
        <div className="flex gap-2 overflow-x-auto pb-0.5">
          {quickCategories.map((category) => (
            <button
              key={category.id}
              type="button"
              onClick={() => setValue("category_id", category.id)}
              className={cn(
                "shrink-0 rounded-full border px-3.5 py-1.5 text-xs font-semibold transition",
                categoryId === category.id
                  ? "border-brand-600 bg-brand-600/15 text-brand-700"
                  : "border-line bg-white text-muted hover:text-ink",
              )}
            >
              {category.name}
            </button>
          ))}
        </div>
      ) : null}

      {/* ACCOUNTS */}
      <div className="space-y-2 rounded-xl border border-line bg-white p-3">
        <div className={cn("grid gap-2", isTransfer && "sm:grid-cols-[1fr_auto_1fr]")}>
          <label className="block">
            <span className="mb-1 block text-[11px] font-semibold uppercase tracking-wide text-muted">
              {isTransfer ? "From" : "Account"}
            </span>
            <select {...register("account_id")} className="input h-11">
              <option value="">Select account</option>
              {activeAccounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({accountOptionBalance(a)})
                </option>
              ))}
            </select>
          </label>

          {isTransfer && (
            <>
              <button
                type="button"
                onClick={handleSwap}
                className="mx-auto mt-5 hidden h-9 w-9 items-center justify-center rounded-full border border-line text-brand-700 hover:bg-brand-50 sm:flex"
                title="Swap accounts"
              >
                <ArrowLeftRight className="h-4 w-4" />
              </button>
              <label className="block">
                <span className="mb-1 block text-[11px] font-semibold uppercase tracking-wide text-muted">
                  To
                </span>
                <select {...register("transfer_account_id")} className="input h-11">
                  <option value="">Select account</option>
                  {activeAccounts.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name} ({accountOptionBalance(a)})
                    </option>
                  ))}
                </select>
              </label>
              <button
                type="button"
                onClick={handleSwap}
                className="flex items-center gap-1.5 text-xs font-semibold text-brand-700 sm:hidden"
              >
                <ArrowLeftRight className="h-3.5 w-3.5" />
                Swap accounts
              </button>
            </>
          )}
        </div>

        {errors.transfer_account_id && (
          <p className="text-xs font-medium text-expense">{errors.transfer_account_id.message}</p>
        )}

        {fromAccount && amountNumber > 0 && (
          <div className="money space-y-1 text-xs text-muted">
            <div>
              {fromAccount.name}: {formatMoney(fromBalance, fromAccount.currency)} →{" "}
              <span className={insufficient ? "font-semibold text-expense" : "font-semibold text-ink"}>
                {formatMoney(previewFrom, fromAccount.currency)}
              </span>
            </div>

            {isTransfer && toAccount && (
              <div>
                {toAccount.name}: {formatMoney(toBalance, toAccount.currency)} →{" "}
                <span className="font-semibold text-income">
                  {formatMoney(previewTo, toAccount.currency)}
                </span>
              </div>
            )}
          </div>
        )}

        {isCardPayment ? (
          <p className="text-xs font-medium text-warning">
            Saved as a card payment — outstanding drops to {formatMoney(previewToOutstanding, toAccount?.currency)}.
          </p>
        ) : null}

        {isCardSpendingTransfer ? (
          <p className="text-xs font-medium text-warning">
            Saved as card spending — outstanding becomes {formatMoney(previewFromOutstanding, fromAccount?.currency)}.
          </p>
        ) : null}

        {type === "expense" && isFromCreditCard ? (
          <p className="text-xs font-medium text-warning">
            Card outstanding will become {formatMoney(previewFromOutstanding, fromAccount?.currency)}.
          </p>
        ) : null}

        {insufficient && (
          <p className="text-xs font-semibold text-expense">⚠️ Insufficient balance</p>
        )}
      </div>

      {/* CATEGORY */}
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

      {/* NOTE */}
      {noteOpen ? (
        <div className="space-y-2">
          <input
            className="input h-11"
            placeholder="Add a short memo"
            {...register("description")}
          />

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
                  className="max-w-full truncate rounded-full border border-line bg-white px-3 py-1.5 text-xs font-medium text-muted transition hover:border-brand-500 hover:text-brand-700"
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
          className="h-11 rounded-xl border border-dashed border-line bg-white text-sm font-semibold text-muted hover:text-ink"
        >
          {description ? `Note: ${description}` : "Add note"}
        </button>
      )}

      {/* KEYPAD or SAVE BAR */}
      <div className="sticky bottom-0 z-20 mt-auto -mx-1 border-t border-line bg-white/95 px-1 pb-2 pt-2 backdrop-blur">
        {keypadOpen ? (
          <div className="space-y-1.5">
            <div className="grid grid-cols-4 gap-1.5">
              <button
                type="button"
                onClick={() => pressKey("ac")}
                className="h-12 rounded-xl bg-expense-soft text-sm font-extrabold text-expense active:scale-95"
              >
                AC
              </button>
              <button
                type="button"
                onClick={() => pressKey("del")}
                className="flex h-12 items-center justify-center rounded-xl bg-surface text-ink active:scale-95"
                aria-label="Backspace"
              >
                <Delete className="h-5 w-5" />
              </button>
              <button
                type="button"
                onClick={() => pressKey("ok")}
                className="col-span-2 h-12 rounded-xl bg-brand-600 text-sm font-extrabold text-white active:scale-95"
              >
                OK
              </button>
            </div>
            {KEYPAD_ROWS.map((row) => (
              <div key={row.join()} className="grid grid-cols-4 gap-1.5">
                {row.map((token) => {
                  const isOperator = ["/", "x", "-", "+"].includes(token);
                  return (
                    <button
                      key={token}
                      type="button"
                      onClick={() => pressKey(token)}
                      className={cn(
                        "h-12 rounded-xl text-xl font-bold active:scale-95",
                        isOperator
                          ? "bg-brand-600/15 text-brand-700"
                          : "bg-surface text-ink hover:bg-brand-50",
                      )}
                    >
                      {token === "x" ? "×" : token}
                    </button>
                  );
                })}
              </div>
            ))}
          </div>
        ) : (
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onCancel}
              className="h-12 rounded-xl border border-line bg-white px-5 text-sm font-semibold text-muted hover:text-ink"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="h-12 flex-1 rounded-xl bg-brand-600 text-sm font-bold text-white transition hover:bg-brand-700 disabled:opacity-60"
            >
              {isSubmitting ? "Saving…" : "Save transaction"}
            </button>
          </div>
        )}
      </div>
    </form>
  );
}
