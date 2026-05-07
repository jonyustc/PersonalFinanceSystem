from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class Account(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "accounts"

    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    name: Mapped[str] = mapped_column(
        String(120),
        nullable=False,
    )

    type: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
    )

    balance: Mapped[Decimal] = mapped_column(
        Numeric(14, 2),
        default=0,
        nullable=False,
    )

    opening_balance: Mapped[Decimal] = mapped_column(
        Numeric(14, 2),
        default=0,
        nullable=False,
    )

    account_subtype: Mapped[str | None] = mapped_column(
        String(30),
        nullable=True,
    )

    institution_name: Mapped[str | None] = mapped_column(
        String(120),
        nullable=True,
    )

    color: Mapped[str | None] = mapped_column(
        String(20),
        nullable=True,
    )

    icon: Mapped[str | None] = mapped_column(
        String(50),
        nullable=True,
    )

    currency: Mapped[str] = mapped_column(
        String(3),
        default="USD",
        nullable=False,
    )

    notes: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )

    archived: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )

    user: Mapped["User"] = relationship(
        "User",
        back_populates="accounts",
    )

    credit_card_details: Mapped["CreditCardDetails | None"] = relationship(
        "CreditCardDetails",
        back_populates="account",
        cascade="all, delete-orphan",
        uselist=False,
    )

    outgoing_transfers: Mapped[list["AccountTransfer"]] = relationship(
        "AccountTransfer",
        foreign_keys="AccountTransfer.from_account_id",
        back_populates="from_account",
    )

    incoming_transfers: Mapped[list["AccountTransfer"]] = relationship(
        "AccountTransfer",
        foreign_keys="AccountTransfer.to_account_id",
        back_populates="to_account",
    )

    balance_history: Mapped[list["AccountBalanceHistory"]] = relationship(
        "AccountBalanceHistory",
        back_populates="account",
        cascade="all, delete-orphan",
    )


class CreditCardDetails(TimestampMixin, Base):
    __tablename__ = "credit_card_details"

    account_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("accounts.id", ondelete="CASCADE"),
        primary_key=True,
    )
    credit_limit: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    available_credit: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    statement_day: Mapped[int | None] = mapped_column(Integer, nullable=True)
    due_day: Mapped[int | None] = mapped_column(Integer, nullable=True)
    minimum_payment_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), default=0, nullable=False)
    annual_fee: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    interest_rate: Mapped[Decimal] = mapped_column(Numeric(6, 3), default=0, nullable=False)
    auto_pay_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    account: Mapped["Account"] = relationship("Account", back_populates="credit_card_details")


class AccountTransfer(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "account_transfers"

    user_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    from_account_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False, index=True)
    to_account_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    fee: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    notes: Mapped[str | None] = mapped_column(String, nullable=True)
    transfer_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    from_account: Mapped["Account"] = relationship("Account", foreign_keys=[from_account_id], back_populates="outgoing_transfers")
    to_account: Mapped["Account"] = relationship("Account", foreign_keys=[to_account_id], back_populates="incoming_transfers")
    user: Mapped["User"] = relationship("User")


class AccountBalanceHistory(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "account_balance_history"

    account_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("accounts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    balance_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    closing_balance: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)

    account: Mapped["Account"] = relationship("Account", back_populates="balance_history")
