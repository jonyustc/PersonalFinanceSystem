from uuid import UUID
from decimal import Decimal
from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


# ================= TYPES =================

TransactionType = Literal["expense", "income", "transfer"]
PaymentMethod = Literal["cash", "bank", "card"]


# ================= CREATE =================

class TransactionCreate(BaseModel):
    account_id: UUID
    transfer_account_id: Optional[UUID] = None
    category_id: Optional[UUID] = None

    type: TransactionType
    payment_method: Optional[PaymentMethod] = None

    amount: Decimal = Field(gt=0)
    txn_date: datetime = Field(default_factory=datetime.utcnow)

    is_emergency: bool = False
    description: Optional[str] = None


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

    is_emergency: bool
    description: Optional[str]

    class Config:
        from_attributes = True
