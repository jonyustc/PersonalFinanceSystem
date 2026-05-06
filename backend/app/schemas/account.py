from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


# ===============================
# 🔹 TYPES
# ===============================
AccountType = Literal["cash", "bank", "card"]


# ===============================
# 🔹 CREATE
# ===============================
class AccountCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: AccountType

    opening_balance: Decimal = Field(default=Decimal("0"), ge=0)

    currency: str = Field(default="USD", min_length=3, max_length=3)
    notes: str | None = None
    is_active: bool = True


# ===============================
# 🔹 UPDATE
# ===============================
class AccountUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    type: AccountType | None = None

    currency: str | None = Field(default=None, min_length=3, max_length=3)
    notes: str | None = None
    is_active: bool | None = None


# ===============================
# 🔹 RESPONSE
# ===============================
class AccountResponse(BaseModel):
    id: UUID   # ✅ FIX (was str ❌)

    name: str
    type: AccountType

    balance: Decimal
    currency: str
    notes: str | None
    is_active: bool

    class Config:
        from_attributes = True
