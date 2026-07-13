# app/schemas/budget.py

from uuid import UUID
from decimal import Decimal
from typing import List, Optional
from pydantic import BaseModel, Field, field_validator
import re


# =========================
# CREATE
# =========================
class BudgetCreate(BaseModel):
    # Optional client-supplied id: an offline client generates the UUID so a
    # replayed create is idempotent and keeps the same id the mobile mirror
    # already stored (no duplicate on the next pull).
    id: Optional[UUID] = None
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
    category_id: str
    category_name: str
    budget: float
    spent: float
    remaining: float
    used_percentage: float
    overspending: bool


class BudgetSummaryResponse(BaseModel):
    month: str
    income: float
    opening_balance: float = 0
    total_balance: float = 0
    total_budget: float = 0
    total_spent: float = 0
    planned_balance: float = 0
    actual_balance: float = 0
    categories: List[BudgetSummaryItem]
