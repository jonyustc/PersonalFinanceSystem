from typing import Optional
from decimal import Decimal
from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.transaction import (
    BulkTransactionDelete,
    BulkTransactionUpdate,
    SplitTransactionCreate,
    TransactionAnalyticsResponse,
    TransactionCreate,
    TransactionListResponse,
    TransactionResponse,
    TransactionUpdate,
)
from app.services.transaction import TransactionService

router = APIRouter()


@router.get("", response_model=TransactionListResponse)
async def list_transactions(
    limit: int = 50,
    offset: int = 0,

    search: Optional[str] = None,
    type: Optional[str] = None,
    account_source: Optional[str] = None,
    category_id: Optional[UUID] = None,
    account_id: Optional[UUID] = None,
    merchant: Optional[str] = None,
    counterparty: Optional[str] = None,
    tags: Optional[str] = None,
    recurring_only: bool = False,
    transfer_only: bool = False,
    active_accounts_only: bool = False,
    min_amount: Optional[Decimal] = None,
    max_amount: Optional[Decimal] = None,

    # ✅ FIXED
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,

    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = TransactionService(db)

    items, total = await service.list(
        user_id=current_user.id,
        limit=limit,
        offset=offset,
        search=search,
        type=type,
        account_source=account_source,
        category_id=category_id,
        account_id=account_id,
        from_date=from_date,
        to_date=to_date,
        merchant=merchant,
        counterparty=counterparty,
        tags=[tag.strip() for tag in tags.split(",") if tag.strip()] if tags else None,
        recurring_only=recurring_only,
        transfer_only=transfer_only,
        active_accounts_only=active_accounts_only,
        min_amount=min_amount,
        max_amount=max_amount,
    )

    return {
        "items": items,
        "total": total,
        "limit": limit,
        "offset": offset,
        "next_offset": offset + limit if offset + limit < total else None,
    }


@router.get("/analytics", response_model=TransactionAnalyticsResponse)
async def transaction_analytics(
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await TransactionService(db).analytics(current_user.id, from_date, to_date)


@router.get("/monthly-summary", response_model=TransactionAnalyticsResponse)
async def monthly_summary(
    month: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    start = date.fromisoformat(f"{month}-01")
    end = (start.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
    return await TransactionService(db).analytics(current_user.id, start, end)


@router.get("/cashflow", response_model=TransactionAnalyticsResponse)
async def cashflow(
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await TransactionService(db).analytics(current_user.id, from_date, to_date)


@router.post("/bulk-update")
async def bulk_update_transactions(
    payload: BulkTransactionUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return {"updated": await TransactionService(db).bulk_update(current_user.id, payload)}


@router.post("/bulk-delete")
async def bulk_delete_transactions(
    payload: BulkTransactionDelete,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return {"deleted": await TransactionService(db).bulk_delete(current_user.id, payload.ids)}


@router.post("/split")
async def split_transaction(
    payload: SplitTransactionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await TransactionService(db).split(current_user.id, payload)

# ================= CREATE =================


@router.post("", response_model=TransactionResponse)
async def create_transaction(
    payload: TransactionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = TransactionService(db)
    return await service.create(current_user.id, payload)


# ================= UPDATE =================

@router.patch("/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(
    transaction_id: UUID,
    payload: TransactionUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = TransactionService(db)

    transaction = await service.update(
        user_id=current_user.id,
        transaction_id=transaction_id,
        payload=payload,
    )

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found",
        )

    return transaction


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(
    transaction_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not await TransactionService(db).delete(current_user.id, transaction_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")
