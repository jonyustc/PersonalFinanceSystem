from sqlalchemy import String, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class Category(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "categories"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    name: Mapped[str] = mapped_column(String(120), nullable=False)

    type: Mapped[str] = mapped_column(String(20), nullable=False)

    parent_id: Mapped[UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("categories.id"),
        nullable=True,
    )

    color: Mapped[str | None] = mapped_column(String(20), nullable=True)
    icon: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # ===============================
    # RELATIONSHIPS
    # ===============================
    user = relationship("User", back_populates="categories")

    parent = relationship(
        "Category",
        remote_side="Category.id",
        back_populates="children",
    )

    children = relationship(
        "Category",
        back_populates="parent",
        cascade="all, delete",
    )

    transactions = relationship("Transaction", back_populates="category")

    # 🔥 FIX (THIS WAS MISSING)
    budgets = relationship("Budget", back_populates="category")
