from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import UUID

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.stock import (
    DividendCreate,
    DividendResponse,
    PortfolioSummaryResponse,
    PortfolioTransactionCreate,
    PortfolioTransactionResponse,
    StockCreate,
    StockResponse,
    StockUpdate,
)
from app.services.portfolio import PortfolioService


router = APIRouter()


@router.get("/stocks", response_model=list[StockResponse])
async def list_stocks(db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).stocks()


@router.post("/stocks", response_model=StockResponse, status_code=status.HTTP_201_CREATED)
async def create_stock(payload: StockCreate, db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).create_stock(payload)


@router.patch("/stocks/{stock_id}", response_model=StockResponse)
async def update_stock(stock_id: UUID, payload: StockUpdate, db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).update_stock(stock_id, payload)


@router.get("/summary", response_model=PortfolioSummaryResponse)
async def summary(db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).summary(current_user.id)


@router.get("/transactions", response_model=list[PortfolioTransactionResponse])
async def transactions(
    limit: int = Query(default=100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await PortfolioService(db).list_transactions(current_user.id, limit)


@router.post("/transactions", response_model=PortfolioTransactionResponse, status_code=status.HTTP_201_CREATED)
async def create_transaction(
    payload: PortfolioTransactionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await PortfolioService(db).create_transaction(current_user.id, payload)


@router.patch("/transactions/{transaction_id}", response_model=PortfolioTransactionResponse)
async def update_transaction(
    transaction_id: UUID,
    payload: PortfolioTransactionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await PortfolioService(db).update_transaction(current_user.id, transaction_id, payload)


@router.delete("/transactions/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(
    transaction_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await PortfolioService(db).delete_transaction(current_user.id, transaction_id)


@router.get("/dividends", response_model=list[DividendResponse])
async def dividends(db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).dividends(current_user.id)


@router.post("/dividends", response_model=DividendResponse, status_code=status.HTTP_201_CREATED)
async def create_dividend(payload: DividendCreate, db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).create_dividend(current_user.id, payload)
