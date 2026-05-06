from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.monthly_income import MonthlyIncome
from app.schemas.monthly_income import MonthlyIncomeCreate


class MonthlyIncomeService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ================= GET =================

    async def get_by_month(self, user_id: UUID, month: str) -> MonthlyIncome | None:
        stmt = select(MonthlyIncome).where(
            MonthlyIncome.user_id == user_id,
            MonthlyIncome.month == month,
        )

        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    # ================= UPSERT =================

    async def upsert(self, user_id: UUID, payload: MonthlyIncomeCreate):
        existing = await self.get_by_month(user_id, payload.month)

        if existing:
            existing.amount = payload.amount
        else:
            existing = MonthlyIncome(
                user_id=user_id,
                month=payload.month,
                amount=payload.amount,
            )
            self.db.add(existing)

        await self.db.commit()
        await self.db.refresh(existing)

        return existing
