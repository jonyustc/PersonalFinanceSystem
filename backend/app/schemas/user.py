from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from app.schemas.common import Timestamped


class UserBase(BaseModel):
    full_name: str = Field(min_length=2, max_length=255)
    email: EmailStr


class UserCreate(UserBase):
    password: str = Field(min_length=8, max_length=128)


class UserUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=255)
    default_currency: str | None = Field(default=None, min_length=3, max_length=3)


class UserResponse(Timestamped):
    id: UUID
    full_name: str
    email: EmailStr
    default_currency: str
    is_active: bool


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8, max_length=128)
