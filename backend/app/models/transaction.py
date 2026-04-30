import enum
from datetime import datetime
from decimal import Decimal
from typing import List

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import TimestampMixin, UUIDMixin


class TransactionType(str, enum.Enum):
    EXPENSE = "expense"
    INCOME = "income"
    TRANSFER = "transfer"


class Transaction(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "transactions"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    account_id: Mapped[UUID] = mapped_column(UUID(as_uuid=True), ForeignKey(
        "accounts.id", ondelete="RESTRICT"), index=True)
    category_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("categories.id", ondelete="SET NULL"), index=True, nullable=True)
    transfer_account_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=True)
    txn_type: Mapped[TransactionType] = mapped_column(
        String(20), nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    txn_date: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    tags: Mapped[List[str]] = mapped_column(
        ARRAY(String), default=list, nullable=False)

    user = relationship("User", back_populates="transactions")
    account = relationship(
        "Account", back_populates="transactions", foreign_keys=[account_id])
    transfer_account = relationship(
        "Account", foreign_keys=[transfer_account_id])
    category = relationship("Category", back_populates="transactions")
