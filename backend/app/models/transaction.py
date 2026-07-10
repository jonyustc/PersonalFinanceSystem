from decimal import Decimal
from datetime import datetime, UTC

from sqlalchemy import String, ForeignKey, Numeric, DateTime, Boolean, CheckConstraint, true
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class Transaction(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "transactions"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    account_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("accounts.id"),
        index=True,
        nullable=False,
    )

    transfer_account_id: Mapped[UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("accounts.id"),
        nullable=True,
    )

    category_id: Mapped[UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("categories.id"),
        nullable=True,
    )

    type: Mapped[str] = mapped_column(
        String(20), nullable=False)  # expense/income/transfer

    payment_method: Mapped[str | None] = mapped_column(
        String(20),
        nullable=True,
    )

    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)

    txn_date: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    transaction_date: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    is_emergency: Mapped[bool] = mapped_column(Boolean, default=False)

    include_in_totals: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default=true(), nullable=False)

    description: Mapped[str | None] = mapped_column(String, nullable=True)
    merchant_name: Mapped[str | None] = mapped_column(String(160), nullable=True)
    counterparty_name: Mapped[str | None] = mapped_column(String(120), index=True, nullable=True)
    debt_type: Mapped[str | None] = mapped_column(String(20), nullable=True)  # lent/borrowed/repaid_by_them/repaid_to_them
    transaction_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    transfer_id: Mapped[UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    tags: Mapped[list[str]] = mapped_column(ARRAY(String), default=list, nullable=False)
    location: Mapped[str | None] = mapped_column(String(160), nullable=True)
    attachment_url: Mapped[str | None] = mapped_column(String, nullable=True)
    recurring_rule: Mapped[str | None] = mapped_column(String(20), nullable=True)
    parent_transaction_id: Mapped[UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("transactions.id", ondelete="SET NULL"),
        nullable=True,
    )
    is_split: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_recurring: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    transaction_status: Mapped[str] = mapped_column(String(20), default="posted", nullable=False)
    reference_number: Mapped[str | None] = mapped_column(String(80), nullable=True)

    # relations
    account = relationship("Account", foreign_keys=[account_id])
    transfer_account = relationship(
        "Account", foreign_keys=[transfer_account_id])
    category = relationship("Category")
    user = relationship("User")
    parent_transaction = relationship("Transaction", remote_side="Transaction.id")

    __table_args__ = (
        CheckConstraint("type IN ('expense','income','transfer')"),
    )
