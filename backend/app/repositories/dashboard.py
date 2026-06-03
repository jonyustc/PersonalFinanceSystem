from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.transaction import Transaction


ZERO = Decimal("0")
ACTIVE_BALANCE_TYPES = ("cash", "bank", "mobile_banking")
CARD_TYPES = ("card", "credit_card", "debit_card")
CREDIT_CARD_TYPES = ("card", "credit_card")


class DashboardRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def active_balance_accounts(self, user_id: UUID) -> list[Account]:
        result = await self.db.execute(
            select(Account)
            .where(
                Account.user_id == user_id,
                Account.is_active.is_(True),
                Account.archived.is_(False),
                func.lower(Account.type).in_(ACTIVE_BALANCE_TYPES),
            )
            .order_by(Account.name)
        )
        return list(result.scalars())

    async def credit_cards(self, user_id: UUID) -> list[Account]:
        result = await self.db.execute(
            select(Account)
            .where(
                Account.user_id == user_id,
                Account.is_active.is_(True),
                Account.archived.is_(False),
                func.lower(Account.type).in_(CREDIT_CARD_TYPES),
            )
            .order_by(Account.name)
        )
        return list(result.scalars())

    async def monthly_card_spending(
        self,
        user_id: UUID,
        start_date: datetime,
        end_date: datetime,
    ) -> dict[UUID, Decimal]:
        rows = await self.db.execute(
            select(Transaction.account_id, func.coalesce(func.sum(Transaction.amount), 0).label("amount"))
            .join(Account, Account.id == Transaction.account_id)
            .where(
                Transaction.user_id == user_id,
                or_(Transaction.type == "expense", Transaction.transaction_type == "CARD_SPENDING"),
                Transaction.transaction_status == "posted",
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
                func.lower(Account.type).in_(CARD_TYPES),
            )
            .group_by(Transaction.account_id)
        )
        return {row.account_id: row.amount or ZERO for row in rows}

    async def monthly_credit_card_payments(
        self,
        user_id: UUID,
        start_date: datetime,
        end_date: datetime,
    ) -> dict[UUID, Decimal]:
        rows = await self.db.execute(
            select(Transaction.transfer_account_id, func.coalesce(func.sum(Transaction.amount), 0).label("amount"))
            .join(Account, Account.id == Transaction.transfer_account_id)
            .where(
                Transaction.user_id == user_id,
                Transaction.type == "transfer",
                Transaction.transaction_status == "posted",
                Transaction.transfer_account_id.is_not(None),
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
                func.lower(Account.type).in_(CREDIT_CARD_TYPES),
                (Transaction.transaction_type == "CARD_PAYMENT") | (Transaction.transaction_type == "transfer"),
            )
            .group_by(Transaction.transfer_account_id)
        )
        return {row.transfer_account_id: row.amount or ZERO for row in rows}
