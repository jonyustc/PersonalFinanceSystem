from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.models.account import Account, AccountBalanceHistory, AccountTransfer, CreditCardDetails
from app.repositories.base import BaseRepository


class AccountRepository(BaseRepository[Account]):
    model = Account

    async def list_by_user(self, user_id: UUID) -> list[Account]:
        result = await self.db.execute(
            select(Account)
            .options(selectinload(Account.credit_card_details))
            .where(Account.user_id == user_id)
            .order_by(Account.type, Account.name)
        )
        return list(result.scalars())

    async def get_user_owned(self, user_id: UUID, account_id: UUID) -> Account | None:
        result = await self.db.execute(
            select(Account)
            .options(selectinload(Account.credit_card_details))
            .where(Account.id == account_id, Account.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def create_card_details(self, details: CreditCardDetails) -> CreditCardDetails:
        self.db.add(details)
        await self.db.flush()
        await self.db.refresh(details)
        return details

    async def create_transfer(self, transfer: AccountTransfer) -> AccountTransfer:
        self.db.add(transfer)
        await self.db.flush()
        await self.db.refresh(transfer)
        return transfer

    async def create_balance_history(self, history: AccountBalanceHistory) -> AccountBalanceHistory:
        self.db.add(history)
        await self.db.flush()
        await self.db.refresh(history)
        return history

    async def balance_history_since(self, user_id: UUID, days: int = 180) -> list[tuple[datetime, Decimal]]:
        since = datetime.now(UTC) - timedelta(days=days)
        result = await self.db.execute(
            select(
                func.date(AccountBalanceHistory.balance_date).label("date"),
                func.sum(AccountBalanceHistory.closing_balance).label("net_worth"),
            )
            .join(Account, Account.id == AccountBalanceHistory.account_id)
            .where(Account.user_id == user_id, AccountBalanceHistory.balance_date >= since)
            .group_by(func.date(AccountBalanceHistory.balance_date))
            .order_by(func.date(AccountBalanceHistory.balance_date))
        )
        return [(row.date, row.net_worth or Decimal("0")) for row in result.all()]
