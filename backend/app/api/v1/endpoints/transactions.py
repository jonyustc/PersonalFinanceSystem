from fastapi import APIRouter, Depends
from typing import Optional
from datetime import date, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.transaction import (
    TransactionCreate,
    TransactionUpdate,
    TransactionResponse,
)
from app.services.transaction import TransactionService

router = APIRouter()


# ================= LIST =================


router = APIRouter()


@router.get("")
async def list_transactions(
    limit: int = 50,
    offset: int = 0,

    search: Optional[str] = None,
    type: Optional[str] = None,
    category_id: Optional[UUID] = None,
    account_id: Optional[UUID] = None,

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
        category_id=category_id,
        account_id=account_id,
        from_date=from_date,
        to_date=to_date,
    )

    return {
        "items": items,
        "total": total,
        "limit": limit,
        "offset": offset,
    }

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
