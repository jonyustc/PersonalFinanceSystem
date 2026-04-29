from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.budget import BudgetComparison, BudgetCreate, BudgetResponse, BudgetUpdate
from app.services.budget import BudgetService

router = APIRouter()


@router.post("", response_model=BudgetResponse, status_code=status.HTTP_201_CREATED)
async def create_budget(payload: BudgetCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await BudgetService(db).create(current_user.id, payload)


@router.get("", response_model=list[BudgetComparison])
async def list_budgets(
    month: int | None = Query(default=None, ge=1, le=12),
    year: int | None = Query(default=None, ge=2000, le=2100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await BudgetService(db).list(current_user.id, month, year)


@router.patch("/{budget_id}", response_model=BudgetResponse)
async def update_budget(budget_id: UUID, payload: BudgetUpdate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await BudgetService(db).update(current_user.id, budget_id, payload)


@router.delete("/{budget_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_budget(budget_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await BudgetService(db).delete(current_user.id, budget_id)
