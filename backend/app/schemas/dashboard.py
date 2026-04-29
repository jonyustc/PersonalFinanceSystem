from decimal import Decimal

from pydantic import BaseModel

from app.schemas.transaction import TransactionResponse


class ChartPoint(BaseModel):
    label: str
    value: Decimal


class DashboardResponse(BaseModel):
    total_cash: Decimal
    total_bank_balance: Decimal
    total_expense_this_month: Decimal
    total_income_this_month: Decimal
    savings: Decimal
    net_worth: Decimal
    investment_value: Decimal
    recent_transactions: list[TransactionResponse]
    expense_by_category: list[ChartPoint]
    monthly_cashflow: list[ChartPoint]
