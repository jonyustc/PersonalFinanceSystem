# app/schemas/budget.py

from uuid import UUID
from decimal import Decimal
from typing import List
from pydantic import BaseModel, Field, field_validator
import re


# =========================
# CREATE
# =========================
class BudgetCreate(BaseModel):
    category_id: UUID
    amount: Decimal = Field(gt=0)
    month: str  # "YYYY-MM"

    @field_validator("month")
    @classmethod
    def validate_month(cls, v):
        if not re.match(r"^\d{4}-\d{2}$", v):
            raise ValueError("month must be in YYYY-MM format")
        return v


# =========================
# UPDATE
# =========================
class BudgetUpdate(BaseModel):
    amount: Decimal = Field(gt=0)


# =========================
# RESPONSE
# =========================
class BudgetResponse(BaseModel):
    id: UUID
    category_id: UUID
    amount: Decimal
    month: str

    class Config:
        from_attributes = True


# =========================
# 🔥 BUDGET VS ACTUAL (IMPORTANT)
# =========================
class BudgetSummaryItem(BaseModel):
    category_id: UUID
    category_name: str
    budget: float
    spent: float


class BudgetSummaryResponse(BaseModel):
    month: str
    income: float
    categories: List[BudgetSummaryItem]
