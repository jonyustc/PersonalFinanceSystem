from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, computed_field, field_validator, model_validator


AccountType = Literal[
    "cash",
    "bank",
    "card",
    "mobile_banking",
    "debit_card",
    "credit_card",
    "CASH",
    "BANK",
    "MOBILE_BANKING",
    "DEBIT_CARD",
    "CREDIT_CARD",
]


class CreditCardDetailsBase(BaseModel):
    credit_limit: Decimal = Field(default=Decimal("0"), ge=0)
    statement_day: int | None = Field(default=None, ge=1, le=31)
    due_day: int | None = Field(default=None, ge=1, le=31)
    minimum_payment_percent: Decimal = Field(default=Decimal("0"), ge=0)
    annual_fee: Decimal = Field(default=Decimal("0"), ge=0)
    interest_rate: Decimal = Field(default=Decimal("0"), ge=0)
    auto_pay_enabled: bool = False


class CreditCardDetailsCreate(CreditCardDetailsBase):
    pass


class CreditCardDetailsResponse(CreditCardDetailsBase):
    account_id: UUID
    available_credit: Decimal

    class Config:
        from_attributes = True


class AccountCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: AccountType
    opening_balance: Decimal = Decimal("0")
    currency: str = Field(default="BDT", min_length=3, max_length=3)
    notes: str | None = None
    is_active: bool = True
    account_subtype: str | None = Field(default=None, max_length=30)
    institution_name: str | None = Field(default=None, max_length=120)
    color: str | None = Field(default=None, max_length=20)
    icon: str | None = Field(default=None, max_length=50)
    archived: bool = False
    credit_limit: Decimal | None = Field(default=None, ge=0)
    current_outstanding: Decimal = Field(default=Decimal("0"), ge=0)
    billing_cycle_day: int | None = Field(default=None, ge=1, le=31)
    payment_due_day: int | None = Field(default=None, ge=1, le=31)
    card_details: CreditCardDetailsCreate | None = None

    @field_validator("currency")
    @classmethod
    def uppercase_currency(cls, value: str) -> str:
        return value.upper()

    @model_validator(mode="after")
    def validate_opening_balance(self) -> "AccountCreate":
        if self.type.lower() not in {"card", "credit_card"} and self.opening_balance < 0:
            raise ValueError("Only card accounts may have a negative opening balance")
        return self


class AccountUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    type: AccountType | None = None
    opening_balance: Decimal | None = None
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    notes: str | None = None
    is_active: bool | None = None
    account_subtype: str | None = Field(default=None, max_length=30)
    institution_name: str | None = Field(default=None, max_length=120)
    color: str | None = Field(default=None, max_length=20)
    icon: str | None = Field(default=None, max_length=50)
    archived: bool | None = None
    credit_limit: Decimal | None = Field(default=None, ge=0)
    current_outstanding: Decimal | None = Field(default=None, ge=0)
    billing_cycle_day: int | None = Field(default=None, ge=1, le=31)
    payment_due_day: int | None = Field(default=None, ge=1, le=31)
    card_details: CreditCardDetailsCreate | None = None

    @field_validator("currency")
    @classmethod
    def uppercase_currency(cls, value: str | None) -> str | None:
        return value.upper() if value else value

    @model_validator(mode="after")
    def validate_opening_balance(self) -> "AccountUpdate":
        if (
            self.opening_balance is not None
            and self.type
            and self.type.lower() not in {"card", "credit_card"}
            and self.opening_balance < 0
        ):
            raise ValueError("Only card accounts may have a negative opening balance")
        return self


class AccountResponse(BaseModel):
    id: UUID
    name: str
    type: AccountType
    balance: Decimal
    opening_balance: Decimal
    currency: str
    notes: str | None
    is_active: bool
    account_subtype: str | None = None
    institution_name: str | None = None
    color: str | None = None
    icon: str | None = None
    archived: bool = False
    credit_limit: Decimal | None = None
    current_outstanding: Decimal = Decimal("0")
    billing_cycle_day: int | None = None
    payment_due_day: int | None = None
    card_details: CreditCardDetailsResponse | None = None

    @computed_field
    @property
    def display_balance(self) -> Decimal:
        if self.type.lower() in {"card", "credit_card"}:
            return self.current_outstanding
        return self.balance

    class Config:
        from_attributes = True


class AccountSummaryResponse(BaseModel):
    total_assets: Decimal
    liabilities: Decimal
    net_worth: Decimal
    card_debt: Decimal
    cash_balance: Decimal
    credit_used: Decimal


class AccountDistributionPoint(BaseModel):
    type: AccountType
    total: Decimal
    count: int


class AccountAnalyticsResponse(BaseModel):
    distribution: list[AccountDistributionPoint]
    debt_vs_assets: list[dict[str, Decimal | str]]
    balance_trend: list[dict[str, Decimal | str]]
    net_worth_trend: list[dict[str, Decimal | str]]


class NetWorthTrendPoint(BaseModel):
    date: str
    net_worth: Decimal


class TransferCreate(BaseModel):
    from_account_id: UUID
    to_account_id: UUID
    amount: Decimal = Field(gt=0)
    fee: Decimal = Field(default=Decimal("0"), ge=0)
    notes: str | None = None
    transfer_date: datetime | None = None
    is_card_payment: bool = False

    @model_validator(mode="after")
    def validate_distinct_accounts(self) -> "TransferCreate":
        if self.from_account_id == self.to_account_id:
            raise ValueError("Transfer accounts must be different")
        return self


class TransferResponse(BaseModel):
    id: UUID
    user_id: UUID
    from_account_id: UUID
    to_account_id: UUID
    amount: Decimal
    fee: Decimal
    notes: str | None
    transfer_date: datetime

    class Config:
        from_attributes = True


class BalanceAdjustmentCreate(BaseModel):
    closing_balance: Decimal
    notes: str | None = None


class BalanceHistoryResponse(BaseModel):
    id: UUID
    account_id: UUID
    balance_date: datetime
    closing_balance: Decimal

    class Config:
        from_attributes = True


class CardSummaryResponse(BaseModel):
    account_id: UUID
    account_name: str
    balance: Decimal
    credit_limit: Decimal
    available_credit: Decimal
    utilization: Decimal
    statement_day: int | None
    due_day: int | None
    minimum_payment_percent: Decimal
    minimum_payment_due: Decimal
    auto_pay_enabled: bool
