"""Records deletions so offline clients can replay them on the next sync.

Every hard delete in the app should call :func:`record_tombstone` inside the
same transaction, just before commit. The row is upserted (idempotent under
retries) with a fresh ``deleted_at`` so a re-deletion still advances the feed.
"""
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sync import SyncTombstone

# Logical resource names shared with GET /sync/changes and the mobile mirror.
RESOURCE_TRANSACTIONS = "transactions"
RESOURCE_CATEGORIES = "categories"
RESOURCE_BUDGETS = "budgets"
RESOURCE_PORTFOLIO_TRANSACTIONS = "portfolio_transactions"
RESOURCE_PORTFOLIOS = "portfolios"


async def record_tombstone(
    db: AsyncSession,
    user_id: UUID,
    resource: str,
    entity_id: UUID,
) -> None:
    """Upsert a tombstone for (user, resource, entity), flushed not committed.

    The caller owns the transaction boundary; this only flushes so the delete
    and its tombstone commit together.
    """
    stmt = (
        pg_insert(SyncTombstone)
        .values(
            user_id=user_id,
            resource=resource,
            entity_id=entity_id,
            deleted_at=datetime.now(UTC),
        )
        .on_conflict_do_update(
            index_elements=["user_id", "resource", "entity_id"],
            set_={"deleted_at": datetime.now(UTC)},
        )
    )
    await db.execute(stmt)
