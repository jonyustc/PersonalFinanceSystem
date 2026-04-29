from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import extract, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.category import Category
from app.models.stock import Holding, Stock
from app.models.transaction import Transaction, TransactionType
from app.schemas.report import MonthlyExpenseReport, ReportRow, TrendPoint


class ReportService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def monthly_expenses(self, user_id: UUID, month: int, year: int) -> MonthlyExpenseReport:
        rows = await self.db.execute(
            select(Category.name, func.coalesce(func.sum(Transaction.amount), 0))
            .join(Category, Category.id == Transaction.category_id)
            .where(
                Transaction.user_id == user_id,
                Transaction.txn_type == TransactionType.EXPENSE,
                extract("month", Transaction.txn_date) == month,
                extract("year", Transaction.txn_date) == year,
            )
            .group_by(Category.name)
        )
        categories = [ReportRow(label=row[0], amount=row[1]) for row in rows.all()]
        total = sum((row.amount for row in categories), Decimal("0"))
        return MonthlyExpenseReport(month=month, year=year, total=total, categories=categories)

    async def category_report(self, user_id: UUID) -> list[ReportRow]:
        rows = await self.db.execute(
            select(Category.name, func.coalesce(func.sum(Transaction.amount), 0))
            .join(Category, Category.id == Transaction.category_id)
            .where(Transaction.user_id == user_id)
            .group_by(Category.name)
        )
        return [ReportRow(label=row[0], amount=row[1]) for row in rows.all()]

    async def income_report(self, user_id: UUID, year: int) -> list[ReportRow]:
        rows = await self.db.execute(
            select(extract("month", Transaction.txn_date), func.coalesce(func.sum(Transaction.amount), 0))
            .where(Transaction.user_id == user_id, Transaction.txn_type == TransactionType.INCOME, extract("year", Transaction.txn_date) == year)
            .group_by(extract("month", Transaction.txn_date))
            .order_by(extract("month", Transaction.txn_date))
        )
        return [ReportRow(label=str(int(row[0])), amount=row[1]) for row in rows.all()]

    async def net_worth_trend(self, user_id: UUID) -> list[TrendPoint]:
        current = await self.db.execute(
            select(func.coalesce(func.sum(Account.current_balance), 0)).where(Account.user_id == user_id)
        )
        return [TrendPoint(period=datetime.now(UTC).strftime("%Y-%m"), amount=current.scalar_one())]

    async def portfolio_performance(self, user_id: UUID) -> list[ReportRow]:
        rows = await self.db.execute(
            select(Stock.symbol, func.coalesce(func.sum((Stock.last_price - Holding.avg_buy_price) * Holding.quantity), 0))
            .join(Stock, Stock.id == Holding.stock_id)
            .where(Holding.user_id == user_id)
            .group_by(Stock.symbol)
        )
        return [ReportRow(label=row[0], amount=row[1]) for row in rows.all()]
