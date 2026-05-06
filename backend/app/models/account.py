from decimal import Decimal
from uuid import UUID

from sqlalchemy import String, Numeric, ForeignKey, Boolean
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

    user: Mapped["User"] = relationship(
        "User",
        back_populates="accounts",
    )
