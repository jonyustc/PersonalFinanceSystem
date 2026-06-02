import { apiRequest } from "@/services/api";
import type {
  Account,
  AccountAnalytics,
  AccountCreatePayload,
  AccountSummary,
  AccountUpdatePayload,
  Budget,
  BudgetCreatePayload,
  BudgetUpdatePayload,
  Category,
  CategoryCreatePayload,
  CategoryUpdatePayload,
  DashboardResponse,
  MonthlyExpenseReport,
  ReportRow,
  SimpleDashboardResponse,
  Transaction,
  TransactionAnalytics,
  TransactionCreatePayload,
  TransactionFilters,
  TransactionUpdatePayload,
  TransferPayload,
  TrendPoint,
} from "@/types/api";

/* =========================
   UTILS
========================= */

function buildQuery(params: Record<string, any>) {
  const query = new URLSearchParams();

  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      query.set(key, String(value));
    }
  });

  return query.toString();
}

/* =========================
   DASHBOARD
========================= */

export const fetchDashboard = (month?: string) =>
  apiRequest<DashboardResponse>(`/dashboard${month ? `?month=${month}` : ""}`);

export const fetchDashboardFull = (month: string) =>
  apiRequest<DashboardResponse>(`/dashboard/full-summary?month=${month}`);

export const fetchSimpleDashboard = (month: string) =>
  apiRequest<SimpleDashboardResponse>(`/dashboard/simple?month=${month}`);

/* =========================
   💳 CARD DASHBOARD (FIXED)
========================= */

export type CardDashboardResponse = {
  total_outstanding: number;
  monthly_spent: number;
  payments: number;
  utilization: number;
  cards: {
    id: string;
    name: string;
    balance: number;
    limit: number;
    utilization: number;
  }[];
};

export const fetchCardDashboard = (month: string) =>
  apiRequest<CardDashboardResponse>(`/dashboard/cards?month=${month}`);

/* =========================
   ACCOUNTS
========================= */

export const fetchAccounts = () => apiRequest<Account[]>("/accounts");

export const fetchAccountSummary = () =>
  apiRequest<AccountSummary>("/accounts/summary");

export const fetchAccountAnalytics = () =>
  apiRequest<AccountAnalytics>("/accounts/analytics");

export const fetchAccountNetWorthTrend = () =>
  apiRequest<{ date: string; net_worth: string }[]>(
    "/accounts/net-worth-trend",
  );

export const createAccount = (payload: AccountCreatePayload) =>
  apiRequest<Account>("/accounts", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateAccount = (id: string, payload: AccountUpdatePayload) =>
  apiRequest<Account>(`/accounts/${id}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });

export const deleteAccount = (id: string) =>
  apiRequest<void>(`/accounts/${id}`, {
    method: "DELETE",
  });

export const createTransfer = (payload: TransferPayload) =>
  apiRequest("/transfers", {
    method: "POST",
    body: JSON.stringify(payload),
  });

/* =========================
   CATEGORIES
========================= */

export const fetchCategories = () => apiRequest<Category[]>("/categories");

export const fetchCategoryTree = () =>
  apiRequest<Category[]>("/categories/tree");

export const createCategory = (payload: CategoryCreatePayload) =>
  apiRequest<Category>("/categories", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateCategory = (id: string, payload: CategoryUpdatePayload) =>
  apiRequest<Category>(`/categories/${id}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });

export const deleteCategory = (id: string) =>
  apiRequest<void>(`/categories/${id}`, {
    method: "DELETE",
  });

/* =========================
   BUDGETS
========================= */

export const fetchBudgets = (month: string) =>
  apiRequest<Budget[]>(`/budgets?month=${month}`);

export const createBudget = (payload: BudgetCreatePayload) =>
  apiRequest<Budget>("/budgets", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const upsertBudget = (payload: BudgetCreatePayload) =>
  apiRequest<Budget>("/budgets/upsert", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateBudget = (id: string, payload: BudgetUpdatePayload) =>
  apiRequest<Budget>(`/budgets/${id}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });

export const deleteBudget = (id: string) =>
  apiRequest<void>(`/budgets/${id}`, {
    method: "DELETE",
  });

export const fetchBudgetSummary = (month: string) =>
  apiRequest(`/budgets/summary?month=${month}`);

/* =========================
   TRANSACTIONS
========================= */

type TransactionList = {
  total: number;
  limit: number;
  offset: number;
  next_offset?: number | null;
  items: Transaction[];
};

export const fetchTransactions = (filters: TransactionFilters = {}) => {
  const query = buildQuery({
    limit: filters.limit ?? 50,
    offset: filters.offset ?? 0,
    search: filters.search,
    type: filters.type,
    account_id: filters.account_id,
    category_id: filters.category_id,
    merchant: filters.merchant,
    tags: filters.tags,
    recurring_only: filters.recurring_only,
    transfer_only: filters.transfer_only,
    min_amount: filters.min_amount,
    max_amount: filters.max_amount,
    from_date: filters.from_date,
    to_date: filters.to_date,
  });

  return apiRequest<TransactionList>(`/transactions?${query}`);
};

export const fetchTransactionAnalytics = (filters: TransactionFilters = {}) => {
  const query = buildQuery({
    from_date: filters.from_date,
    to_date: filters.to_date,
  });
  return apiRequest<TransactionAnalytics>(
    `/transactions/analytics${query ? `?${query}` : ""}`,
  );
};

export const createTransaction = (payload: TransactionCreatePayload) =>
  apiRequest<Transaction>("/transactions", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateTransaction = (
  id: string,
  payload: TransactionUpdatePayload,
) =>
  apiRequest<Transaction>(`/transactions/${id}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });

export const deleteTransaction = (id: string) =>
  apiRequest<void>(`/transactions/${id}`, {
    method: "DELETE",
  });

/* =========================
   REPORTS
========================= */

export const fetchMonthlyExpenses = (month: number, year: number) =>
  apiRequest<MonthlyExpenseReport>(
    `/reports/monthly-expenses?month=${month}&year=${year}`,
  );

export const fetchCategorySpending = (params?: {
  from_date?: string;
  to_date?: string;
}) => {
  const query = params
    ? `?${new URLSearchParams(
        Object.entries(params).filter(([, value]) => Boolean(value)) as [
          string,
          string,
        ][],
      ).toString()}`
    : "";

  return apiRequest<ReportRow[]>(`/reports/categories${query}`);
};

export const fetchIncomeReport = (year: number) =>
  apiRequest<ReportRow[]>(`/reports/income?year=${year}`);

export const fetchNetWorthTrend = () =>
  apiRequest<TrendPoint[]>("/reports/net-worth-trend");

export const fetchMonthlyIncome = (month: string) =>
  apiRequest<{ amount: number }>(`/budgets/income?month=${month}`);

export const saveMonthlyIncome = (payload: {
  month: string;
  amount: number;
  opening_balance?: number;
}) =>
  apiRequest("/budgets/income", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const fetchCardAnalytics = (month: string) =>
  apiRequest(`/dashboard/card-analytics?month=${month}`);
