import sys
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError, ResponseValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.logging import configure_logging
from app.core.rate_limit import limiter
from app.db.session import engine

logger = logging.getLogger("app.api")


# Idempotent DDL for the offline-sync tombstone table. Kept identical to
# migration 20260712_0001 and run at startup as a safety net: this deployment's
# Supabase schema is partly aligned by hand, so a fresh table shipped only via
# Alembic can be missing on the running DB and every /sync call 500s. CREATE ...
# IF NOT EXISTS makes this a no-op once the table is present.
_SYNC_TOMBSTONES_DDL = (
    """
    CREATE TABLE IF NOT EXISTS sync_tombstones (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        resource varchar(40) NOT NULL,
        entity_id uuid NOT NULL,
        deleted_at timestamptz NOT NULL DEFAULT now()
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_sync_tombstones_user_id ON sync_tombstones (user_id)",
    "CREATE INDEX IF NOT EXISTS ix_sync_tombstones_deleted_at ON sync_tombstones (deleted_at)",
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_sync_tombstones_user_resource_entity "
    "ON sync_tombstones (user_id, resource, entity_id)",
)


async def _ensure_sync_schema() -> None:
    """Best-effort: guarantee the sync tombstone table exists before serving.

    Runs the idempotent DDL above. Failures are logged but never crash startup —
    the rest of the API must stay up even if this can't run.
    """
    try:
        async with engine.begin() as conn:
            for statement in _SYNC_TOMBSTONES_DDL:
                await conn.execute(text(statement))
        print("[STARTUP] sync_tombstones schema ensured", file=sys.stderr)
    except Exception as e:  # noqa: BLE001 - log and continue
        print(f"[STARTUP WARN] ensure sync schema failed: {type(e).__name__}: {e}",
              file=sys.stderr)


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        configure_logging()
        print("[STARTUP] App initialized successfully", file=sys.stderr)
        print(
            f"[STARTUP] Database URL normalized to: {settings.database_url[:50]}...", file=sys.stderr)
        print(
            f"[STARTUP] CORS origins: {settings.cors_origins}", file=sys.stderr)
    except Exception as e:
        print(f"[STARTUP ERROR] {type(e).__name__}: {str(e)}", file=sys.stderr)
        raise
    await _ensure_sync_schema()
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.PROJECT_NAME,
        version=settings.VERSION,
        openapi_url=f"{settings.API_V1_PREFIX}/openapi.json",
        lifespan=lifespan,
    )
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_exception_handler(SQLAlchemyError, sqlalchemy_exception_handler)
    app.add_exception_handler(RequestValidationError, request_validation_exception_handler)
    app.add_exception_handler(ResponseValidationError, response_validation_exception_handler)
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(api_router, prefix=settings.API_V1_PREFIX)
    return app


async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError) -> JSONResponse:
    logger.exception(
        "database_error",
        extra={"path": request.url.path, "method": request.method, "error_type": type(exc).__name__},
    )
    return JSONResponse(status_code=500, content={"detail": "Database operation failed"})


async def request_validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    errors = jsonable_encoder(exc.errors())
    logger.warning(
        "request_validation_error",
        extra={"path": request.url.path, "method": request.method, "errors": errors},
    )
    return JSONResponse(status_code=422, content={"detail": errors})


async def response_validation_exception_handler(request: Request, exc: ResponseValidationError) -> JSONResponse:
    errors = jsonable_encoder(exc.errors())
    logger.exception(
        "response_validation_error",
        extra={"path": request.url.path, "method": request.method, "errors": errors},
    )
    return JSONResponse(status_code=500, content={"detail": "Response validation failed"})


app = create_app()
