from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.stock import (
    DseDividendEstimateResponse,
    DseStockSearchResponse,
    DividendCreate,
    DividendResponse,
    PortfolioSummaryResponse,
    PortfolioTransactionCreate,
    PortfolioTransactionResponse,
    StockCreate,
    StockPriceRefreshResponse,
    StockResponse,
    StockUpdate,
)
from app.services.market_price import MarketPriceService
from app.services.portfolio import PortfolioService


router = APIRouter()


@router.get("/stocks", response_model=list[StockResponse])
async def list_stocks(db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).stocks()


@router.get("/stocks/dse/search", response_model=list[DseStockSearchResponse])
async def search_dse_stocks(
    query: str = Query(default="", max_length=40),
    limit: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
):
    quotes = await MarketPriceService().search_dse_stocks(query=query, limit=limit)
    return [
        {
            "symbol": quote.symbol,
            "name": quote.name,
            "last_price": quote.last_price,
            "source": quote.source,
            "fetched_at": quote.fetched_at.isoformat(),
        }
        for quote in quotes
    ]


@router.get("/stocks/dse/dividend-estimate", response_model=DseDividendEstimateResponse)
async def dse_dividend_estimate(
    symbol: str = Query(min_length=1, max_length=20),
    stock_id: UUID | None = None,
    tax_rate_percent: Decimal = Query(default=Decimal("10"), ge=0, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await PortfolioService(db).dse_dividend_estimate(
        current_user.id,
        symbol=symbol,
        stock_id=stock_id,
        tax_rate_percent=tax_rate_percent,
    )


@router.post("/stocks/refresh-prices", response_model=StockPriceRefreshResponse)
async def refresh_stock_prices(db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).refresh_stock_prices()


@router.post("/stocks", response_model=StockResponse, status_code=status.HTTP_201_CREATED)
async def create_stock(payload: StockCreate, db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).create_stock(payload)


@router.post("/stocks/{stock_id}/refresh-price", response_model=StockPriceRefreshResponse)
async def refresh_stock_price(stock_id: UUID, db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).refresh_stock_price(stock_id)


@router.patch("/stocks/{stock_id}", response_model=StockResponse)
async def update_stock(stock_id: UUID, payload: StockUpdate, db: AsyncSession = Depends(get_db), current_user: User = Depends(get_current_user)):
    return await PortfolioService(db).update_stock(stock_id, payload)


@router.get("/summary", response_model=PortfolioSummaryResponse)
async def summary(
    include_auto_dividends: bool = Query(default=False),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await PortfolioService(db).summary(
        current_user.id,
        include_auto_dividends=include_auto_dividends,
    )


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
