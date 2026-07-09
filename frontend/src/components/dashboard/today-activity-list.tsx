import { ArrowDownLeft, ArrowLeftRight, ArrowUpRight, ReceiptText } from "lucide-react";
import Link from "next/link";
import type { LucideIcon } from "lucide-react";

import { EmptyPanel } from "@/components/ui/empty-panel";
import { categoryVisual } from "@/lib/category-visuals";
import { formatMoney } from "@/lib/money";
import { cn } from "@/lib/utils";
import type { Account, Category, Transaction } from "@/types/api";

function toNumber(value: string | number | null | undefined) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

const FALLBACK_ICONS: Record<Transaction["type"], LucideIcon> = {
  expense: ArrowUpRight,
  income: ArrowDownLeft,
  transfer: ArrowLeftRight,
};

const FALLBACK_COLORS: Record<Transaction["type"], string> = {
  expense: "#dc2626",
  income: "#16a34a",
  transfer: "#475569",
};

const FALLBACK_TITLES: Record<Transaction["type"], string> = {
  expense: "Expense",
  income: "Income",
  transfer: "Transfer",
};

interface TodayActivityListProps {
  transactions: Transaction[];
  accounts: Map<string, Account>;
  categories: Map<string, Category>;
}

export function TodayActivityList({ transactions, accounts, categories }: TodayActivityListProps) {
  if (transactions.length === 0) {
    return (
      <EmptyPanel
        icon={ReceiptText}
        title="No transactions today"
        body="Tap the + button to add your first one"
        action={
          <Link
            href="/dashboard/transactions"
            className="text-xs font-semibold text-brand-700 hover:underline"
          >
            View all transactions
          </Link>
        }
      />
    );
  }

  return (
    <div className="card divide-y divide-line">
      {transactions.map((transaction) => (
        <TransactionRow
          key={transaction.id}
          transaction={transaction}
          account={accounts.get(transaction.account_id)}
          category={
            transaction.category_id ? categories.get(transaction.category_id) : undefined
          }
        />
      ))}
    </div>
  );
}

function TransactionRow({
  transaction,
  account,
  category,
}: {
  transaction: Transaction;
  account?: Account;
  category?: Category;
}) {
  const type = transaction.type;
  const visual = category ? categoryVisual(category.name, category.color) : null;
  const Icon = visual ? visual.Icon : FALLBACK_ICONS[type];
  const color = visual ? visual.color : FALLBACK_COLORS[type];

  const title =
    transaction.description || transaction.merchant_name || category?.name || FALLBACK_TITLES[type];
  const caption = account?.name ?? category?.name ?? "";

  const amount = toNumber(transaction.amount);
  const sign = type === "expense" ? "-" : type === "income" ? "+" : "";

  return (
    <div className="flex items-center gap-3 px-4 py-3">
      <span
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
        style={{ backgroundColor: `${color}24`, color }}
        aria-hidden
      >
        <Icon className="h-[18px] w-[18px]" />
      </span>

      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-ink">{title}</p>
        {caption ? <p className="truncate text-xs text-muted">{caption}</p> : null}
      </div>

      <p
        className={cn(
          "money shrink-0 text-sm font-semibold",
          type === "expense" ? "text-expense" : type === "income" ? "text-income" : "text-ink",
        )}
      >
        {sign}
        {formatMoney(amount, account?.currency || "BDT")}
      </p>
    </div>
  );
}
