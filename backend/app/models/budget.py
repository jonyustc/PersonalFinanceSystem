# app/models/budget.py

from decimal import Decimal
from sqlalchemy import ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class Budget(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "budgets"

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "category_id",
            "month",
            name="uq_budget_user_category_month",
        ),
    )

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    category_id: Mapped[str] = mapped_column(
        ForeignKey("categories.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    # ✅ NEW: actual month (IMPORTANT FIX)
    month: Mapped[str] = mapped_column(
        String(7),  # "2026-05"
        index=True,
        nullable=False,
    )

    amount: Mapped[Decimal] = mapped_column(
        Numeric(14, 2),
        nullable=False,
    )

    user = relationship("User", back_populates="budgets")
    category = relationship("Category", back_populates="budgets")
