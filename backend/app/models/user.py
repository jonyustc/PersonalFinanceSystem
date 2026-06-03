from sqlalchemy import String, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class User(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "users"

    # ===============================
    # BASIC FIELDS
    # ===============================

    full_name: Mapped[str] = mapped_column(
        String(120),
        nullable=False,
    )

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
    # RELATIONSHIPS
    # ===============================

    accounts: Mapped[list["Account"]] = relationship(
        "Account",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    categories: Mapped[list["Category"]] = relationship(
        "Category",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    transactions: Mapped[list["Transaction"]] = relationship(
        "Transaction",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    budgets: Mapped[list["Budget"]] = relationship(
        "Budget",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    notifications: Mapped[list["Notification"]] = relationship(
        "Notification",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    monthly_incomes: Mapped[list["MonthlyIncome"]] = relationship(
        "MonthlyIncome",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    # ===============================
    # DEBUG
    # ===============================

    def __repr__(self) -> str:
        return f"<User {self.email}>"


# Ensure string-based relationships are registered before SQLAlchemy configures
# mappers in API paths that import User without importing every feature module.
from app.models.account import Account  # noqa: E402,F401
from app.models.budget import Budget  # noqa: E402,F401
from app.models.category import Category  # noqa: E402,F401
from app.models.monthly_income import MonthlyIncome  # noqa: E402,F401
from app.models.notification import Notification  # noqa: E402,F401
from app.models.stock import Dividend, Holding, PortfolioTransaction, Stock  # noqa: E402,F401
from app.models.transaction import Transaction  # noqa: E402,F401
