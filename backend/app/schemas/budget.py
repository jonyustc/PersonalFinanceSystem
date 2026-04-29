from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.common import Timestamped


class BudgetCreate(BaseModel):
    category_id: UUID
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=2100)
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)


class BudgetUpdate(BaseModel):
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)


class BudgetResponse(Timestamped):
    category_id: UUID
    month: int
    year: int
    amount: Decimal


class BudgetComparison(BudgetResponse):
    spent: Decimal
    remaining: Decimal
    overspending: bool
