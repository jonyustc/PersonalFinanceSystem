import secrets

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.google_oauth import GoogleTokenError, verify_google_id_token
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

    async def login_with_google(self, id_token: str) -> AuthResponse:
        if not settings.google_client_ids:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Google login is not configured",
            )

        try:
            claims = await verify_google_id_token(id_token, settings.google_client_ids)
        except GoogleTokenError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Google credential") from exc

        email = claims["email"].lower()

        # Reuse an existing account (including legacy Supabase users) by email so
        # all their data carries over — we never create a duplicate for an email
        # that is already registered.
        user = await self.users.get_by_email(email)
        if user is None:
            user = await self.users.create(
                {
                    "full_name": claims.get("name") or email.split("@")[0],
                    "email": email,
                    # The account is keyed to Google; store an unusable random
                    # password so the NOT NULL column is satisfied and nobody can
                    # log in with a password until they set one.
                    "hashed_password": get_password_hash(secrets.token_urlsafe(48)),
                }
            )
            await self.db.commit()
        elif not user.is_active:
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
