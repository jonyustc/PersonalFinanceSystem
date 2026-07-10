"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
} from "recharts";

import { formatMoney } from "@/lib/money";

const BRAND = "#0f766e";
const BRAND_FADED = "rgba(15, 118, 110, 0.35)";

export interface TrendPointDatum {
  key: string;
  label: string;
  amount: number;
}

interface TrendChartProps {
  data: TrendPointDatum[];
  loading: boolean;
  /** e.g. "Last 6 months" */
  subtitle: string;
}

interface TrendTooltipProps {
  active?: boolean;
  label?: string | number;
  payload?: ReadonlyArray<{ value?: number | string }>;
}

function TrendTooltip({ active, label, payload }: TrendTooltipProps) {
  if (!active || !payload?.length) return null;
  const value = Number(payload[0]?.value ?? 0);
  return (
    <div className="rounded-lg border border-line bg-card px-2.5 py-1.5">
      <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">
        {label}
      </p>
      <p className="money text-sm font-bold text-ink">{formatMoney(value)}</p>
    </div>
  );
}

/**
 * Expense totals for the last 6 buckets of the selected granularity. The
 * current (last) bucket is solid teal; earlier buckets are faded, mirroring
 * the mobile `_TrendChart`.
 */
export function TrendChart({ data, loading, subtitle }: TrendChartProps) {
  return (
    <section className="card p-4">
      <div className="px-1">
        <h2 className="text-base font-bold tracking-tight text-ink">Trend</h2>
        <p className="text-xs text-muted">{subtitle}</p>
      </div>
      <div className="mt-3 h-[180px]">
        {loading ? (
          <div className="h-full animate-pulse rounded-xl bg-line/60" />
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={data} margin={{ top: 8, right: 4, bottom: 0, left: 4 }}>
              <CartesianGrid vertical={false} stroke="#e7ecf3" />
              <XAxis
                dataKey="label"
                axisLine={false}
                tickLine={false}
                tick={{ fontSize: 11, fill: "#667085" }}
                interval={0}
              />
              <Tooltip
                cursor={{ fill: "rgba(15, 23, 42, 0.04)" }}
                content={<TrendTooltip />}
              />
              <Bar dataKey="amount" radius={[6, 6, 0, 0]} maxBarSize={32}>
                {data.map((point, index) => (
                  <Cell
                    key={point.key}
                    fill={index === data.length - 1 ? BRAND : BRAND_FADED}
                  />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </section>
  );
}
