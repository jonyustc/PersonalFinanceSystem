from decimal import Decimal
from datetime import date, datetime, time, timedelta

from sqlalchemy import select, func, extract, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.category import Category
from app.models.transaction import Transaction
from app.schemas.account import NetWorthTrendPoint
from app.services.account import AccountService


class ReportService:
    def __init__(self, db: AsyncSession):
        self.db = db

    def _date_range_conditions(self, from_date=None, to_date=None):
        conditions = []
        if from_date:
            start = date.fromisoformat(from_date) if isinstance(from_date, str) else from_date
            if isinstance(start, date) and not isinstance(start, datetime):
                start = datetime.combine(start, time.min)
            conditions.append(Transaction.txn_date >= start)
        if to_date:
            end = date.fromisoformat(to_date) if isinstance(to_date, str) else to_date
            if isinstance(end, date) and not isinstance(end, datetime):
                end = datetime.combine(end + timedelta(days=1), time.min)
                conditions.append(Transaction.txn_date < end)
            else:
                conditions.append(Transaction.txn_date <= end)
        return conditions

    def _report_expense_filter(self):
        return or_(
            Transaction.type == "expense",
            Transaction.transaction_type.in_(["CARD_PAYMENT", "CARD_SPENDING"]),
        )

    async def monthly_expenses(self, user_id, month, year):
        stmt = (
            select(
                Category.id.label("category_id"),
                Category.parent_id.label("parent_id"),
                func.coalesce(Category.name, "Uncategorized").label("label"),
                func.sum(Transaction.amount).label("amount"),
            )
            .outerjoin(Category, Category.id == Transaction.category_id)
            .where(
                Transaction.user_id == user_id,
                self._report_expense_filter(),
                extract("month", Transaction.txn_date) == month,
                extract("year", Transaction.txn_date) == year,
            )
            .group_by(Category.id, Category.parent_id, Category.name)
            .order_by(func.sum(Transaction.amount).desc())
        )

        result = await self.db.execute(stmt)
        categories = [
            {
                "id": str(row.category_id) if row.category_id else None,
                "parent_id": str(row.parent_id) if row.parent_id else None,
                "label": str(row.label),
                "amount": row.amount or Decimal("0"),
            }
            for row in result
        ]
        total = sum((row["amount"] for row in categories), Decimal("0"))

        return {
            "month": month,
            "year": year,
            "total": total,
            "categories": categories,
        }

    async def category_report(self, user_id, from_date=None, to_date=None):
        conditions = [
            Transaction.user_id == user_id,
            self._report_expense_filter(),
        ]
        conditions.extend(self._date_range_conditions(from_date, to_date))

        stmt = (
            select(
                Category.id.label("category_id"),
                Category.parent_id.label("parent_id"),
                func.coalesce(Category.name, "Uncategorized").label("label"),
                func.sum(Transaction.amount).label("amount"),
            )
            .outerjoin(Category, Category.id == Transaction.category_id)
            .where(*conditions)
            .group_by(Category.id, Category.parent_id, Category.name)
            .order_by(func.sum(Transaction.amount).desc())
        )

        result = await self.db.execute(stmt)
        return [
            {
                "id": str(row.category_id) if row.category_id else None,
                "parent_id": str(row.parent_id) if row.parent_id else None,
                "label": str(row.label),
                "amount": row.amount or Decimal("0"),
            }
            for row in result
        ]

    async def income_report(self, user_id, year):
        stmt = (
            select(
                extract("month", Transaction.txn_date).label("month"),
                func.sum(Transaction.amount).label("amount"),
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.type == "income",
                extract("year", Transaction.txn_date) == year,
            )
            .group_by(extract("month", Transaction.txn_date))
            .order_by(extract("month", Transaction.txn_date))
        )

        result = await self.db.execute(stmt)
        return [
            {"label": f"Month {int(row.month)}",
             "amount": row.amount or Decimal("0")}
            for row in result
        ]

    async def net_worth_trend(self, user_id):
        return [
            {"period": point.date, "amount": point.net_worth}
            for point in await AccountService(self.db).net_worth_trend(user_id)
        ]

    async def portfolio_performance(self, user_id):
        summary = await AccountService(self.db).summary(user_id)
        return [
            {"label": "Net worth", "amount": summary.net_worth},
            {"label": "Assets", "amount": summary.total_assets},
            {"label": "Liabilities", "amount": summary.liabilities},
        ]
