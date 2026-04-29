"use client";

import {
  BarChart3,
  CreditCard,
  LayoutDashboard,
  LogOut,
  Menu,
  PieChart,
  ReceiptText,
  Tags,
  Wallet,
  X,
} from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { logout } from "@/services/auth-service";
import { getStoredUser } from "@/services/token-store";
import type { User } from "@/types/api";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/dashboard/accounts", label: "Accounts", icon: Wallet },
  { href: "/dashboard/categories", label: "Categories", icon: Tags },
  { href: "/dashboard/budgets", label: "Budgets", icon: PieChart },
  { href: "/dashboard/portfolio", label: "Portfolio", icon: BarChart3 },
  { href: "/dashboard/transactions", label: "Transactions", icon: ReceiptText },
  { href: "/dashboard/reports", label: "Reports", icon: BarChart3 },
];

export function DashboardShell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    const stored = getStoredUser();
    if (!stored) {
      router.replace("/auth/login");
      return;
    }
    setUser(stored);
  }, [router]);

  function handleLogout() {
    logout();
    router.replace("/auth/login");
  }

  return (
    <div className="min-h-screen bg-surface">
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-30 w-72 border-r border-line bg-white px-4 py-5 transition-transform lg:translate-x-0",
          open ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex items-center justify-between">
          <Link className="flex items-center gap-3" href="/dashboard">
            <span className="flex h-10 w-10 items-center justify-center rounded-md bg-brand-600 text-white">
              <CreditCard className="h-5 w-5" aria-hidden />
            </span>
            <span>
              <span className="block text-sm font-semibold text-ink">
                Finance System
              </span>
              <span className="block text-xs text-muted">Control center</span>
            </span>
          </Link>
          <button
            className="rounded-md p-2 text-muted lg:hidden"
            onClick={() => setOpen(false)}
            type="button"
          >
            <X className="h-5 w-5" aria-hidden />
          </button>
        </div>
        <nav className="mt-8 space-y-1">
          {navItems.map((item) => {
            const active = pathname === item.href;
            return (
              <Link
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium text-muted transition hover:bg-surface hover:text-ink",
                  active && "bg-brand-50 text-brand-700",
                )}
                href={item.href}
                key={item.href}
                onClick={() => setOpen(false)}
              >
                <item.icon className="h-4 w-4" aria-hidden />
                {item.label}
              </Link>
            );
          })}
        </nav>
      </aside>

      {open ? (
        <button
          className="fixed inset-0 z-20 bg-ink/20 lg:hidden"
          onClick={() => setOpen(false)}
          type="button"
        />
      ) : null}

      <div className="lg:pl-72">
        <header className="sticky top-0 z-10 border-b border-line bg-white/90 backdrop-blur">
          <div className="flex h-16 items-center justify-between px-4 sm:px-6 lg:px-8">
            <button
              className="rounded-md p-2 text-muted lg:hidden"
              onClick={() => setOpen(true)}
              type="button"
            >
              <Menu className="h-5 w-5" aria-hidden />
            </button>
            <div className="ml-auto flex items-center gap-3">
              <div className="hidden text-right sm:block">
                <p className="text-sm font-semibold text-ink">
                  {user?.full_name ?? "User"}
                </p>
                <p className="text-xs text-muted">{user?.email ?? ""}</p>
              </div>
              <Button variant="secondary" onClick={handleLogout}>
                <LogOut className="h-4 w-4" aria-hidden />
                Logout
              </Button>
            </div>
          </div>
        </header>
        <main className="px-4 py-6 sm:px-6 lg:px-8">{children}</main>
      </div>
    </div>
  );
}
