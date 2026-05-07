from uuid import UUID
from decimal import Decimal
from datetime import UTC, datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


# ================= TYPES =================

TransactionType = Literal["expense", "income", "transfer"]
PaymentMethod = Literal["cash", "bank", "card"]
TransactionStatus = Literal["posted", "pending", "void"]
RecurringRule = Literal["daily", "weekly", "monthly", "yearly"]


# ================= CREATE =================

class TransactionCreate(BaseModel):
    account_id: UUID
    transfer_account_id: Optional[UUID] = None
    category_id: Optional[UUID] = None

    type: TransactionType
    payment_method: Optional[PaymentMethod] = None

    amount: Decimal = Field(gt=0)
    txn_date: datetime = Field(default_factory=lambda: datetime.now(UTC))

    is_emergency: bool = False
    description: Optional[str] = None
    merchant_name: Optional[str] = Field(default=None, max_length=160)
    tags: list[str] = Field(default_factory=list)
    location: Optional[str] = Field(default=None, max_length=160)
    attachment_url: Optional[str] = None
    recurring_rule: Optional[RecurringRule] = None
    is_recurring: bool = False
    transaction_status: TransactionStatus = "posted"
    reference_number: Optional[str] = Field(default=None, max_length=80)


# ================= UPDATE =================

class TransactionUpdate(BaseModel):
    account_id: Optional[UUID] = None
    transfer_account_id: Optional[UUID] = None
    category_id: Optional[UUID] = None

    type: Optional[TransactionType] = None
    payment_method: Optional[PaymentMethod] = None

    amount: Optional[Decimal] = Field(default=None, gt=0)
    txn_date: Optional[datetime] = None

    is_emergency: Optional[bool] = None
    description: Optional[str] = None
    merchant_name: Optional[str] = Field(default=None, max_length=160)
    tags: Optional[list[str]] = None
    location: Optional[str] = Field(default=None, max_length=160)
    attachment_url: Optional[str] = None
    recurring_rule: Optional[RecurringRule] = None
    is_recurring: Optional[bool] = None
    transaction_status: Optional[TransactionStatus] = None
    reference_number: Optional[str] = Field(default=None, max_length=80)


# ================= RESPONSE =================

class TransactionResponse(BaseModel):
    id: UUID
    account_id: UUID
    transfer_account_id: Optional[UUID]
    category_id: Optional[UUID]

    type: TransactionType
    payment_method: Optional[PaymentMethod]

    amount: Decimal
    txn_date: datetime
    transaction_date: Optional[datetime] = None

    is_emergency: bool
    description: Optional[str]
    merchant_name: Optional[str] = None
    transaction_type: Optional[str] = None
    transfer_id: Optional[UUID] = None
    tags: list[str] = Field(default_factory=list)
    location: Optional[str] = None
    attachment_url: Optional[str] = None
    recurring_rule: Optional[str] = None
    parent_transaction_id: Optional[UUID] = None
    is_split: bool = False
    is_recurring: bool = False
    transaction_status: str = "posted"
    reference_number: Optional[str] = None

    class Config:
        from_attributes = True


class TransactionListResponse(BaseModel):
    items: list[TransactionResponse]
    total: int
    limit: int
    offset: int
    next_offset: int | None


class SplitItemCreate(BaseModel):
    category_id: Optional[UUID] = None
    amount: Decimal = Field(gt=0)
    description: Optional[str] = None
    merchant_name: Optional[str] = None
    tags: list[str] = Field(default_factory=list)


class SplitTransactionCreate(BaseModel):
    parent: TransactionCreate
    splits: list[SplitItemCreate] = Field(min_length=2)


class BulkTransactionUpdate(BaseModel):
    ids: list[UUID] = Field(min_length=1)
    category_id: Optional[UUID] = None
    tags: Optional[list[str]] = None
    transaction_status: Optional[TransactionStatus] = None


class BulkTransactionDelete(BaseModel):
    ids: list[UUID] = Field(min_length=1)


class TransactionAnalyticsResponse(BaseModel):
    total_income: Decimal
    total_expense: Decimal
    net_cashflow: Decimal
    average_daily_spending: Decimal
    top_categories: list[dict]
    top_merchants: list[dict]
    income_vs_expense: list[dict]
    spending_trend: list[dict]
    expense_heatmap: list[dict]
    account_breakdown: list[dict]
