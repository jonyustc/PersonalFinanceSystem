export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-10">
      <div className="grid w-full max-w-5xl items-center gap-8 lg:grid-cols-[1fr_440px]">
        <section className="hidden lg:block">
          <p className="text-sm font-semibold uppercase tracking-wide text-brand-700">Finance workspace</p>
          <h2 className="mt-4 max-w-xl text-5xl font-semibold leading-tight text-ink">
            Track cashflow, budgets, and investments from one calm dashboard.
          </h2>
          <div className="mt-8 grid max-w-lg grid-cols-2 gap-3">
            {["Bank balances", "Monthly budgets", "Stock holdings", "Reports"].map((item) => (
              <div className="rounded-lg border border-line bg-white p-4 shadow-soft" key={item}>
                <p className="text-sm font-medium text-ink">{item}</p>
              </div>
            ))}
          </div>
        </section>
        {children}
      </div>
    </main>
  );
}
