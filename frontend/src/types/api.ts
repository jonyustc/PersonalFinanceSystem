export type User = {
  id: string;
  full_name: string;
  email: string;
  default_currency: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type AuthResponse = {
  access_token: string;
  refresh_token: string;
  token_type: "bearer";
  user: User;
};

export type LoginPayload = {
  email: string;
  password: string;
};

export type RegisterPayload = LoginPayload & {
  full_name: string;
};

export type Account = {
  id: string;
  name: string;
  type: "cash" | "bank" | "debit_card" | "credit_card" | "mobile_banking";
  opening_balance: string;
  current_balance: string;
  currency: string;
  notes?: string | null;
  is_active: boolean;
};

export type AccountType = Account["type"];

export type AccountCreatePayload = {
  name: string;
  type: AccountType;
  opening_balance: number;
  currency: string;
  notes?: string | null;
  is_active: boolean;
};

export type AccountUpdatePayload = {
  name?: string;
  type?: AccountType;
  currency?: string;
  notes?: string | null;
  is_active?: boolean;
};

export type Category = {
  id: string;
  name: string;
  type: "expense" | "income";
  color?: string | null;
  icon?: string | null;
  created_at: string;
  updated_at: string;
};

export type CategoryType = Category["type"];

export type CategoryCreatePayload = {
  name: string;
  type: CategoryType;
  color?: string | null;
  icon?: string | null;
};

export type CategoryUpdatePayload = Partial<CategoryCreatePayload>;

export type Transaction = {
  id: string;
  account_id: string;
  category_id?: string | null;
  transfer_account_id?: string | null;
  txn_type: "expense" | "income" | "transfer";
  amount: string;
  txn_date: string;
  description?: string | null;
  tags: string[];
};

export type TransactionType = Transaction["txn_type"];

export type TransactionCreatePayload = {
  account_id: string;
  category_id?: string | null;
  transfer_account_id?: string | null;
  txn_type: TransactionType;
  amount: number;
  txn_date: string;
  description?: string | null;
  tags: string[];
};

export type TransactionUpdatePayload = Partial<TransactionCreatePayload>;

export type TransactionFilters = {
  start_date?: string;
  end_date?: string;
  account_id?: string;
  category_id?: string;
  limit?: number;
  offset?: number;
};

export type MonthlySummary = {
  month: number;
  year: number;
  total_income: string;
  total_expense: string;
  savings: string;
};

export type ReportRow = {
  label: string;
  amount: string;
};

export type MonthlyExpenseReport = {
  month: number;
  year: number;
  total: string;
  categories: ReportRow[];
};

export type TrendPoint = {
  period: string;
  amount: string;
};

export type Budget = {
  id: string;
  category_id: string;
  month: number;
  year: number;
  amount: string;
  spent: string;
  remaining: string;
  overspending: boolean;
  created_at: string;
  updated_at: string;
};

export type BudgetCreatePayload = {
  category_id: string;
  month: number;
  year: number;
  amount: number;
};

export type BudgetUpdatePayload = {
  amount: number;
};

export type StockCreatePayload = {
  symbol: string;
  name: string;
  exchange?: string | null;
  currency: string;
  last_price: number;
};

export type PortfolioTransactionCreatePayload = {
  stock: StockCreatePayload;
  txn_type: "buy" | "sell";
  quantity: number;
  price: number;
  fees?: number;
  txn_date: string;
};

export type PortfolioTransactionResponse = {
  id: string;
  stock_id: string;
  txn_type: "buy" | "sell";
  quantity: string;
  price: string;
  fees: string;
  txn_date: string;
  created_at: string;
  updated_at: string;
};

export type DividendCreatePayload = {
  stock_id: string;
  amount: number;
  payment_date: string;
  notes?: string | null;
};

export type DividendResponse = {
  id: string;
  stock_id: string;
  amount: string;
  payment_date: string;
  notes?: string | null;
  created_at: string;
  updated_at: string;
};

export type StockHolding = {
  stock: {
    id: string;
    symbol: string;
    name: string;
    exchange?: string | null;
    currency: string;
    last_price: string;
    created_at: string;
    updated_at: string;
  };
  quantity: string;
  avg_buy_price: string;
  realized_profit_loss: string;
  market_value: string;
  unrealized_profit_loss: string;
  created_at: string;
  updated_at: string;
};

export type PortfolioSummary = {
  total_market_value: string;
  total_cost_basis: string;
  total_unrealized_profit_loss: string;
  total_realized_profit_loss: string;
  holdings: StockHolding[];
};

export type DashboardResponse = {
  total_cash: string;
  total_bank_balance: string;
  total_expense_this_month: string;
  total_income_this_month: string;
  savings: string;
  net_worth: string;
  investment_value: string;
  recent_transactions: Transaction[];
  expense_by_category: { label: string; value: string }[];
  monthly_cashflow: { label: string; value: string }[];
};
