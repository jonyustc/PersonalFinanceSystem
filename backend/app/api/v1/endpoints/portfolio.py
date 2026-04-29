from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.stock import DividendCreate, DividendResponse, PortfolioSummary, PortfolioTransactionCreate, PortfolioTransactionResponse
from app.services.portfolio import PortfolioService

router = APIRouter()


@router.post("/transactions", response_model=PortfolioTransactionResponse, status_code=status.HTTP_201_CREATED)
async def create_trade(payload: PortfolioTransactionCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await PortfolioService(db).trade(current_user.id, payload)


@router.get("/summary", response_model=PortfolioSummary)
async def portfolio_summary(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await PortfolioService(db).summary(current_user.id)


@router.post("/dividends", response_model=DividendResponse, status_code=status.HTTP_201_CREATED)
async def add_dividend(payload: DividendCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await PortfolioService(db).add_dividend(current_user.id, payload)


@router.get("/dividends", response_model=list[DividendResponse])
async def list_dividends(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await PortfolioService(db).list_dividends(current_user.id)
