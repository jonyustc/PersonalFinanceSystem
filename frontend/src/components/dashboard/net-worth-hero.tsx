"use client";

import { useEffect, useState } from "react";

import { formatMoney } from "@/lib/money";

// Count-up over ~700ms with a cubic ease-out, matching the mobile hero.
function useCountUp(target: number, duration = 700) {
  const [value, setValue] = useState(0);

  useEffect(() => {
    let frame = 0;
    const start = performance.now();

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setValue(t < 1 ? Math.round(target * eased) : target);
      if (t < 1) frame = requestAnimationFrame(tick);
    };

    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, duration]);

  return value;
}

interface NetWorthHeroProps {
  netWorth: number;
  assets: number;
  liabilities: number;
}

export function NetWorthHero({ netWorth, assets, liabilities }: NetWorthHeroProps) {
  const animated = useCountUp(netWorth);

  return (
    <section className="card p-6">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">Net worth</p>
      <p className="money mt-1 text-3xl font-extrabold tracking-tight text-ink lg:text-4xl">
        {formatMoney(animated)}
      </p>

      <div className="mt-5 flex items-center gap-4">
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted">
            <span className="h-2 w-2 shrink-0 rounded-full bg-income" aria-hidden />
            Assets
          </p>
          <p className="money mt-0.5 truncate text-sm font-bold text-ink">{formatMoney(assets)}</p>
        </div>

        <div className="h-9 w-px shrink-0 bg-line" aria-hidden />

        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted">
            <span className="h-2 w-2 shrink-0 rounded-full bg-expense" aria-hidden />
            Liabilities
          </p>
          <p className="money mt-0.5 truncate text-sm font-bold text-ink">{formatMoney(liabilities)}</p>
        </div>
      </div>
    </section>
  );
}
