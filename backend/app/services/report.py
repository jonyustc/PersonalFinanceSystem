from sqlalchemy import select, func, extract
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Transaction


class ReportService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def monthly_expenses(self, user_id, month, year):
        stmt = select(
            func.sum(Transaction.amount)
        ).where(
            Transaction.user_id == user_id,
            Transaction.type == "expense",
            extract("month", Transaction.txn_date) == month,
            extract("year", Transaction.txn_date) == year,
        )

        total = await self.db.scalar(stmt) or 0

        return {
            "month": month,
            "year": year,
            "total": total,
            "categories": [],
        }

    async def category_report(self, user_id):
        stmt = (
            select(
                Transaction.category_id,
                func.sum(Transaction.amount)
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.type == "expense"
            )
            .group_by(Transaction.category_id)
        )

        result = await self.db.execute(stmt)

        return [
            {"label": str(r.category_id), "amount": r[1]}
            for r in result
        ]

    async def income_report(self, user_id, year):
        stmt = (
            select(
                extract("month", Transaction.txn_date),
                func.sum(Transaction.amount)
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.type == "income",
                extract("year", Transaction.txn_date) == year,
            )
            .group_by(extract("month", Transaction.txn_date))
        )

        result = await self.db.execute(stmt)

        return [
            {"label": f"Month {int(r[0])}", "amount": r[1]}
            for r in result
        ]

    async def net_worth_trend(self, user_id):
        return []

    async def portfolio_performance(self, user_id):
        return []
