from decimal import Decimal
from sqlalchemy import ForeignKey, Numeric, String, UniqueConstraint
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

    # ================= RELATION =================

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    # ================= DATA =================

    month: Mapped[str] = mapped_column(
        String(7),  # format: YYYY-MM
        nullable=False,
    )

    amount: Mapped[Decimal] = mapped_column(
        Numeric(14, 2),
        nullable=False,
    )

    # ================= RELATIONSHIP =================

    user = relationship("User", back_populates="monthly_incomes")
