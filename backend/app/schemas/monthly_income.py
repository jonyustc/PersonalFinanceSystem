from pydantic import BaseModel
from uuid import UUID
from decimal import Decimal
from pydantic import BaseModel, Field


class MonthlyIncomeBase(BaseModel):
    month: str = Field(..., example="2026-05")
    amount: Decimal


class MonthlyIncomeCreate(MonthlyIncomeBase):
    pass


class MonthlyIncomeResponse(BaseModel):
    id: UUID | None = None   # 🔥 FIX
    month: str
    amount: Decimal

    class Config:
        from_attributes = True
