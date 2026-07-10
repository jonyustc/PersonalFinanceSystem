from decimal import Decimal
from datetime import date, datetime, time, timedelta

from sqlalchemy import select, func, extract, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models.account import Account
from app.models.category import Category
from app.models.transaction import Transaction
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

    def _credit_card_filter(self):
        return func.lower(Account.type).in_(["card", "credit_card"])

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

    async def card_report(self, user_id, from_date=None, to_date=None):
        CardAccount = aliased(Account)
        SourceAccount = aliased(Account)
        card_result = await self.db.execute(
            select(Account)
            .where(
                Account.user_id == user_id,
                Account.is_active.is_(True),
                Account.archived.is_(False),
                self._credit_card_filter(),
            )
            .order_by(Account.name)
        )
        cards = list(card_result.scalars())
        card_ids = [card.id for card in cards]
        date_conditions = self._date_range_conditions(from_date, to_date)

        if not card_ids:
            return {
                "from_date": from_date,
                "to_date": to_date,
                "total_spent": Decimal("0"),
                "total_paid": Decimal("0"),
                "net_change": Decimal("0"),
                "total_outstanding": Decimal("0"),
                "cards": [],
                "spent_history": [],
                "payment_history": [],
            }

        spent_rows = await self.db.execute(
            select(
                Transaction.account_id.label("card_id"),
                func.coalesce(func.sum(Transaction.amount), 0).label("amount"),
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.transaction_status == "posted",
                Transaction.account_id.in_(card_ids),
                or_(
                    Transaction.type == "expense",
                    Transaction.transaction_type == "CARD_SPENDING",
                ),
                *date_conditions,
            )
            .group_by(Transaction.account_id)
        )
        spent_by_card = {row.card_id: row.amount or Decimal("0") for row in spent_rows}

        payment_rows = await self.db.execute(
            select(
                Transaction.transfer_account_id.label("card_id"),
                func.coalesce(func.sum(Transaction.amount), 0).label("amount"),
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.transaction_status == "posted",
                Transaction.transfer_account_id.in_(card_ids),
                Transaction.type == "transfer",
                or_(
                    Transaction.transaction_type == "CARD_PAYMENT",
                    Transaction.transaction_type == "transfer",
                ),
                *date_conditions,
            )
            .group_by(Transaction.transfer_account_id)
        )
        paid_by_card = {row.card_id: row.amount or Decimal("0") for row in payment_rows}

        spent_history_result = await self.db.execute(
            select(Transaction, Account.name.label("card_name"))
            .join(Account, Account.id == Transaction.account_id)
            .where(
                Transaction.user_id == user_id,
                Transaction.transaction_status == "posted",
                Transaction.account_id.in_(card_ids),
                or_(
                    Transaction.type == "expense",
                    Transaction.transaction_type == "CARD_SPENDING",
                ),
                *date_conditions,
            )
            .order_by(Transaction.txn_date.desc(), Transaction.id.desc())
            .limit(100)
        )

        payment_history_result = await self.db.execute(
            select(
                Transaction,
                CardAccount.name.label("card_name"),
                SourceAccount.name.label("account_name"),
            )
            .join(CardAccount, CardAccount.id == Transaction.transfer_account_id)
            .join(SourceAccount, SourceAccount.id == Transaction.account_id)
            .where(
                Transaction.user_id == user_id,
                Transaction.transaction_status == "posted",
                Transaction.transfer_account_id.in_(card_ids),
                Transaction.type == "transfer",
                or_(
                    Transaction.transaction_type == "CARD_PAYMENT",
                    Transaction.transaction_type == "transfer",
                ),
                *date_conditions,
            )
            .order_by(Transaction.txn_date.desc(), Transaction.id.desc())
            .limit(100)
        )

        total_spent = sum(spent_by_card.values(), Decimal("0"))
        total_paid = sum(paid_by_card.values(), Decimal("0"))
        total_outstanding = sum((card.current_outstanding for card in cards), Decimal("0"))

        return {
            "from_date": from_date,
            "to_date": to_date,
            "total_spent": total_spent,
            "total_paid": total_paid,
            "net_change": total_spent - total_paid,
            "total_outstanding": total_outstanding,
            "cards": [
                {
                    "id": str(card.id),
                    "name": card.name,
                    "credit_limit": card.credit_limit or Decimal("0"),
                    "current_outstanding": card.current_outstanding or Decimal("0"),
                    "spent": spent_by_card.get(card.id, Decimal("0")),
                    "paid": paid_by_card.get(card.id, Decimal("0")),
                }
                for card in cards
            ],
            "spent_history": [
                self._card_report_transaction(row[0], row.card_name)
                for row in spent_history_result
            ],
            "payment_history": [
                self._card_report_transaction(
                    row[0],
                    row.card_name,
                    account_name=row.account_name,
                )
                for row in payment_history_result
            ],
        }

    def _card_report_transaction(self, transaction, card_name, account_name=None):
        return {
            "id": str(transaction.id),
            "card_id": str(transaction.transfer_account_id or transaction.account_id)
            if (transaction.transfer_account_id or transaction.account_id)
            else None,
            "card_name": card_name,
            "account_name": account_name,
            "amount": transaction.amount or Decimal("0"),
            "txn_date": transaction.txn_date.date().isoformat(),
            "description": transaction.description,
            "merchant_name": transaction.merchant_name,
        }
