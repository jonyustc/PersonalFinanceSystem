from sqlalchemy import String, Numeric, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class Account(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "accounts"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    name: Mapped[str] = mapped_column(String(120), nullable=False)

    type: Mapped[str] = mapped_column(
        String,
        nullable=False,
    )  # cash / bank / card

    balance: Mapped[float] = mapped_column(
        Numeric(14, 2),
        default=0,
    )

    currency: Mapped[str] = mapped_column(String(3), default="USD")
    notes: Mapped[str | None] = mapped_column(String, nullable=True)
    is_active: Mapped[bool] = mapped_column(default=True)

    user = relationship("User", back_populates="accounts")
