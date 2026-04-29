from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import Timestamped


class NotificationCreate(BaseModel):
    title: str
    message: str
    scheduled_at: datetime | None = None


class NotificationResponse(Timestamped):
    title: str
    message: str
    scheduled_at: datetime | None
    is_read: bool
