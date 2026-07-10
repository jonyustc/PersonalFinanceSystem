from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.debts import DebtSummaryResponse
from app.services.debts import DebtsService

router = APIRouter()


@router.get("/summary", response_model=DebtSummaryResponse)
async def debt_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await DebtsService(db).summary(current_user.id)
