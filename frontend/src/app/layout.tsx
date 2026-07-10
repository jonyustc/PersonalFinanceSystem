import type { Metadata } from "next";
import { QueryProvider } from "@/components/providers/query-provider";
import { ThemeProvider } from "@/components/providers/theme-provider";
import "./globals.css";

export const metadata: Metadata = {
  title: "Personal Finance System",
  description:
    "Personal finance dashboard for accounts, transactions, budgets, and reports",
};

// Applies the stored theme before hydration so dark mode doesn't flash white.
const themeBootScript = `(function(){try{var t=localStorage.getItem("pf_theme");var d=t==="dark"||(t==="system"&&window.matchMedia("(prefers-color-scheme: dark)").matches);if(d)document.documentElement.classList.add("dark");}catch(e){}})();`;

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeBootScript }} />
      </head>
      <body className="min-h-screen bg-surface text-ink antialiased">
        <ThemeProvider>
          <QueryProvider>
            <div className="min-h-screen">{children}</div>
          </QueryProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
