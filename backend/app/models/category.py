import enum

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import TimestampMixin, UUIDMixin


class CategoryType(str, enum.Enum):
    EXPENSE = "expense"
    INCOME = "income"


class Category(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "categories"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    type: Mapped[CategoryType] = mapped_column(String(20), nullable=False)
    color: Mapped[str] = mapped_column(String(20), nullable=True)
    icon: Mapped[str] = mapped_column(String(80), nullable=True)

    user = relationship("User", back_populates="categories")
    transactions = relationship("Transaction", back_populates="category")
    budgets = relationship("Budget", back_populates="category")
