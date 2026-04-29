import { apiRequest } from "@/services/api";
import type {
  Account,
  AccountCreatePayload,
  AccountUpdatePayload,
  Budget,
  BudgetCreatePayload,
  BudgetUpdatePayload,
  Category,
  CategoryCreatePayload,
  CategoryUpdatePayload,
  DashboardResponse,
  DividendCreatePayload,
  DividendResponse,
  MonthlyExpenseReport,
  MonthlySummary,
  PortfolioSummary,
  PortfolioTransactionCreatePayload,
  PortfolioTransactionResponse,
  ReportRow,
  Transaction,
  TransactionCreatePayload,
  TransactionFilters,
  TransactionUpdatePayload,
  TrendPoint,
} from "@/types/api";

type TransactionList = {
  total: number;
  limit: number;
  offset: number;
  items: Transaction[];
};

export function fetchDashboard() {
  return apiRequest<DashboardResponse>("/dashboard");
}

export function fetchAccounts() {
  return apiRequest<Account[]>("/accounts");
}

export function createAccount(payload: AccountCreatePayload) {
  return apiRequest<Account>("/accounts", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function updateAccount(
  accountId: string,
  payload: AccountUpdatePayload,
) {
  return apiRequest<Account>(`/accounts/${accountId}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
}

export function deleteAccount(accountId: string) {
  return apiRequest<void>(`/accounts/${accountId}`, {
    method: "DELETE",
  });
}

export function fetchCategories() {
  return apiRequest<Category[]>("/categories");
}

export function createCategory(payload: CategoryCreatePayload) {
  return apiRequest<Category>("/categories", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function updateCategory(
  categoryId: string,
  payload: CategoryUpdatePayload,
) {
  return apiRequest<Category>(`/categories/${categoryId}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
}

export function deleteCategory(categoryId: string) {
  return apiRequest<void>(`/categories/${categoryId}`, {
    method: "DELETE",
  });
}

export function fetchPortfolioSummary() {
  return apiRequest<PortfolioSummary>("/portfolio/summary");
}

export function createTrade(payload: PortfolioTransactionCreatePayload) {
  return apiRequest<PortfolioTransactionResponse>("/portfolio/transactions", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function addDividend(payload: DividendCreatePayload) {
  return apiRequest<DividendResponse>("/portfolio/dividends", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function listDividends() {
  return apiRequest<DividendResponse[]>("/portfolio/dividends");
}

export function fetchMonthlyExpenses(month: number, year: number) {
  return apiRequest<MonthlyExpenseReport>(
    `/reports/monthly-expenses?month=${month}&year=${year}`,
  );
}

export function fetchCategorySpending() {
  return apiRequest<ReportRow[]>("/reports/categories");
}

export function fetchIncomeReport(year: number) {
  return apiRequest<ReportRow[]>(`/reports/income?year=${year}`);
}

export function fetchNetWorthTrend() {
  return apiRequest<TrendPoint[]>("/reports/net-worth-trend");
}

export function fetchBudgets(month?: number, year?: number) {
  const params = new URLSearchParams();
  if (month) params.set("month", String(month));
  if (year) params.set("year", String(year));
  const query = params.toString();
  return apiRequest<Budget[]>(`/budgets${query ? `?${query}` : ""}`);
}

export function createBudget(payload: BudgetCreatePayload) {
  return apiRequest<Budget>("/budgets", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function updateBudget(budgetId: string, payload: BudgetUpdatePayload) {
  return apiRequest<Budget>(`/budgets/${budgetId}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
}

export function deleteBudget(budgetId: string) {
  return apiRequest<void>(`/budgets/${budgetId}`, {
    method: "DELETE",
  });
}

export function fetchTransactions(filters: TransactionFilters = {}) {
  const params = new URLSearchParams();
  params.set("limit", String(filters.limit ?? 50));
  params.set("offset", String(filters.offset ?? 0));
  if (filters.start_date) params.set("start_date", filters.start_date);
  if (filters.end_date) params.set("end_date", filters.end_date);
  if (filters.account_id) params.set("account_id", filters.account_id);
  if (filters.category_id) params.set("category_id", filters.category_id);
  return apiRequest<TransactionList>(`/transactions?${params.toString()}`);
}

export function createTransaction(payload: TransactionCreatePayload) {
  return apiRequest<Transaction>("/transactions", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function updateTransaction(
  transactionId: string,
  payload: TransactionUpdatePayload,
) {
  return apiRequest<Transaction>(`/transactions/${transactionId}`, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
}

export function deleteTransaction(transactionId: string) {
  return apiRequest<void>(`/transactions/${transactionId}`, {
    method: "DELETE",
  });
}

export function fetchMonthlySummary(month: number, year: number) {
  return apiRequest<MonthlySummary>(
    `/transactions/monthly-summary?month=${month}&year=${year}`,
  );
}
