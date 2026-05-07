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
