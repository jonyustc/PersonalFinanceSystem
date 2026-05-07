from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.account import CardSummaryResponse
from app.services.account import AccountService


router = APIRouter(tags=["Cards"])


@router.get("/{account_id}/summary", response_model=CardSummaryResponse)
async def card_summary(
    account_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).card_summary(current_user.id, account_id)
