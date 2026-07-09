import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        ink: "#0f172a",
        muted: "#667085",
        line: "#e7ecf3",
        surface: "#f6f8fb",
        brand: {
          50: "#f0fdfa",
          100: "#ccfbf1",
          200: "#99f6e4",
          500: "#14b8a6",
          600: "#0f766e",
          700: "#115e59"
        },
        accent: {
          100: "#fef3c7",
          500: "#f59e0b",
          600: "#b45309"
        },
        income: {
          DEFAULT: "#15803d",
          soft: "#dcfce7"
        },
        expense: {
          DEFAULT: "#b91c1c",
          soft: "#fee2e2"
        },
        warning: {
          DEFAULT: "#b45309",
          soft: "#fef3c7"
        }
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
