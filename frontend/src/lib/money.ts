const SYMBOLS: Record<string, string> = {
  USD: "$",
  EUR: "€",
  GBP: "£",
  BDT: "৳",
};

// Matches the mobile app's formatter: symbol prefix, thousands separators,
// decimals only when the value isn't a whole number, negatives as -৳500.
export function formatMoney(
  value: number | string | null | undefined,
  currency = "BDT",
): string {
  const num = typeof value === "string" ? Number(value) : value ?? 0;
  const safe = Number.isFinite(num) ? (num as number) : 0;
  const symbol = SYMBOLS[currency] ?? `${currency} `;
  const abs = Math.abs(safe);
  const hasCents = Math.round(abs * 100) % 100 !== 0;
  const formatted = abs.toLocaleString("en-US", {
    minimumFractionDigits: hasCents ? 2 : 0,
    maximumFractionDigits: 2,
  });
  return `${safe < 0 ? "-" : ""}${symbol}${formatted}`;
}

export function signedMoney(value: number, currency = "BDT"): string {
  const formatted = formatMoney(Math.abs(value), currency);
  return value >= 0 ? `+${formatted}` : `-${formatted}`;
}
