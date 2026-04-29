from uuid import UUID

from sqlalchemy import select

from app.models.notification import Notification
from app.repositories.base import BaseRepository


class NotificationRepository(BaseRepository[Notification]):
    model = Notification

    async def list_by_user(self, user_id: UUID) -> list[Notification]:
        result = await self.db.execute(
            select(Notification).where(Notification.user_id == user_id).order_by(Notification.created_at.desc())
        )
        return list(result.scalars())
