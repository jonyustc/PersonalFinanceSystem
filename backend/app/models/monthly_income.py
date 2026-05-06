from decimal import Decimal
from uuid import UUID

from sqlalchemy import ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class MonthlyIncome(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "monthly_income"

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "month",
            name="uq_income_user_month",
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    month: Mapped[str] = mapped_column(
        String(7),
        nullable=False,
    )

    amount: Mapped[Decimal] = mapped_column(
        Numeric(14, 2),
        nullable=False,
    )

    user: Mapped["User"] = relationship(
        "User",
        back_populates="monthly_incomes",
    )
