from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.models.transaction import TransactionType
from app.schemas.common import Timestamped


class TransactionBase(BaseModel):
    account_id: UUID
    category_id: UUID | None = None
    transfer_account_id: UUID | None = None
    txn_type: TransactionType
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)
    txn_date: datetime
    description: str | None = None
    tags: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_transfer(self):
        if self.txn_type == TransactionType.TRANSFER and not self.transfer_account_id:
            raise ValueError("transfer_account_id is required for transfers")
        if self.txn_type != TransactionType.TRANSFER and self.category_id is None:
            raise ValueError("category_id is required for income and expense transactions")
        return self


class TransactionCreate(TransactionBase):
    pass


class TransactionUpdate(BaseModel):
    account_id: UUID | None = None
    category_id: UUID | None = None
    transfer_account_id: UUID | None = None
    txn_type: TransactionType | None = None
    amount: Decimal | None = Field(default=None, gt=0, max_digits=14, decimal_places=2)
    txn_date: datetime | None = None
    description: str | None = None
    tags: list[str] | None = None


class TransactionResponse(Timestamped):
    account_id: UUID
    category_id: UUID | None
    transfer_account_id: UUID | None
    txn_type: TransactionType
    amount: Decimal
    txn_date: datetime
    description: str | None
    tags: list[str]


class TransactionListResponse(BaseModel):
    total: int
    limit: int
    offset: int
    items: list[TransactionResponse]


class MonthlySummary(BaseModel):
    month: int
    year: int
    total_income: Decimal
    total_expense: Decimal
    savings: Decimal
