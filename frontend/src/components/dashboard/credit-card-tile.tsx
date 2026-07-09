import { ProgressPill, utilizationColor } from "@/components/ui/progress-pill";
import { formatMoney } from "@/lib/money";
import type { SimpleDashboardCard } from "@/types/api";

function toNumber(value: string | number | null | undefined) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

interface CreditCardTileProps {
  card: SimpleDashboardCard;
}

// One card per credit card: utilization headline + progress + mini stats,
// mirroring the mobile dashboard's card tiles.
export function CreditCardTile({ card }: CreditCardTileProps) {
  const limit = toNumber(card.credit_limit);
  const outstanding = toNumber(card.current_outstanding);
  const fraction = limit > 0 ? outstanding / limit : 0;
  const usedPercent = toNumber(card.used_percentage);

  return (
    <article className="card p-4">
      <div className="flex items-baseline justify-between gap-3">
        <p className="min-w-0 truncate text-sm font-bold text-ink">{card.name}</p>
        <p
          className="money shrink-0 text-sm font-extrabold"
          style={{ color: utilizationColor(fraction) }}
        >
          {usedPercent.toFixed(1)}%
        </p>
      </div>
      <p className="money mt-0.5 text-xs text-muted">
        {formatMoney(outstanding)} of {formatMoney(limit)}
      </p>

      <ProgressPill fraction={fraction} className="mt-3" />

      <div className="mt-3 grid grid-cols-3 gap-2">
        <MiniStat label="Available" value={formatMoney(card.available_limit)} />
        <MiniStat label="Spent" value={formatMoney(card.monthly_spending)} />
        <MiniStat label="Paid" value={formatMoney(card.monthly_payment)} />
      </div>
    </article>
  );
}

function MiniStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 rounded-xl bg-surface px-2.5 py-2">
      <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">{label}</p>
      <p className="money mt-0.5 truncate text-xs font-bold text-ink">{value}</p>
    </div>
  );
}
