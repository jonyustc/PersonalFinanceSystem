from decimal import Decimal
from datetime import datetime, UTC

from sqlalchemy import String, ForeignKey, Numeric, DateTime, Boolean, CheckConstraint
from sqlalchemy.dialects.postgresql import UUID
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

    is_emergency: Mapped[bool] = mapped_column(Boolean, default=False)

    description: Mapped[str | None] = mapped_column(String, nullable=True)

    # relations
    account = relationship("Account", foreign_keys=[account_id])
    transfer_account = relationship(
        "Account", foreign_keys=[transfer_account_id])
    category = relationship("Category")
    user = relationship("User")

    __table_args__ = (
        CheckConstraint("type IN ('expense','income','transfer')"),
    )
