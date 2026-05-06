import { formatCurrency } from "@/lib/utils";

export function RecentTransactions({ data }: any[]) {
  return (
    <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm">
      <h3 className="mb-3 font-semibold">Recent Transactions</h3>

      {data.length === 0 && (
        <p className="text-sm text-gray-500">No transactions</p>
      )}

      {data.map((t) => (
        <div
          key={t.id}
          className="flex justify-between items-center py-3 border-b last:border-none"
        >
          <div>
            <p className="font-medium capitalize">{t.type}</p>
            <p className="text-xs text-gray-500">
              {t.description || "No note"}
            </p>
          </div>

          <p
            className={`font-semibold ${
              t.type === "income"
                ? "text-green-600"
                : t.type === "expense"
                  ? "text-red-500"
                  : "text-gray-600"
            }`}
          >
            {formatCurrency(t.amount)}
          </p>
        </div>
      ))}
    </div>
  );
}
