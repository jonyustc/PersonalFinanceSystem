from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.report import CardReport, MonthlyExpenseReport, ReportRow, TrendPoint
from app.services.report import ReportService

router = APIRouter()


@router.get("/monthly-expenses", response_model=MonthlyExpenseReport)
async def monthly_expenses(month: int = Query(ge=1, le=12), year: int = Query(ge=2000, le=2100), current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await ReportService(db).monthly_expenses(current_user.id, month, year)


@router.get("/categories", response_model=list[ReportRow])
async def category_report(
    from_date: str | None = Query(None),
    to_date: str | None = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ReportService(db).category_report(current_user.id, from_date, to_date)


@router.get("/income", response_model=list[ReportRow])
async def income_report(year: int = Query(ge=2000, le=2100), current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await ReportService(db).income_report(current_user.id, year)


@router.get("/net-worth-trend", response_model=list[TrendPoint])
async def net_worth_trend(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await ReportService(db).net_worth_trend(current_user.id)


@router.get("/portfolio-performance", response_model=list[ReportRow])
async def portfolio_performance(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await ReportService(db).portfolio_performance(current_user.id)


@router.get("/cards", response_model=CardReport)
async def card_report(
    from_date: str | None = Query(None),
    to_date: str | None = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ReportService(db).card_report(current_user.id, from_date, to_date)
