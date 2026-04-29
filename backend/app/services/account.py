from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.repositories.account import AccountRepository
from app.schemas.account import AccountCreate, AccountUpdate


class AccountService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.accounts = AccountRepository(db)

    async def create(self, user_id: UUID, payload: AccountCreate) -> Account:
        data = payload.model_dump()
        data["user_id"] = user_id
        data["currency"] = data["currency"].upper()
        data["current_balance"] = data["opening_balance"]
        account = await self.accounts.create(data)
        await self.db.commit()
        return account

    async def list(self, user_id: UUID) -> list[Account]:
        return await self.accounts.list_by_user(user_id)

    async def get(self, user_id: UUID, account_id: UUID) -> Account:
        account = await self.accounts.get_user_owned(user_id, account_id)
        if not account:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
        return account

    async def update(self, user_id: UUID, account_id: UUID, payload: AccountUpdate) -> Account:
        account = await self.get(user_id, account_id)
        for field, value in payload.model_dump(exclude_unset=True).items():
            if field == "currency" and value:
                value = value.upper()
            setattr(account, field, value)
        await self.db.commit()
        await self.db.refresh(account)
        return account

    async def delete(self, user_id: UUID, account_id: UUID) -> None:
        account = await self.get(user_id, account_id)
        await self.accounts.delete(account)
        await self.db.commit()
