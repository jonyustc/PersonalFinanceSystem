from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.services.sync import SyncService

router = APIRouter()


@router.get("/changes")
async def sync_changes(
    since: Optional[datetime] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delta feed for offline clients.

    Pass `since` = the `server_time` from the previous response to get only
    what changed. Omit it on the first sync to pull everything. The response is
    `{server_time, changes: {<resource>: [...]}, tombstones: [...]}`.
    """
    return await SyncService(db).changes(current_user.id, since)
