"use client";

import { Monitor, Moon, Sun } from "lucide-react";

import {
  useTheme,
  type ThemePreference,
} from "@/components/providers/theme-provider";

const ORDER: ThemePreference[] = ["light", "dark", "system"];

const META: Record<ThemePreference, { icon: typeof Sun; label: string }> = {
  light: { icon: Sun, label: "Light theme" },
  dark: { icon: Moon, label: "Dark theme" },
  system: { icon: Monitor, label: "System theme" },
};

// Cycles light → dark → system, like the mobile app's theme setting.
export function ThemeToggle({ className }: { className?: string }) {
  const { theme, setTheme } = useTheme();
  const { icon: Icon, label } = META[theme];

  function cycle() {
    const next = ORDER[(ORDER.indexOf(theme) + 1) % ORDER.length];
    setTheme(next);
  }

  return (
    <button
      type="button"
      onClick={cycle}
      className={
        className ??
        "rounded-lg p-2 text-muted transition hover:bg-card hover:text-ink"
      }
      title={`${label} — tap to change`}
      aria-label={label}
    >
      <Icon className="h-5 w-5" />
    </button>
  );
}
