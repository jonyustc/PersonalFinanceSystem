from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.transaction import MonthlySummary, TransactionCreate, TransactionListResponse, TransactionResponse, TransactionUpdate
from app.services.transaction import TransactionService

router = APIRouter()


@router.post("", response_model=TransactionResponse, status_code=status.HTTP_201_CREATED)
async def create_transaction(payload: TransactionCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await TransactionService(db).create(current_user.id, payload)


@router.get("", response_model=TransactionListResponse)
async def list_transactions(
    start_date: datetime | None = None,
    end_date: datetime | None = None,
    account_id: UUID | None = None,
    category_id: UUID | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await TransactionService(db).list(current_user.id, start_date, end_date, account_id, category_id, limit, offset)


@router.get("/monthly-summary", response_model=MonthlySummary)
async def monthly_summary(month: int = Query(ge=1, le=12), year: int = Query(ge=2000, le=2100), current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await TransactionService(db).monthly_summary(current_user.id, month, year)


@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(transaction_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await TransactionService(db).get(current_user.id, transaction_id)


@router.patch("/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(transaction_id: UUID, payload: TransactionUpdate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await TransactionService(db).update(current_user.id, transaction_id, payload)


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(transaction_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await TransactionService(db).delete(current_user.id, transaction_id)
