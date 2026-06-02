// frontend/src/services/fund-service.ts

import { apiRequest } from "@/services/api";

export type FundMember = "mine" | "friend" | "untagged";

export type FundTransaction = {
  id: string;
  amount: number;
  type: "expense" | "income" | "transfer";
  txn_date: string;
  description?: string | null;
  merchant_name?: string | null;
  tags: string[];
  category_id?: string | null;
  member: FundMember;
};

export type FundSummary = {
  account_id: string;
  account_name: string;
  currency: string;
  fund_balance: number;
  total_contributed: number;
  total_spent: number;
  outstanding_amount: number;
  my_spent: number;
  friend_spent: number;
  untagged_spent: number;
  my_spent_pct: number;
  friend_spent_pct: number;
  untagged_pct: number;
  recent_transactions: FundTransaction[];
};

export type FundTransactions = {
  mine: FundTransaction[];
  friend: FundTransaction[];
  untagged: FundTransaction[];
};

export const fetchFundSummary = (accountId: string) =>
  apiRequest<FundSummary>(`/accounts/${accountId}/summary`);

export const fetchFundTransactions = (accountId: string) =>
  apiRequest<FundTransactions>(`/accounts/${accountId}/transactions`);

// Tag helpers — appended to transaction tags when creating/updating
export const FUND_TAG_MINE = "fund:mine";
export const FUND_TAG_FRIEND = "fund:friend";

// Use these when creating a transaction for the fund:
// tags: [FUND_TAG_MINE]   → your expense
// tags: [FUND_TAG_FRIEND] → friend's expense
