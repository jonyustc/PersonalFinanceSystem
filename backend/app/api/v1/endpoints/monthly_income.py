from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.monthly_income import MonthlyIncomeCreate, MonthlyIncomeResponse
from app.services.monthly_income import MonthlyIncomeService

router = APIRouter()


@router.get("/income", response_model=MonthlyIncomeResponse)
async def get_income(
    month: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    service = MonthlyIncomeService(db)
    income = await service.get_by_month(user.id, month)

    if not income:
        return {
            "id": None,
            "month": month,
            "amount": 0,
            "opening_balance": 0,
        }

    return income


@router.post("/income", response_model=MonthlyIncomeResponse)
async def save_income(
    payload: MonthlyIncomeCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    service = MonthlyIncomeService(db)
    return await service.upsert(user.id, payload)
