"use client";

import {
  BarChart3,
  LayoutDashboard,
  LogOut,
  Menu,
  PieChart,
  ReceiptText,
  Tags,
  TrendingUp,
  Wallet,
  X,
} from "lucide-react";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { GlobalTransactionCta } from "@/components/transactions/global-transaction-cta";
import { cn } from "@/lib/utils";
import { getMe, logout } from "@/services/auth-service";
import {
  clearAuthSession,
  getAccessToken,
  getRefreshToken,
  getStoredUser,
} from "@/services/token-store";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/dashboard/transactions", label: "Transactions", icon: ReceiptText },
  { href: "/dashboard/accounts", label: "Accounts", icon: Wallet },
  { href: "/dashboard/budgets", label: "Budgets", icon: PieChart },
  { href: "/dashboard/categories", label: "Categories", icon: Tags },
  { href: "/dashboard/reports", label: "Reports", icon: BarChart3 },
  { href: "/dashboard/portfolio", label: "Stocks", icon: TrendingUp },
];

// The 5 primary destinations surfaced in the mobile bottom bar (same set as the Flutter app)
const bottomNavItems = [
  { href: "/dashboard", label: "Home", icon: LayoutDashboard },
  { href: "/dashboard/transactions", label: "Trans.", icon: ReceiptText },
  { href: "/dashboard/accounts", label: "Accounts", icon: Wallet },
  { href: "/dashboard/reports", label: "Reports", icon: BarChart3 },
  { href: "/dashboard/portfolio", label: "Stocks", icon: TrendingUp },
];

const pageTitles: Array<[string, string]> = [
  ["/dashboard/transactions", "Transactions"],
  ["/dashboard/accounts", "Accounts"],
  ["/dashboard/budgets", "Budgets"],
  ["/dashboard/categories", "Categories"],
  ["/dashboard/reports", "Reports"],
  ["/dashboard/portfolio", "Portfolio"],
  ["/dashboard/funds", "Funds"],
  ["/dashboard", "Overview"],
];

function isActive(pathname: string, href: string) {
  return href === "/dashboard"
    ? pathname === "/dashboard"
    : pathname.startsWith(href);
}

export function DashboardShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();

  const [open, setOpen] = useState(false);
  const [user, setUser] = useState<{ full_name?: string; email?: string } | null>(null);

  const title = pageTitles.find(([prefix]) => pathname.startsWith(prefix))?.[1] ?? "Overview";

  useEffect(() => {
    let active = true;
    const u = getStoredUser();
    const token = getAccessToken();
    const refreshToken = getRefreshToken();
    if (!u || (!token && !refreshToken)) {
      clearAuthSession();
      router.push("/auth/login");
      return;
    }

    setUser(u);
    getMe()
      .then((freshUser) => {
        if (active) setUser(freshUser);
      })
      .catch(() => {
        if (!active) return;
        clearAuthSession();
        router.push("/auth/login");
      });

    return () => {
      active = false;
    };
  }, [router]);

  function handleLogout() {
    logout();
    router.push("/auth/login");
  }

  return (
    <div className="min-h-screen bg-surface flex">
      {/* SIDEBAR — permanent on desktop, drawer on mobile (secondary destinations) */}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 w-72 max-w-[85vw] lg:w-64 bg-white border-r border-line transition-transform",
          open ? "translate-x-0" : "-translate-x-full",
          "lg:translate-x-0",
        )}
      >
        <div className="flex items-center justify-between p-4 border-b border-line">
          <Link href="/dashboard" className="flex items-center gap-2 font-bold text-ink">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-600/15 text-brand-700">
              <Wallet className="h-5 w-5" />
            </span>
            Personal Finance
          </Link>

          <button
            onClick={() => setOpen(false)}
            className="lg:hidden rounded-lg p-1.5 text-muted hover:bg-surface"
            aria-label="Close menu"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <nav className="p-3 space-y-1 overflow-y-auto">
          {navItems.map((item) => {
            const active = isActive(pathname, item.href);

            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                className={cn(
                  "flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium",
                  active
                    ? "bg-brand-600/15 text-brand-700 font-semibold"
                    : "text-muted hover:bg-surface hover:text-ink",
                )}
              >
                <item.icon className="h-[18px] w-[18px]" />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="absolute inset-x-0 bottom-0 border-t border-line p-3">
          <div className="mb-2 px-3">
            <p className="truncate text-sm font-semibold text-ink">
              {user?.full_name || "User"}
            </p>
            <p className="truncate text-xs text-muted">{user?.email}</p>
          </div>
          <button
            onClick={handleLogout}
            className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-expense hover:bg-expense-soft"
          >
            <LogOut className="h-[18px] w-[18px]" />
            Logout
          </button>
        </div>
      </aside>

      {/* OVERLAY */}
      {open && (
        <div
          className="fixed inset-0 bg-black/30 z-40 lg:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      {/* MAIN */}
      <div className="min-w-0 flex-1 lg:ml-64 flex flex-col">
        {/* HEADER */}
        <header className="sticky top-0 z-30 flex h-14 items-center gap-3 border-b border-line bg-surface/95 px-4 backdrop-blur">
          <button
            onClick={() => setOpen(true)}
            className="lg:hidden rounded-lg p-1.5 -ml-1.5 text-ink hover:bg-white"
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </button>

          <h1 className="text-lg font-bold tracking-tight text-ink">{title}</h1>

          <div className="ml-auto hidden lg:flex items-center gap-3">
            <div className="text-right">
              <p className="text-sm font-medium">{user?.full_name || "User"}</p>
              <p className="text-xs text-muted">{user?.email}</p>
            </div>
          </div>
        </header>

        {/* CONTENT — bottom padding clears the mobile tab bar + FAB */}
        <main className="min-w-0 flex-1 overflow-x-hidden px-3 pb-32 pt-3 sm:px-4 md:px-6 lg:pb-10">
          {children}
        </main>

        {user ? <GlobalTransactionCta /> : null}

        {/* BOTTOM NAV — mobile only, mirrors the Flutter app's 5 tabs */}
        <nav
          className="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-white lg:hidden"
          style={{ paddingBottom: "var(--safe-bottom)" }}
        >
          <div className="grid h-16 grid-cols-5">
            {bottomNavItems.map((item) => {
              const active = isActive(pathname, item.href);

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className="flex flex-col items-center justify-center gap-0.5"
                >
                  <span
                    className={cn(
                      "flex h-7 w-14 items-center justify-center rounded-full transition-colors",
                      active ? "bg-brand-600/15 text-brand-700" : "text-muted",
                    )}
                  >
                    <item.icon className="h-5 w-5" strokeWidth={active ? 2.4 : 2} />
                  </span>
                  <span
                    className={cn(
                      "text-[11px] leading-none",
                      active ? "font-semibold text-brand-700" : "text-muted",
                    )}
                  >
                    {item.label}
                  </span>
                </Link>
              );
            })}
          </div>
        </nav>
      </div>
    </div>
  );
}
