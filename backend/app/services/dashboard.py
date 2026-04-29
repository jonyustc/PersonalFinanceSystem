from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import extract, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account, AccountType
from app.models.category import Category
from app.models.stock import Holding, Stock
from app.models.transaction import Transaction, TransactionType
from app.schemas.dashboard import ChartPoint, DashboardResponse


class DashboardService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def dashboard(self, user_id: UUID) -> DashboardResponse:
        now = datetime.now(UTC)
        balances = await self.db.execute(
            select(Account.type, func.coalesce(func.sum(Account.current_balance), 0))
            .where(Account.user_id == user_id, Account.is_active.is_(True))
            .group_by(Account.type)
        )
        balance_map = {row[0]: row[1] for row in balances.all()}
        total_cash = balance_map.get(AccountType.CASH, Decimal("0"))
        total_bank = balance_map.get(AccountType.BANK, Decimal("0")) + balance_map.get(AccountType.MOBILE_BANKING, Decimal("0"))

        totals = await self.db.execute(
            select(Transaction.txn_type, func.coalesce(func.sum(Transaction.amount), 0))
            .where(
                Transaction.user_id == user_id,
                extract("month", Transaction.txn_date) == now.month,
                extract("year", Transaction.txn_date) == now.year,
            )
            .group_by(Transaction.txn_type)
        )
        total_map = {row[0]: row[1] for row in totals.all()}
        income = total_map.get(TransactionType.INCOME, Decimal("0"))
        expense = total_map.get(TransactionType.EXPENSE, Decimal("0"))

        investments = await self.db.execute(
            select(func.coalesce(func.sum(Holding.quantity * Stock.last_price), 0))
            .join(Stock, Stock.id == Holding.stock_id)
            .where(Holding.user_id == user_id)
        )
        investment_value = investments.scalar_one()

        recent = await self.db.execute(
            select(Transaction).where(Transaction.user_id == user_id).order_by(Transaction.txn_date.desc()).limit(10)
        )
        category_rows = await self.db.execute(
            select(Category.name, func.coalesce(func.sum(Transaction.amount), 0))
            .join(Category, Category.id == Transaction.category_id)
            .where(Transaction.user_id == user_id, Transaction.txn_type == TransactionType.EXPENSE)
            .group_by(Category.name)
            .order_by(func.sum(Transaction.amount).desc())
        )
        monthly_rows = await self.db.execute(
            select(Transaction.txn_type, func.coalesce(func.sum(Transaction.amount), 0))
            .where(Transaction.user_id == user_id)
            .group_by(Transaction.txn_type)
        )
        cashflow = [ChartPoint(label=row[0], value=row[1]) for row in monthly_rows.all()]
        account_total = sum(balance_map.values(), Decimal("0"))
        return DashboardResponse(
            total_cash=total_cash,
            total_bank_balance=total_bank,
            total_expense_this_month=expense,
            total_income_this_month=income,
            savings=income - expense,
            net_worth=account_total + investment_value,
            investment_value=investment_value,
            recent_transactions=list(recent.scalars()),
            expense_by_category=[ChartPoint(label=row[0], value=row[1]) for row in category_rows.all()],
            monthly_cashflow=cashflow,
        )
