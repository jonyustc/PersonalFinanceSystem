// Period math for the reports page. All dates are local; ranges are inclusive
// [start, end] with `fromDate`/`toDate` as YYYY-MM-DD strings for the API.

export type Granularity = "week" | "month" | "year";

export interface PeriodRange {
  start: Date;
  end: Date;
  fromDate: string;
  toDate: string;
  /** Number of calendar days in the range (inclusive). */
  days: number;
}

export interface TrendBucket {
  key: string;
  label: string;
  fromDate: string;
  toDate: string;
}

export function toIsoDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
    date.getDate(),
  ).padStart(2, "0")}`;
}

function dayCount(start: Date, end: Date): number {
  const ms = end.getTime() - start.getTime();
  return Math.round(ms / 86_400_000) + 1;
}

function makeRange(start: Date, end: Date): PeriodRange {
  return {
    start,
    end,
    fromDate: toIsoDate(start),
    toDate: toIsoDate(end),
    days: dayCount(start, end),
  };
}

/** Monday of the week containing `date`. */
export function startOfWeek(date: Date): Date {
  const day = date.getDay(); // 0 = Sunday
  const offset = (day + 6) % 7; // days since Monday
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() - offset);
}

/** Canonical period start for the period containing `date`. */
export function periodStartFor(granularity: Granularity, date: Date): Date {
  switch (granularity) {
    case "week":
      return startOfWeek(date);
    case "month":
      return new Date(date.getFullYear(), date.getMonth(), 1);
    case "year":
      return new Date(date.getFullYear(), 0, 1);
  }
}

/** Full range of the period beginning at `start` (assumed canonical). */
export function rangeFromStart(granularity: Granularity, start: Date): PeriodRange {
  switch (granularity) {
    case "week":
      return makeRange(
        start,
        new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6),
      );
    case "month":
      return makeRange(start, new Date(start.getFullYear(), start.getMonth() + 1, 0));
    case "year":
      return makeRange(start, new Date(start.getFullYear(), 11, 31));
  }
}

/** Start of the period `offset` periods away from `start`. */
export function shiftPeriodStart(
  granularity: Granularity,
  start: Date,
  offset: number,
): Date {
  switch (granularity) {
    case "week":
      return new Date(
        start.getFullYear(),
        start.getMonth(),
        start.getDate() + offset * 7,
      );
    case "month":
      return new Date(start.getFullYear(), start.getMonth() + offset, 1);
    case "year":
      return new Date(start.getFullYear() + offset, 0, 1);
  }
}

/** The immediately-previous, equal-length period. */
export function previousRange(granularity: Granularity, start: Date): PeriodRange {
  return rangeFromStart(granularity, shiftPeriodStart(granularity, start, -1));
}

const SHORT_DAY: Intl.DateTimeFormatOptions = { month: "short", day: "numeric" };

export function periodLabel(granularity: Granularity, range: PeriodRange): string {
  switch (granularity) {
    case "week": {
      const sameYear = range.start.getFullYear() === range.end.getFullYear();
      const startLabel = range.start.toLocaleDateString(
        "en-US",
        sameYear ? SHORT_DAY : { ...SHORT_DAY, year: "numeric" },
      );
      const endLabel = range.end.toLocaleDateString("en-US", {
        ...SHORT_DAY,
        year: "numeric",
      });
      return `${startLabel} – ${endLabel}`;
    }
    case "month":
      return range.start.toLocaleDateString("en-US", {
        month: "long",
        year: "numeric",
      });
    case "year":
      return String(range.start.getFullYear());
  }
}

/**
 * The last `count` buckets of the selected granularity, oldest → newest,
 * ending with the period that starts at `start`.
 */
export function trendBuckets(
  granularity: Granularity,
  start: Date,
  count = 6,
): TrendBucket[] {
  const buckets: TrendBucket[] = [];
  for (let i = count - 1; i >= 0; i -= 1) {
    const bucketStart = shiftPeriodStart(granularity, start, -i);
    const range = rangeFromStart(granularity, bucketStart);
    let label: string;
    switch (granularity) {
      case "week":
        label = bucketStart.toLocaleDateString("en-US", SHORT_DAY);
        break;
      case "month":
        label = bucketStart.toLocaleDateString("en-US", { month: "short" });
        break;
      case "year":
        label = String(bucketStart.getFullYear());
        break;
    }
    buckets.push({
      key: range.fromDate,
      label,
      fromDate: range.fromDate,
      toDate: range.toDate,
    });
  }
  return buckets;
}

/** `YYYY-MM` key for the budget summary endpoint. */
export function monthKeyFor(start: Date): string {
  return `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, "0")}`;
}
