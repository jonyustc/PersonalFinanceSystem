from uuid import UUID

from sqlalchemy import select

from app.models.budget import Budget
from app.repositories.base import BaseRepository


class BudgetRepository(BaseRepository[Budget]):
    model = Budget

    async def list_by_user(self, user_id: UUID, month: int | None = None, year: int | None = None) -> list[Budget]:
        stmt = select(Budget).where(Budget.user_id == user_id)
        if month:
            stmt = stmt.where(Budget.month == month)
        if year:
            stmt = stmt.where(Budget.year == year)
        result = await self.db.execute(stmt.order_by(Budget.year.desc(), Budget.month.desc()))
        return list(result.scalars())

    async def get_user_owned(self, user_id: UUID, budget_id: UUID) -> Budget | None:
        result = await self.db.execute(select(Budget).where(Budget.id == budget_id, Budget.user_id == user_id))
        return result.scalar_one_or_none()
