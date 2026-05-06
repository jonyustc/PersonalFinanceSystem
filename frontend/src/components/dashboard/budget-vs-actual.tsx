// components/dashboard/budget-vs-actual.tsx

export function BudgetVsActual({ data }: any) {
  if (!data) return null;

  return (
    <div className="p-4 border rounded-xl">
      <h2 className="text-lg font-semibold mb-4">
        Budget vs Actual ({data.month})
      </h2>

      <div className="space-y-3">
        {data.categories.map((c: any) => {
          const percent = c.budget
            ? Math.min((c.spent / c.budget) * 100, 100)
            : 0;

          return (
            <div key={c.category_id}>
              <div className="flex justify-between text-sm">
                <span>{c.category_name}</span>
                <span>
                  {c.spent} / {c.budget}
                </span>
              </div>

              <div className="w-full bg-gray-200 rounded h-2 mt-1">
                <div
                  className="bg-blue-500 h-2 rounded"
                  style={{ width: `${percent}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
