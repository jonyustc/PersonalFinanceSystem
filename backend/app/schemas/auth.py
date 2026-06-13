from pydantic import BaseModel, EmailStr, Field

from app.schemas.user import UserCreate, UserResponse


# ===============================
# 🔹 LOGIN
# ===============================
class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1)


# ===============================
# 🔹 TOKEN RESPONSE
# ===============================
class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


# ===============================
# 🔹 REFRESH TOKEN
# ===============================
class RefreshTokenRequest(BaseModel):
    refresh_token: str


# ===============================
# 🔹 GOOGLE LOGIN
# ===============================
class GoogleLoginRequest(BaseModel):
    # The ID token (JWT credential) returned by Google Identity Services on the
    # web, or by the google_sign_in plugin on mobile.
    id_token: str = Field(min_length=1)


# ===============================
# 🔹 AUTH RESPONSE
# ===============================
class AuthResponse(TokenResponse):
    # ✅ must match UserResponse (currency, not default_currency)
    user: UserResponse


# ===============================
# 🔹 REGISTER
# ===============================
RegisterRequest = UserCreate
