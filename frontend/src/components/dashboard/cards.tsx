import { Banknote, PiggyBank, TrendingDown, TrendingUp } from "lucide-react";
import { formatCurrency } from "@/lib/utils";

export function DashboardCards({ data }: any) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 hover:shadow-md transition grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <Card icon={PiggyBank} label="Net Worth" value={data.net_worth} />
      <Card
        icon={TrendingUp}
        label="Income"
        value={data.total_income_this_month}
      />
      <Card
        icon={TrendingDown}
        label="Expense"
        value={data.total_expense_this_month}
      />
      <Card icon={Banknote} label="Balance" value={data.total_cash} />
    </div>
  );
}

function Card({ icon: Icon, label, value }: any) {
  return (
    <div className="p-4 bg-white rounded-xl border shadow-sm">
      <div className="flex items-center justify-between">
        <span className="text-sm text-gray-500">{label}</span>
        <Icon className="h-4 w-4 text-gray-400" />
      </div>
      <p className="text-xl font-semibold mt-2">{formatCurrency(value || 0)}</p>
    </div>
  );
}
