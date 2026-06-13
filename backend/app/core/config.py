from functools import lru_cache

from pydantic import Field, PostgresDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "Personal Finance Management API"
    VERSION: str = "1.0.0"
    API_V1_PREFIX: str = "/api/v1"
    ENVIRONMENT: str = "development"

    DATABASE_URL: PostgresDsn = Field(
        default="postgresql+asyncpg://finance:finance@localhost:5432/personal_finance"
    )
    JWT_SECRET_KEY: str = Field(
        default="change-me-in-production", min_length=16)
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    # Long refresh window so "keep me signed in" survives weeks of inactivity;
    # clients silently refresh the access token whenever it expires.
    REFRESH_TOKEN_EXPIRE_DAYS: int = 60

    # Google "Sign in with Google" OAuth client IDs accepted as the ID-token
    # audience. Comma-separated to allow web + Android (+ iOS) clients at once.
    GOOGLE_CLIENT_IDS: str = Field(default="")

    # Store as string for env parsing, convert to list in property
    BACKEND_CORS_ORIGINS: str = Field(
        default="http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000,http://127.0.0.1:5173"
    )
    RATE_LIMIT_DEFAULT: str = "100/minute"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
    )

    @property
    def database_url(self) -> str:
        """Normalize Render-style DATABASE_URL values for the async engine."""
        import sys
        try:
            raw_url = str(self.DATABASE_URL)
            print(
                f"[CONFIG] Raw DATABASE_URL: {raw_url[:60]}...", file=sys.stderr)

            if raw_url.startswith("postgres://"):
                normalized = raw_url.replace(
                    "postgres://", "postgresql+asyncpg://", 1)
                print(f"[CONFIG] Normalized postgres:// to asyncpg",
                      file=sys.stderr)
                return normalized
            if raw_url.startswith("postgresql://"):
                normalized = raw_url.replace(
                    "postgresql://", "postgresql+asyncpg://", 1)
                print(f"[CONFIG] Normalized postgresql:// to asyncpg",
                      file=sys.stderr)
                return normalized

            print(f"[CONFIG] DATABASE_URL already normalized", file=sys.stderr)
            return raw_url
        except Exception as e:
            print(
                f"[CONFIG ERROR] Failed to normalize DATABASE_URL: {e}", file=sys.stderr)
            raise

    @property
    def cors_origins(self) -> list[str]:
        """Parse and normalize CORS origins from comma-separated string."""
        if not self.BACKEND_CORS_ORIGINS:
            return []
        # Split by comma and strip whitespace
        origins = [origin.strip() for origin in self.BACKEND_CORS_ORIGINS.split(
            ",") if origin.strip()]
        if not origins:
            raise ValueError(
                "BACKEND_CORS_ORIGINS must contain at least one URL")
        # Remove trailing slashes for consistency
        return [origin.rstrip("/") for origin in origins]

    @property
    def google_client_ids(self) -> list[str]:
        """Parse the accepted Google OAuth client IDs from the env string."""
        return [cid.strip() for cid in self.GOOGLE_CLIENT_IDS.split(",") if cid.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
