from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token, create_refresh_token, decode_token, get_password_hash, verify_password
from app.repositories.user import UserRepository
from app.schemas.auth import AuthResponse, TokenResponse
from app.schemas.user import UserCreate


class AuthService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.users = UserRepository(db)

    async def register(self, payload: UserCreate) -> AuthResponse:
        existing = await self.users.get_by_email(payload.email)
        if existing:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")
        user = await self.users.create(
            {
                "full_name": payload.full_name,
                "email": payload.email.lower(),
                "hashed_password": get_password_hash(payload.password),
            }
        )
        await self.db.commit()
        return AuthResponse(
            access_token=create_access_token(user.id),
            refresh_token=create_refresh_token(user.id),
            user=user,
        )

    async def login(self, email: str, password: str) -> AuthResponse:
        user = await self.users.get_by_email(email)
        if not user or not verify_password(password, user.hashed_password):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")
        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User account is disabled")
        return AuthResponse(
            access_token=create_access_token(user.id),
            refresh_token=create_refresh_token(user.id),
            user=user,
        )

    async def refresh(self, refresh_token: str) -> TokenResponse:
        try:
            payload = decode_token(refresh_token, expected_type="refresh")
            user = await self.users.get(payload["sub"])
        except Exception as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token") from exc
        if not user or not user.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
        return TokenResponse(access_token=create_access_token(user.id), refresh_token=create_refresh_token(user.id))
