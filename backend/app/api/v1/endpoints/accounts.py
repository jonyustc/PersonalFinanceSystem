from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.account import (
    AccountAnalyticsResponse,
    AccountCreate,
    AccountResponse,
    AccountSummaryResponse,
    AccountUpdate,
    BalanceAdjustmentCreate,
    NetWorthTrendPoint,
)
from app.services.account import AccountService


router = APIRouter(tags=["Accounts"])


@router.post("", response_model=AccountResponse, status_code=status.HTTP_201_CREATED)
async def create_account(
    payload: AccountCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).create(current_user.id, payload)


@router.get("", response_model=list[AccountResponse])
async def list_accounts(
    active_only: bool = Query(default=True),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).list(current_user.id, active_only=active_only)


@router.get("/summary", response_model=AccountSummaryResponse)
async def account_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).summary(current_user.id)


@router.get("/analytics", response_model=AccountAnalyticsResponse)
async def account_analytics(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).analytics(current_user.id)


@router.get("/net-worth-trend", response_model=list[NetWorthTrendPoint])
async def account_net_worth_trend(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).net_worth_trend(current_user.id)


@router.get("/{account_id}", response_model=AccountResponse)
async def get_account(
    account_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).get(current_user.id, account_id)


@router.patch("/{account_id}", response_model=AccountResponse)
async def update_account(
    account_id: UUID,
    payload: AccountUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).update(current_user.id, account_id, payload)


@router.post("/{account_id}/adjust-balance", response_model=AccountResponse)
async def adjust_account_balance(
    account_id: UUID,
    payload: BalanceAdjustmentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await AccountService(db).adjust_balance(current_user.id, account_id, payload)


@router.delete("/{account_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    account_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await AccountService(db).delete(current_user.id, account_id)
