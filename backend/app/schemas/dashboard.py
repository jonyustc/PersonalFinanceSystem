# app/schemas/dashboard.py

from decimal import Decimal
from datetime import datetime
from typing import List

from pydantic import BaseModel

from app.schemas.transaction import TransactionResponse


# =========================
# CATEGORY PIE CHART
# =========================
class CategoryExpense(BaseModel):
    label: str
    value: Decimal

    class Config:
        from_attributes = True


# =========================
# MONTHLY TREND (LINE CHART)
# =========================
class MonthlyCashflow(BaseModel):
    month: str
    income: Decimal
    expense: Decimal

    class Config:
        from_attributes = True


# =========================
# BUDGET SUMMARY
# =========================
class BudgetCategory(BaseModel):
    category_id: str
    category_name: str
    budget: Decimal
    spent: Decimal
    remaining: Decimal = Decimal("0")
    used_percentage: Decimal = Decimal("0")
    overspending: bool = False

    class Config:
        from_attributes = True


class BudgetSummary(BaseModel):
    month: str
    income: Decimal
    opening_balance: Decimal = Decimal("0")
    total_balance: Decimal = Decimal("0")
    total_budget: Decimal = Decimal("0")
    total_spent: Decimal = Decimal("0")
    planned_balance: Decimal = Decimal("0")
    actual_balance: Decimal = Decimal("0")
    categories: List[BudgetCategory]

    class Config:
        from_attributes = True


# =========================
# MAIN DASHBOARD RESPONSE
# =========================
class DashboardResponse(BaseModel):
    total_cash: Decimal
    total_bank_balance: Decimal
    total_expense_this_month: Decimal
    total_income_this_month: Decimal
    savings: Decimal
    net_worth: Decimal
    investment_value: Decimal

    recent_transactions: List[TransactionResponse]

    # ✅ Fixed (was generic ChartPoint)
    expense_by_category: List[CategoryExpense]

    # ✅ Fixed (now proper structure for line chart)
    monthly_cashflow: List[MonthlyCashflow]

    # ✅ NEW (required for BudgetVsActual component)
    budget_summary: BudgetSummary

    class Config:
        from_attributes = True


class SimpleDashboardAccount(BaseModel):
    id: str
    name: str
    type: str
    balance: Decimal
    currency: str


class SimpleDashboardActiveBalance(BaseModel):
    total_balance: Decimal
    accounts: list[SimpleDashboardAccount]


class SimpleDashboardCard(BaseModel):
    id: str
    name: str
    credit_limit: Decimal
    current_outstanding: Decimal
    available_limit: Decimal
    used_percentage: Decimal
    monthly_spending: Decimal
    monthly_payment: Decimal
    billing_cycle_day: int | None
    payment_due_day: int | None


class SimpleDashboardCardSummary(BaseModel):
    total_card_spending: Decimal
    total_card_payment: Decimal
    total_card_outstanding: Decimal
    cards: list[SimpleDashboardCard]


class SimpleDashboardResponse(BaseModel):
    month: str
    active_accounts_balance: SimpleDashboardActiveBalance
    card_summary: SimpleDashboardCardSummary
