from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification
from app.repositories.notification import NotificationRepository
from app.schemas.notification import NotificationCreate


class NotificationService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.notifications = NotificationRepository(db)

    async def create(self, user_id: UUID, payload: NotificationCreate) -> Notification:
        notification = await self.notifications.create({"user_id": user_id, **payload.model_dump()})
        await self.db.commit()
        return notification

    async def list(self, user_id: UUID) -> list[Notification]:
        return await self.notifications.list_by_user(user_id)
