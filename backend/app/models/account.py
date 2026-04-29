import enum
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, ForeignKey, Numeric, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import TimestampMixin, UUIDMixin


class AccountType(str, enum.Enum):
    CASH = "cash"
    BANK = "bank"
    DEBIT_CARD = "debit_card"
    CREDIT_CARD = "credit_card"
    MOBILE_BANKING = "mobile_banking"


class Account(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "accounts"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    type: Mapped[AccountType] = mapped_column(String(30), nullable=False)
    opening_balance: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=0, nullable=False)
    current_balance: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=0, nullable=False)
    currency: Mapped[str] = mapped_column(
        String(3), default="USD", nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False)

    user = relationship("User", back_populates="accounts")
    transactions = relationship(
        "Transaction", back_populates="account", foreign_keys="Transaction.account_id")
