from sqlalchemy import String, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class User(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "users"

    # ===============================
    # 🔹 BASIC FIELDS
    # ===============================
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)

    email: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        index=True,
        nullable=False,
    )

    hashed_password: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    currency: Mapped[str] = mapped_column(
        String(10),
        default="USD",
        nullable=False,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )

    # ===============================
    # 🔹 RELATIONSHIPS
    # ===============================
    accounts = relationship(
        "Account",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    categories = relationship(
        "Category",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    transactions = relationship(
        "Transaction",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    budgets = relationship(
        "Budget",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    notifications = relationship(
        "Notification",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    monthly_incomes = relationship(
        "MonthlyIncome",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    # ===============================
    # 🔹 DEBUG
    # ===============================
    def __repr__(self):
        return f"<User {self.email}>"
