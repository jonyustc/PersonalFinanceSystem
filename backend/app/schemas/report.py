from decimal import Decimal

from pydantic import BaseModel


class ReportRow(BaseModel):
    id: str | None = None
    parent_id: str | None = None
    label: str
    amount: Decimal


class MonthlyExpenseReport(BaseModel):
    month: int
    year: int
    total: Decimal
    categories: list[ReportRow]


class TrendPoint(BaseModel):
    period: str
    amount: Decimal


class CardReportCard(BaseModel):
    id: str
    name: str
    credit_limit: Decimal
    current_outstanding: Decimal
    spent: Decimal
    paid: Decimal


class CardReportTransaction(BaseModel):
    id: str
    card_id: str | None = None
    card_name: str
    account_name: str | None = None
    amount: Decimal
    txn_date: str
    description: str | None = None
    merchant_name: str | None = None


class CardReport(BaseModel):
    from_date: str | None = None
    to_date: str | None = None
    total_spent: Decimal
    total_paid: Decimal
    net_change: Decimal
    total_outstanding: Decimal
    cards: list[CardReportCard]
    spent_history: list[CardReportTransaction]
    payment_history: list[CardReportTransaction]
