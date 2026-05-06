from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from app.schemas.common import Timestamped


# ===============================
# 🔹 BASE
# ===============================
class UserBase(BaseModel):
    full_name: str = Field(min_length=2, max_length=255)
    email: EmailStr


# ===============================
# 🔹 CREATE
# ===============================
class UserCreate(UserBase):
    password: str = Field(min_length=8, max_length=128)


# ===============================
# 🔹 UPDATE
# ===============================
class UserUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=255)
    currency: str | None = Field(
        default=None, min_length=3, max_length=3)  # ✅ FIX


# ===============================
# 🔹 RESPONSE
# ===============================
class UserResponse(Timestamped):
    id: UUID
    full_name: str
    email: EmailStr
    currency: str  # ✅ FIX
    is_active: bool

    class Config:
        from_attributes = True


# ===============================
# 🔹 PASSWORD CHANGE
# ===============================
class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8, max_length=128)
