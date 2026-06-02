# app/api/v1/endpoints/funds.py

from uuid import UUID
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.services.funds import FundService

router = APIRouter(tags=["Funds"])


@router.get("/{account_id}/summary")
async def fund_summary(
    account_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns fund breakdown:
    - Total fund balance
    - My spending vs friend's spending
    - Transaction list tagged by member
    """
    return await FundService(db).get_summary(current_user.id, account_id)


@router.get("/{account_id}/transactions")
async def fund_transactions(
    account_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """All transactions for this fund, grouped by member tag."""
    return await FundService(db).get_transactions(current_user.id, account_id)
