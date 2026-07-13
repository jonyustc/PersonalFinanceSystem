from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.base import UUIDMixin


class SyncTombstone(UUIDMixin, Base):
    """Records a hard-deleted row so offline clients can replay the deletion.

    Deletes across the app stay hard deletes (the web app and every existing
    query are untouched); the delete path just drops one tombstone here. A
    client pulling ``/sync/changes?since=<ts>`` reads rows with
    ``deleted_at > since`` and removes the matching local mirror rows.
    """

    __tablename__ = "sync_tombstones"

    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Logical resource name the client mirrors, e.g. "transactions",
    # "categories", "budgets", "portfolio_transactions", "portfolios".
    resource: Mapped[str] = mapped_column(String(40), nullable=False)
    entity_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), nullable=False)
    deleted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
        index=True,
    )
