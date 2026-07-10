import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        // Semantic tokens backed by CSS variables (see globals.css) so the
        // whole app flips between the light and dark Flutter palettes.
        ink: "rgb(var(--c-ink) / <alpha-value>)",
        muted: "rgb(var(--c-muted) / <alpha-value>)",
        line: "rgb(var(--c-line) / <alpha-value>)",
        surface: "rgb(var(--c-surface) / <alpha-value>)",
        card: "rgb(var(--c-card) / <alpha-value>)",
        brand: {
          50: "rgb(var(--c-brand-50) / <alpha-value>)",
          100: "rgb(var(--c-brand-100) / <alpha-value>)",
          200: "#99f6e4",
          500: "#14b8a6",
          600: "#0f766e",
          700: "rgb(var(--c-brand-700) / <alpha-value>)"
        },
        accent: {
          100: "#fef3c7",
          500: "#f59e0b",
          600: "#b45309"
        },
        income: {
          DEFAULT: "rgb(var(--c-income) / <alpha-value>)",
          soft: "rgb(var(--c-income-soft) / <alpha-value>)"
        },
        expense: {
          DEFAULT: "rgb(var(--c-expense) / <alpha-value>)",
          soft: "rgb(var(--c-expense-soft) / <alpha-value>)"
        },
        warning: {
          DEFAULT: "rgb(var(--c-warning) / <alpha-value>)",
          soft: "rgb(var(--c-warning-soft) / <alpha-value>)"
        }
      },
      borderColor: {
        DEFAULT: "rgb(var(--c-line) / 1)"
      },
      boxShadow: {
        soft: "0 12px 32px rgba(23, 33, 43, 0.08)",
        fab: "0 8px 24px rgba(15, 118, 110, 0.35)"
      },
      fontFamily: {
        sans: [
          "Roboto",
          "ui-sans-serif",
          "system-ui",
          "-apple-system",
          "Segoe UI",
          "sans-serif"
        ]
      }
    }
  },
  plugins: []
};

export default config;
