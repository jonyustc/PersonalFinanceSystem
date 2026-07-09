import type { LucideIcon } from "lucide-react";
import {
  ArrowLeftRight,
  Baby,
  Banknote,
  BookOpen,
  Bus,
  Car,
  CarTaxiFront,
  Coffee,
  Droplets,
  Dumbbell,
  Film,
  Fuel,
  Gamepad2,
  Gift,
  GraduationCap,
  HandHeart,
  Heart,
  Home,
  Landmark,
  Music,
  PawPrint,
  PiggyBank,
  Plane,
  Receipt,
  Scissors,
  Shield,
  Shirt,
  ShoppingBag,
  ShoppingCart,
  Smartphone,
  Sparkles,
  Stethoscope,
  Tag,
  TrendingUp,
  UtensilsCrossed,
  Wifi,
  Zap,
} from "lucide-react";

// Ported from mobile/lib/src/theme/category_visuals.dart so both clients
// render the same color + icon for a given category name.
const PALETTE = [
  "#ef4444",
  "#f97316",
  "#f59e0b",
  "#10b981",
  "#06b6d4",
  "#3b82f6",
  "#6366f1",
  "#8b5cf6",
  "#ec4899",
  "#14b8a6",
];

const ICON_KEYWORDS: Array<[string[], LucideIcon]> = [
  [["food", "restaurant", "lunch", "dinner", "meal"], UtensilsCrossed],
  [["grocer"], ShoppingCart],
  [["coffee", "cafe", "tea"], Coffee],
  [["transport", "commute"], Bus],
  [["uber", "taxi", "ride"], CarTaxiFront],
  [["fuel", "gas", "petrol"], Fuel],
  [["car", "vehicle"], Car],
  [["travel", "flight", "trip", "holiday"], Plane],
  [["rent", "home", "house"], Home],
  [["bill"], Receipt],
  [["utilit", "electric", "power"], Zap],
  [["water"], Droplets],
  [["internet", "broadband"], Wifi],
  [["phone", "mobile"], Smartphone],
  [["shop"], ShoppingBag],
  [["cloth", "fashion", "dress"], Shirt],
  [["health", "care"], Heart],
  [["medic", "pharma", "doctor", "hospital"], Stethoscope],
  [["gym", "fitness", "sport"], Dumbbell],
  [["education", "school", "tuition", "course"], GraduationCap],
  [["book"], BookOpen],
  [["entertain", "movie", "cinema"], Film],
  [["music"], Music],
  [["game"], Gamepad2],
  [["gift"], Gift],
  [["donation", "charity", "zakat"], HandHeart],
  [["salary", "wage", "payroll"], Banknote],
  [["income", "saving"], PiggyBank],
  [["invest", "stock", "dividend"], TrendingUp],
  [["tax", "bank", "loan", "emi"], Landmark],
  [["insurance"], Shield],
  [["pet"], PawPrint],
  [["baby", "kid", "child"], Baby],
  [["beauty", "spa"], Sparkles],
  [["salon", "hair", "barber"], Scissors],
  [["transfer"], ArrowLeftRight],
];

function hashName(name: string): number {
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }
  return hash;
}

export interface CategoryVisual {
  color: string;
  Icon: LucideIcon;
}

export function categoryVisual(
  name: string | null | undefined,
  storedColor?: string | null,
): CategoryVisual {
  const label = (name ?? "").trim();
  const lower = label.toLowerCase();

  const color =
    storedColor && /^#([0-9a-f]{6})$/i.test(storedColor)
      ? storedColor
      : PALETTE[label ? hashName(lower) % PALETTE.length : 9];

  let Icon: LucideIcon = Tag;
  for (const [keywords, candidate] of ICON_KEYWORDS) {
    if (keywords.some((keyword) => lower.includes(keyword))) {
      Icon = candidate;
      break;
    }
  }

  return { color, Icon };
}

// Report chart series palette — same order as the Flutter reports page.
export const CHART_COLORS = [
  "#0f766e",
  "#2563eb",
  "#f59e0b",
  "#dc2626",
  "#7c3aed",
  "#0891b2",
  "#16a34a",
  "#db2777",
];
