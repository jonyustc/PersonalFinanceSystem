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
    category_id: int
    category_name: str
    budget: Decimal
    spent: Decimal

    class Config:
        from_attributes = True


class BudgetSummary(BaseModel):
    month: str
    income: Decimal
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
