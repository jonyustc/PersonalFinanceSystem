from decimal import Decimal

from pydantic import BaseModel, Field

from app.models.account import AccountType
from app.schemas.common import Timestamped


class AccountBase(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: AccountType
    opening_balance: Decimal = Field(default=Decimal("0"), ge=0)
    currency: str = Field(default="USD", min_length=3, max_length=3)
    notes: str | None = None
    is_active: bool = True


class AccountCreate(AccountBase):
    pass


class AccountUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    type: AccountType | None = None
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    notes: str | None = None
    is_active: bool | None = None


class AccountResponse(Timestamped):
    name: str
    type: AccountType
    opening_balance: Decimal
    current_balance: Decimal
    currency: str
    notes: str | None
    is_active: bool
