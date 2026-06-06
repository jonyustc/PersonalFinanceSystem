export type User = {
  id: string;
  full_name: string;
  email: string;
  currency: string;
  default_currency?: string;
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
  type:
    | "cash"
    | "bank"
    | "card"
    | "mobile_banking"
    | "debit_card"
    | "credit_card"
    | "CASH"
    | "BANK"
    | "MOBILE_BANKING"
    | "DEBIT_CARD"
    | "CREDIT_CARD";
  balance: string;
  opening_balance: string;
  currency: string;
  notes?: string | null;
  is_active: boolean;
  account_subtype?: string | null;
  institution_name?: string | null;
  color?: string | null;
  icon?: string | null;
  archived: boolean;
  credit_limit?: string | null;
  current_outstanding?: string;
  billing_cycle_day?: number | null;
  payment_due_day?: number | null;
  card_details?: CreditCardDetails | null;
};

export type AccountType = Account["type"];

export type AccountCreatePayload = {
  name: string;
  type: AccountType;
  opening_balance: number;
  currency: string;
  notes?: string | null;
  is_active: boolean;
  account_subtype?: string | null;
  institution_name?: string | null;
  color?: string | null;
  icon?: string | null;
  archived?: boolean;
  credit_limit?: number | null;
  current_outstanding?: number;
  billing_cycle_day?: number | null;
  payment_due_day?: number | null;
  card_details?: CreditCardDetailsPayload | null;
};

export type AccountUpdatePayload = {
  name?: string;
  type?: AccountType;
  opening_balance?: number;
  currency?: string;
  notes?: string | null;
  is_active?: boolean;
  account_subtype?: string | null;
  institution_name?: string | null;
  color?: string | null;
  icon?: string | null;
  archived?: boolean;
  credit_limit?: number | null;
  current_outstanding?: number | null;
  billing_cycle_day?: number | null;
  payment_due_day?: number | null;
  card_details?: CreditCardDetailsPayload | null;
};

export type CreditCardDetails = {
  account_id: string;
  credit_limit: string;
  available_credit: string;
  statement_day?: number | null;
  due_day?: number | null;
  minimum_payment_percent: string;
  annual_fee: string;
  interest_rate: string;
  auto_pay_enabled: boolean;
};

export type CreditCardDetailsPayload = {
  credit_limit: number;
  statement_day?: number | null;
  due_day?: number | null;
  minimum_payment_percent?: number;
  annual_fee?: number;
  interest_rate?: number;
  auto_pay_enabled?: boolean;
};

export type AccountSummary = {
  total_assets: string;
  liabilities: string;
  net_worth: string;
  card_debt: string;
  cash_balance: string;
  credit_used: string;
};

export type AccountAnalytics = {
  distribution: { type: AccountType; total: string; count: number }[];
  debt_vs_assets: { label: string; amount: string }[];
  balance_trend: { date: string; balance: string }[];
  net_worth_trend: { date: string; net_worth: string }[];
};

export type TransferPayload = {
  from_account_id: string;
  to_account_id: string;
  amount: number;
  fee: number;
  notes?: string | null;
  is_card_payment?: boolean;
};

export type Category = {
  id: string;
  name: string;
  type: "expense" | "income";
  parent_id?: string | null;
  color?: string | null;
  icon?: string | null;

  children?: Category[];
};

export type CategoryType = Category["type"];

export type CategoryCreatePayload = {
  name: string;
  type: CategoryType;
  parent_id?: string | null;
  color?: string | null;
  icon?: string | null;
};

export type CategoryUpdatePayload = Partial<CategoryCreatePayload>;

export type Transaction = {
  id: string;
  account_id: string;
  category_id?: string | null;
  transfer_account_id?: string | null;
  type: "expense" | "income" | "transfer";
  txn_type?: "expense" | "income" | "transfer";
  payment_method?: string | null;
  transaction_type?: "expense" | "income" | "transfer" | "CARD_PAYMENT" | "CARD_SPENDING" | null;
  amount: string;
  txn_date: string;
  transaction_date?: string | null;
  description?: string | null;
  merchant_name?: string | null;
  tags: string[];
  location?: string | null;
  attachment_url?: string | null;
  recurring_rule?: string | null;
  parent_transaction_id?: string | null;
  is_split?: boolean;
  is_recurring?: boolean;
  transaction_status?: string;
  reference_number?: string | null;
};

export type TransactionType = Transaction["type"];

