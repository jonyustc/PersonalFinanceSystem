import type { Metadata } from "next";
import { QueryProvider } from "@/components/providers/query-provider";
import "./globals.css";

export const metadata: Metadata = {
  title: "Personal Finance System",
  description:
    "Personal finance dashboard for accounts, transactions, budgets, and reports",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-gray-50 text-gray-900 antialiased">
        {/* Global wrapper only */}
        <QueryProvider>
          <div className="min-h-screen">{children}</div>
        </QueryProvider>
      </body>
    </html>
  );
}
