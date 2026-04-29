from uuid import UUID

from sqlalchemy import select

from app.models.account import Account
from app.repositories.base import BaseRepository


class AccountRepository(BaseRepository[Account]):
    model = Account

    async def list_by_user(self, user_id: UUID) -> list[Account]:
        result = await self.db.execute(select(Account).where(Account.user_id == user_id).order_by(Account.name))
        return list(result.scalars())

    async def get_user_owned(self, user_id: UUID, account_id: UUID) -> Account | None:
        result = await self.db.execute(select(Account).where(Account.id == account_id, Account.user_id == user_id))
        return result.scalar_one_or_none()
