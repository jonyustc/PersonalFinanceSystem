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

import { Button } from "@/components/ui/button";
import { GlobalTransactionCta } from "@/components/transactions/global-transaction-cta";
import { cn } from "@/lib/utils";
import { getMe, logout } from "@/services/auth-service";
import {
  clearAuthSession,
  getAccessToken,
  getStoredUser,
} from "@/services/token-store";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/dashboard/accounts", label: "Accounts", icon: Wallet },
  { href: "/dashboard/categories", label: "Categories", icon: Tags },
  { href: "/dashboard/budgets", label: "Budgets", icon: PieChart },
  { href: "/dashboard/transactions", label: "Transactions", icon: ReceiptText },
  { href: "/dashboard/portfolio", label: "Stocks", icon: TrendingUp },
  { href: "/dashboard/reports", label: "Reports", icon: BarChart3 },
];

export function DashboardShell({ children }: any) {
  const pathname = usePathname();
  const router = useRouter();

  const [open, setOpen] = useState(false);
  const [user, setUser] = useState<any>(null);

  // ✅ safer client auth check
  useEffect(() => {
    let active = true;
    const u = getStoredUser();
    const token = getAccessToken();
    if (!u || !token) {
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
    <div className="min-h-screen bg-gray-50 flex">
      {/* SIDEBAR */}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-40 w-64 bg-white border-r transition-transform",
          open ? "translate-x-0" : "-translate-x-full",
          "lg:translate-x-0",
        )}
      >
        <div className="flex items-center justify-between p-4 border-b">
          <Link href="/dashboard" className="font-semibold">
            Finance System
          </Link>

          <button onClick={() => setOpen(false)} className="lg:hidden">
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* MENU */}
        <nav className="p-3 space-y-1 overflow-y-auto h-full">
          {navItems.map((item) => {
            const active = pathname === item.href;

            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                className={cn(
                  "flex items-center gap-3 px-3 py-2 rounded-md text-sm",
                  active
                    ? "bg-green-100 text-green-700"
                    : "text-gray-600 hover:bg-gray-100",
                )}
              >
                <item.icon className="h-4 w-4" />
                {item.label}
              </Link>
            );
          })}
        </nav>
      </aside>

      {/* OVERLAY */}
      {open && (
        <div
          className="fixed inset-0 bg-black/20 z-30 lg:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      {/* MAIN */}
      <div className="min-w-0 flex-1 lg:ml-64 flex flex-col">
        {/* HEADER */}
        <header className="bg-white border-b h-14 flex items-center justify-between px-4">
          <button onClick={() => setOpen(true)} className="lg:hidden">
            <Menu className="h-5 w-5" />
          </button>

          <div className="ml-auto flex items-center gap-3">
            <div className="text-right hidden sm:block">
              <p className="text-sm font-medium">{user?.full_name || "User"}</p>
              <p className="text-xs text-gray-500">{user?.email}</p>
            </div>

            <Button variant="secondary" onClick={handleLogout}>
              <LogOut className="h-4 w-4" />
              Logout
            </Button>
          </div>
        </header>

        {/* CONTENT */}
        <main className="min-w-0 flex-1 overflow-x-hidden px-3 pb-24 pt-0 sm:px-4 md:px-6 md:pb-10 md:pt-3">{children}</main>
        {user ? <GlobalTransactionCta /> : null}
      </div>
    </div>
  );
}
