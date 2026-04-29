import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        ink: "#17212b",
        muted: "#667085",
        line: "#d9e2ec",
        surface: "#f7fafc",
        brand: {
          50: "#eef9f6",
          100: "#d5f1ea",
          500: "#1f9d7a",
          600: "#137f65",
          700: "#0f6653"
        },
        accent: {
          500: "#d97706",
          600: "#b45309"
        }
      },
      boxShadow: {
        soft: "0 12px 32px rgba(23, 33, 43, 0.08)"
      }
    }
  },
  plugins: []
};

export default config;
