from calendar import monthrange
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.budget import Budget
from app.models.transaction import Transaction, TransactionType
from app.repositories.budget import BudgetRepository
from app.repositories.category import CategoryRepository
from app.schemas.budget import BudgetComparison, BudgetCreate, BudgetUpdate


class BudgetService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.budgets = BudgetRepository(db)
        self.categories = CategoryRepository(db)

    async def create(self, user_id: UUID, payload: BudgetCreate) -> Budget:
        if not await self.categories.get_user_owned(user_id, payload.category_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")
        budget = await self.budgets.create({"user_id": user_id, **payload.model_dump()})
        await self.db.commit()
        return budget

    async def get(self, user_id: UUID, budget_id: UUID) -> Budget:
        budget = await self.budgets.get_user_owned(user_id, budget_id)
        if not budget:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Budget not found")
        return budget

    async def list(self, user_id: UUID, month: int | None, year: int | None) -> list[BudgetComparison]:
        budgets = await self.budgets.list_by_user(user_id, month, year)
        return [await self.compare_budget(budget) for budget in budgets]

    async def update(self, user_id: UUID, budget_id: UUID, payload: BudgetUpdate) -> Budget:
        budget = await self.get(user_id, budget_id)
        budget.amount = payload.amount
        await self.db.commit()
        await self.db.refresh(budget)
        return budget

    async def delete(self, user_id: UUID, budget_id: UUID) -> None:
        budget = await self.get(user_id, budget_id)
        await self.budgets.delete(budget)
        await self.db.commit()

    async def compare_budget(self, budget: Budget) -> BudgetComparison:
        start = datetime(budget.year, budget.month, 1, tzinfo=UTC)
        end = datetime(budget.year, budget.month, monthrange(budget.year, budget.month)[1], 23, 59, 59, tzinfo=UTC)
        result = await self.db.execute(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == budget.user_id,
                Transaction.category_id == budget.category_id,
                Transaction.txn_type == TransactionType.EXPENSE,
                Transaction.txn_date >= start,
                Transaction.txn_date <= end,
            )
        )
        spent = result.scalar_one()
        remaining = budget.amount - spent
        return BudgetComparison.model_validate(budget).model_copy(
            update={"spent": spent, "remaining": remaining, "overspending": remaining < Decimal("0")}
        )
