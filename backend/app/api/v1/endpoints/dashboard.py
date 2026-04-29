from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.dashboard import DashboardResponse
from app.services.dashboard import DashboardService

router = APIRouter()


@router.get("", response_model=DashboardResponse)
async def dashboard(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await DashboardService(db).dashboard(current_user.id)
