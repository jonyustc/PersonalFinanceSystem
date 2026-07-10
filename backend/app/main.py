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
from sqlalchemy.exc import SQLAlchemyError

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.logging import configure_logging
from app.core.rate_limit import limiter

logger = logging.getLogger("app.api")


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
