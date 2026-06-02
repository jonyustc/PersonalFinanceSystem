from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class MonthlyIncomeBase(BaseModel):
    month: str = Field(..., example="2026-05")
    amount: Decimal
    opening_balance: Decimal = Decimal("0")


class MonthlyIncomeCreate(MonthlyIncomeBase):
    pass


class MonthlyIncomeResponse(BaseModel):
    id: UUID | None = None
    month: str
    amount: Decimal
    opening_balance: Decimal = Decimal("0")

    class Config:
        from_attributes = True