export type TransactionCreatePayload = {
  account_id: string;
  transfer_account_id?: string | null;
  category_id?: string | null;

  type: "expense" | "income" | "transfer";
  transaction_type?: "expense" | "income" | "transfer" | "CARD_PAYMENT" | "CARD_SPENDING" | null;
  payment_method?: string | null;

  amount: number;
  txn_date?: string;

  is_emergency?: boolean;
  description?: string | null;
  merchant_name?: string | null;
  tags?: string[];
  location?: string | null;
  attachment_url?: string | null;
  recurring_rule?: "daily" | "weekly" | "monthly" | "yearly" | null;
  is_recurring?: boolean;
  transaction_status?: "posted" | "pending" | "void";
  reference_number?: string | null;
};

export type TransactionUpdatePayload = Partial<TransactionCreatePayload>;

export type TransactionFilters = {
  start_date?: string;
  end_date?: string;
  from_date?: string;
  to_date?: string;
  search?: string;
  type?: TransactionType;
  account_source?: "cash" | "bank" | "card";
  account_id?: string;
  category_id?: string;
  merchant?: string;
  tags?: string;
  recurring_only?: boolean;
  transfer_only?: boolean;
  min_amount?: number;
  max_amount?: number;
  limit?: number;
  offset?: number;
};

export type TransactionAnalytics = {
  total_income: string;
  total_expense: string;
  net_cashflow: string;
  average_daily_spending: string;
  top_categories: { label: string; amount: string }[];
  top_merchants: { label: string; amount: string }[];
  income_vs_expense: { label: string; amount: string }[];
  spending_trend: { date: string; type: TransactionType; amount: string }[];
  expense_heatmap: { date: string; type: TransactionType; amount: string }[];
  account_breakdown: { label: string; amount: string | number }[];
};

export type MonthlySummary = {
  month: number;
  year?: number;
  total_income: string;
  total_expense: string;
  savings: string;
};

export type ReportRow = {
  id?: string;
  parent_id?: string;
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
  month: number | string;
  year?: number;
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

export type PortfolioTxnType = "buy" | "sell" | "deposit" | "withdraw" | "income";

export type Stock = {
  id: string;
  symbol: string;
  name: string;
  exchange?: string | null;
  currency: string;
  last_price: string;
};

export type PortfolioTransaction = {
  id: string;
  stock_id?: string | null;
  broker_account_id?: string | null;
  txn_type: PortfolioTxnType;
  quantity: string;
  price: string;
  fees: string;
  total_amount: string;
  cash_flow: string;
  txn_date: string;
  notes?: string | null;
  stock?: Stock | null;
};

export type PortfolioTransactionPayload = {
  stock_id?: string | null;
  stock?: {
    symbol: string;
    name: string;
    exchange?: string | null;
    currency: string;
    last_price: number;
  } | null;
  broker_account_id?: string | null;
  txn_type: PortfolioTxnType;
  quantity?: number;
  price: number;
  fees?: number | null;
  txn_date: string;
  notes?: string | null;
};

export type PortfolioHolding = {
  stock: Stock;
  quantity: string;
  avg_buy_price: string;
  invested_amount: string;
  market_value: string;
  unrealized_profit_loss: string;
  unrealized_percent: string;
  realized_profit_loss: string;
  dividend_income: string;
  total_profit_loss: string;
};

export type PortfolioDividendReportRow = {
  stock_id: string;
  stock_name: string;
  year: number;
  dividend_gain: string;
  record_date?: string | null;
  cash_dividend_percent?: string | null;
  eligible_quantity?: string | null;
  source?: string;
};

export type PortfolioSummaryV2 = {
  total_principal_investment: string;
  invested_capital: string;
  active_cost_basis: string;
  current_equity_value: string;
  unrealized_gain_loss: string;
  cash_balance: string;
  total_portfolio_value: string;
  total_realized_capital_gain_loss: string;
  dividend_income: string;
  total_realized_profit: string;
  overall_profit_loss: string;
  return_percent: string;
  broker_accounts: { id: string; name: string; balance: string; currency: string }[];
  holdings: PortfolioHolding[];
  dividend_report: PortfolioDividendReportRow[];
  auto_dividend_report?: PortfolioDividendReportRow[];
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

export type SimpleDashboardAccount = {
  id: string;
  name: string;
  type: "CASH" | "BANK" | "MOBILE_BANKING";
  balance: string;
  currency: string;
};

export type SimpleDashboardCard = {
  id: string;
  name: string;
  credit_limit: string;
  current_outstanding: string;
  available_limit: string;
  used_percentage: string;
  monthly_spending: string;
  monthly_payment: string;
  billing_cycle_day?: number | null;
  payment_due_day?: number | null;
};

export type SimpleDashboardResponse = {
  month: string;
  active_accounts_balance: {
    total_balance: string;
    accounts: SimpleDashboardAccount[];
  };
  card_summary: {
    total_card_spending: string;
    total_card_payment: string;
    total_card_outstanding: string;
    cards: SimpleDashboardCard[];
  };
};
