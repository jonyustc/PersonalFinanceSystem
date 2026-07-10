from decimal import Decimal

from sqlalchemy import select, func, and_, case, cast, Date
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime
from uuid import UUID

from app.services.budget import BudgetService
from app.repositories.dashboard import DashboardRepository
from app.models.account import Account
from app.models.transaction import Transaction
from app.models.category import Category


ZERO = Decimal("0")


class DashboardService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.budget_service = BudgetService(db)
        self.dashboard_repo = DashboardRepository(db)

    # =========================
    # UTIL: MONTH RANGE
    # =========================
    def _get_month_range(self, month: str):
        start_date = datetime.strptime(month + "-01", "%Y-%m-%d")

        if start_date.month == 12:
            end_date = datetime(start_date.year + 1, 1, 1)
        else:
            end_date = datetime(start_date.year, start_date.month + 1, 1)

        return start_date, end_date

    # =========================
    # MAIN DASHBOARD
    # =========================
    async def get_full_summary(self, user_id: str, month: str):
        start_date, end_date = self._get_month_range(month)

        dashboard_data = await self._get_dashboard_data(
            user_id, start_date, end_date
        )

        budget_summary = await self.budget_service.get_budget_summary(
            user_id, month
        )

        return {
            **dashboard_data,
            "budget_summary": budget_summary,
        }

    async def get_simple_dashboard(self, user_id: UUID, month: str):
        start_date, end_date = self._get_month_range(month)

        active_accounts = await self.dashboard_repo.active_balance_accounts(user_id)
        credit_cards = await self.dashboard_repo.credit_cards(user_id)
        monthly_spending = await self.dashboard_repo.monthly_card_spending(user_id, start_date, end_date)
        monthly_payments = await self.dashboard_repo.monthly_credit_card_payments(user_id, start_date, end_date)

        total_balance = sum((account.balance for account in active_accounts), ZERO)
        total_card_spending = sum(monthly_spending.values(), ZERO)
        total_card_payment = sum(monthly_payments.values(), ZERO)
        total_card_outstanding = sum((card.current_outstanding for card in credit_cards), ZERO)

        return {
            "month": month,
            "active_accounts_balance": {
                "total_balance": total_balance,
                "accounts": [
                    {
                        "id": str(account.id),
                        "name": account.name,
                        "type": account.type.upper(),
                        "balance": account.balance,
                        "currency": account.currency,
                    }
                    for account in active_accounts
                ],
            },
            "card_summary": {
                "total_card_spending": total_card_spending,
                "total_card_payment": total_card_payment,
                "total_card_outstanding": total_card_outstanding,
                "cards": [self._simple_card(card, monthly_spending, monthly_payments) for card in credit_cards],
            },
        }

    def _simple_card(self, card: Account, monthly_spending: dict, monthly_payments: dict) -> dict:
        credit_limit = card.credit_limit or ZERO
        outstanding = card.current_outstanding or ZERO
        available_limit = max(credit_limit - outstanding, ZERO)
        used_percentage = (outstanding / credit_limit * Decimal("100")) if credit_limit > ZERO else ZERO
        return {
            "id": str(card.id),
            "name": card.name,
            "credit_limit": credit_limit,
            "current_outstanding": outstanding,
            "available_limit": available_limit,
            "used_percentage": used_percentage.quantize(Decimal("0.01")),
            "monthly_spending": monthly_spending.get(card.id, ZERO),
            "monthly_payment": monthly_payments.get(card.id, ZERO),
            "billing_cycle_day": card.billing_cycle_day,
            "payment_due_day": card.payment_due_day,
        }

    # =========================
    # CORE DASHBOARD
    # =========================
    async def _get_dashboard_data(self, user_id, start_date, end_date):
        base_filter = and_(
            Transaction.user_id == user_id,
            Transaction.txn_date >= start_date,
            Transaction.txn_date < end_date,
        )

        # TOTAL BALANCE
        total_balance = await self.db.scalar(
            select(func.coalesce(func.sum(Account.balance), 0)).where(
                Account.user_id == user_id
            )
        )

        # INCOME / EXPENSE
        total_income = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                base_filter, Transaction.type == "income"
            )
        )

        total_expense = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                base_filter, Transaction.type == "expense"
            )
        )

        # RECENT
        recent_res = await self.db.execute(
            select(Transaction)
            .where(Transaction.user_id == user_id)
            .order_by(Transaction.txn_date.desc())
            .limit(5)
        )

        # CATEGORY (WITH NAME)
        cat_res = await self.db.execute(
            select(
                Category.name,
                func.sum(Transaction.amount).label("total"),
            )
            .join(Category, Category.id == Transaction.category_id)
            .where(base_filter, Transaction.type == "expense")
            .group_by(Category.name)
        )

        # MONTHLY CASHFLOW
        month_expr = func.to_char(Transaction.txn_date, "YYYY-MM")

        cashflow_res = await self.db.execute(
            select(
                month_expr.label("month"),
                func.sum(
                    case((Transaction.type == "income",
                         Transaction.amount), else_=0)
                ).label("income"),
                func.sum(
                    case((Transaction.type == "expense",
                         Transaction.amount), else_=0)
                ).label("expense"),
            )
            .where(Transaction.user_id == user_id)
            .group_by(month_expr)
            .order_by(month_expr)
        )

        return {
            "total_cash": float(total_balance or 0),
            "total_expense_this_month": float(total_expense or 0),
            "total_income_this_month": float(total_income or 0),
            "savings": float((total_income or 0) - (total_expense or 0)),
            "net_worth": float(total_balance or 0),
            "recent_transactions": [
                {
                    "id": t.id,
                    "amount": float(t.amount),
                    "type": t.type,
                    "date": t.txn_date,
                    "category_id": t.category_id,
                }
                for t in recent_res.scalars()
            ],
            "expense_by_category": [
                {"label": r.name, "value": float(r.total)}
                for r in cat_res
            ],
            "monthly_cashflow": [
                {
                    "month": r.month,
                    "income": float(r.income),
                    "expense": float(r.expense),
                }
                for r in cashflow_res
            ],
        }

    # =========================
    # CARD DASHBOARD
    # =========================
    async def get_card_dashboard(self, user_id: UUID, month: str):
        cards = await self.db.execute(
            select(Account).where(
                Account.user_id == user_id,
                Account.type == "card"
            )
        )
        cards = cards.scalars().all()
        card_ids = [c.id for c in cards]

        if not card_ids:
            return {
                "total_outstanding": 0,
                "monthly_spent": 0,
                "payments": 0,
                "utilization": 0,
                "cards": [],
            }

        start_date, end_date = self._get_month_range(month)

        spent = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.type == "expense",
                Transaction.account_id.in_(card_ids),
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
            )
        )

        paid = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.type == "transfer",
                Transaction.transfer_account_id.in_(card_ids),
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
            )
        )

        total_outstanding = sum(c.balance for c in cards)
        total_limit = sum(getattr(c, "credit_limit", 0) for c in cards) or 1

        return {
            "total_outstanding": total_outstanding,
            "monthly_spent": float(spent or 0),
            "payments": float(paid or 0),
            "utilization": round(abs(total_outstanding) / total_limit * 100, 2),
            "cards": [
                {
                    "id": str(c.id),
                    "name": c.name,
                    "balance": c.balance,
                    "limit": getattr(c, "credit_limit", 0),
                    "utilization": (
                        abs(c.balance) / c.credit_limit * 100
                        if getattr(c, "credit_limit", 0) > 0 else 0
                    ),
                }
                for c in cards
            ],
        }

    # =========================
    # CARD ANALYTICS (FIXED)
    # =========================
    async def get_card_analytics(self, user_id: UUID, month: str):
        cards = await self.db.execute(
            select(Account).where(
                Account.user_id == user_id,
                Account.type == "card"
            )
        )
        cards = cards.scalars().all()
        card_ids = [c.id for c in cards]

        if not card_ids:
            return {
                "spent": 0,
                "paid": 0,
                "net_change": 0,
                "payment_ratio": 0,
                "daily_trend": [],
                "category_breakdown": [],
                "suggested_payment": 0,
            }

        start_date, end_date = self._get_month_range(month)

        base_filter = and_(
            Transaction.user_id == user_id,
            Transaction.txn_date >= start_date,
            Transaction.txn_date < end_date,
        )

        spent = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                base_filter,
                Transaction.type == "expense",
                Transaction.account_id.in_(card_ids),
            )
        )

        paid = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                base_filter,
                Transaction.type == "transfer",
                Transaction.transfer_account_id.in_(card_ids),
            )
        )

        # SAFE DAILY (no func.date issue)
        date_expr = cast(Transaction.txn_date, Date)

        daily = await self.db.execute(
            select(
                date_expr.label("date"),
                func.sum(Transaction.amount).label("amount"),
            )
            .where(
                base_filter,
                Transaction.type == "expense",
                Transaction.account_id.in_(card_ids),
            )
            .group_by(date_expr)
            .order_by(date_expr)
        )

        daily_trend = [
            {"date": str(r.date), "amount": float(r.amount)}
            for r in daily
        ]

        # CATEGORY (WITH NAME 🔥)
        category = await self.db.execute(
            select(
                Category.name.label("category"),
                func.sum(Transaction.amount).label("amount"),
            )
            .join(Category, Category.id == Transaction.category_id)
            .where(
                base_filter,
                Transaction.type == "expense",
                Transaction.account_id.in_(card_ids),
            )
            .group_by(Category.name)
            .order_by(func.sum(Transaction.amount).desc())
        )

        category_data = [
            {"category": r.category, "amount": float(r.amount)}
            for r in category
        ]

        spent = float(spent or 0)
        paid = float(paid or 0)

        return {
            "spent": spent,
            "paid": paid,
            "net_change": spent - paid,
            "payment_ratio": round((paid / spent * 100) if spent else 0, 2),
            "daily_trend": daily_trend,
            "category_breakdown": category_data,
            "suggested_payment": round(max(spent * 0.5, paid * 0.2), 2),
        }
