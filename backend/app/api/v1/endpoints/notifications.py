from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.notification import NotificationCreate, NotificationResponse
from app.services.notification import NotificationService

router = APIRouter()


@router.post("", response_model=NotificationResponse, status_code=status.HTTP_201_CREATED)
async def create_notification(payload: NotificationCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await NotificationService(db).create(current_user.id, payload)


@router.get("", response_model=list[NotificationResponse])
async def list_notifications(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await NotificationService(db).list(current_user.id)
