from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import UUIDMixin, TimestampMixin


class Notification(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "notifications"

    # ===============================
    # 🔹 FIELDS
    # ===============================
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    title: Mapped[str] = mapped_column(String(160), nullable=False)

    message: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    scheduled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    is_read: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )

    # ===============================
    # 🔹 RELATIONSHIP
    # ===============================
    user = relationship(
        "User",
        back_populates="notifications",
    )
