from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_password_hash, verify_password
from app.models.user import User
from app.schemas.user import ChangePasswordRequest, UserUpdate


class UserService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def update_profile(self, user: User, payload: UserUpdate) -> User:
        data = payload.model_dump(exclude_unset=True)
        for field, value in data.items():
            if field == "default_currency" and value:
                value = value.upper()
            setattr(user, field, value)
        await self.db.commit()
        await self.db.refresh(user)
        return user

    async def change_password(self, user: User, payload: ChangePasswordRequest) -> None:
        if not verify_password(payload.current_password, user.hashed_password):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Current password is incorrect")
        user.hashed_password = get_password_hash(payload.new_password)
        await self.db.commit()

    async def delete_account(self, user: User) -> None:
        user.is_active = False
        await self.db.commit()
