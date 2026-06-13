# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A personal finance management system in a single repo with three independently-built clients sharing one REST API:

- `backend/` — FastAPI (Python 3.14) + async SQLAlchemy + PostgreSQL. The source of truth and the only place business logic lives.
- `frontend/` — Next.js 16 (App Router) + React 19 + TypeScript web app.
- `mobile/` — Flutter (Dart) Android app, **offline-first** with a local SQLite mirror.

All clients talk to the same versioned API under `/api/v1`. The deployed API base is `https://personalfinancesystem.onrender.com/api/v1` (see `render.yaml`). The two clients deliberately re-implement the *same* domain behavior against that API — when you change finance rules in the backend, check whether the frontend (`src/lib/*.ts`) and mobile (`lib/src/core/finance_summary.dart`) mirror logic need the same change.

## Commands

### Backend (run from `backend/`)
```bash
pip install -r requirements.txt
alembic upgrade head                         # apply migrations (required before first run)
uvicorn app.main:app --reload                # dev server at http://127.0.0.1:8000 (docs at /docs)
pytest                                        # run all tests
pytest tests/test_portfolio_service.py        # single test file
pytest -k portfolio                           # tests matching an expression
ruff check app                                # lint
alembic revision -m "description"             # create a new migration
```
Tests use `asyncio_mode = auto` (`pytest.ini`) — no `@pytest.mark.asyncio` needed.

### Frontend (run from `frontend/`)
```bash
npm run dev          # dev server (next dev)
npm run build        # production build
npm run lint         # eslint
npm run typecheck    # tsc --noEmit
```

### Mobile (run from `mobile/`)
```bash
flutter pub get
flutter run                                                      # targets the production API by default
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1   # local backend (Android emulator)
flutter test                                                     # all tests
flutter test test/finance_summary_test.dart                      # single test file
flutter analyze                                                  # lint (rules in analysis_options.yaml)
```
Use `10.0.2.2` for the Android emulator and the machine's LAN IP for a physical device.

## Backend architecture

Strict layered flow — keep each concern in its layer:

```
api/v1/endpoints/  HTTP routing + auth dependency only; delegates immediately to a service
services/          ALL business logic + transaction boundaries (commit/rollback live here)
repositories/      DB access primitives (BaseRepository.create/get/delete only flush)
models/            SQLAlchemy entities
schemas/           Pydantic request/response DTOs (the API contract)
```

Key conventions:

- **Transaction ownership is in services, not repositories.** `BaseRepository` only `flush()`es. Services call `await self.db.commit()` on success and `await self.db.rollback()` on exceptions (see `services/transaction.py`). Don't commit inside a repository.
- **Auth.** Every protected endpoint depends on `get_current_user` (`api/v1/deps.py`), which decodes the JWT access token and loads the `User`. Access + refresh tokens are issued in `core/security.py`; the refresh flow is `POST /api/v1/auth/refresh`.
- **DB session.** `db/session.py` builds the async engine with `NullPool` and per-connection statement-cache disabled — this is intentional for the Render/pooled-Postgres setup (asyncpg + PgBouncer); don't re-enable prepared-statement caching.
- **Config.** `core/config.py` (`pydantic-settings`, reads `backend/.env`). `settings.database_url` normalizes Render's `postgres://` / `postgresql://` URLs to `postgresql+asyncpg://`. `BACKEND_CORS_ORIGINS` is a comma-separated string parsed into a list.
- **Migrations are idempotent.** Every Alembic step uses `IF NOT EXISTS`-style guards because `render.yaml` runs `alembic upgrade head` on *every* deploy/start. New migrations must follow this pattern so they're safe to re-run.
- **Routing.** All routers are registered in `api/v1/router.py` and mounted under `API_V1_PREFIX` (`/api/v1`) in `main.py`. Note `accounts`, `card`/`cards`, `funds`, and `monthly_income` share or nest prefixes — check the router before assuming a path.
- Rate limiting via `slowapi` (`core/rate_limit.py`); global exception handlers for SQLAlchemy / validation errors are in `main.py`.

Core domain: accounts (cash/bank/debit/credit-card/mobile-banking), categories, transactions (income/expense/transfer with automatic balance updates), budgets, stock portfolio, funds, dashboard, and reports.

## Frontend architecture

Next.js App Router. Routes live in `src/app/` (auth pages under `app/auth/`, the authenticated app under `app/dashboard/`). UI in `src/components/`, domain helpers in `src/lib/`.

- **All HTTP goes through `src/services/api.ts`** (`apiRequest`). It injects the bearer token, and on a `401` it transparently calls `/auth/refresh` (de-duped via a shared `refreshPromise`), retries once, and otherwise clears the session and redirects to `/auth/login`. Don't call `fetch` directly from components.
- Domain calls are wrapped in `services/finance-service.ts` and `services/auth-service.ts`; tokens are persisted via `services/token-store.ts`. API types live in `src/types/api.ts`.
- API base URL comes from `NEXT_PUBLIC_API_BASE_URL` (falls back to the production Render URL).
- Server state via `@tanstack/react-query` (`components/providers/query-provider.tsx`); forms via `react-hook-form` + `zod`; charts via `recharts`; styling via Tailwind.

## Mobile architecture

Flutter + Riverpod, **offline-first**. State is a single `AppController` (`AsyncNotifierProvider`, `lib/src/state/app_controller.dart`) exposing an immutable `AppSnapshot`.

- **`AppDatabase`** (`core/app_database.dart`, sqflite) is the local mirror. The UI reads from it so the app works offline.
- **`SyncService`** (`core/sync_service.dart`) is the sync engine: it first **replays queued local mutations** (offline writes are queued in the DB and POST/PATCH'd on reconnect), then pulls each resource and replaces the local cache. Individual resource failures are tolerated so one bad endpoint doesn't block the rest.
- **`ApiClient`** (`core/api_client.dart`, dio) handles HTTP and triggers session expiry. `SessionStore` (`shared_preferences`) holds the session.
- Navigation: `go_router`; theme in `lib/src/theme/`. Features are organized under `lib/src/features/<feature>/`.
- API base URL is compile-time via `--dart-define=API_BASE_URL=...` (defaults to production).

## Deployment

`render.yaml` defines the backend web service (`rootDir: backend`, Python 3.14). Start command runs migrations then the server: `alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT`. Secrets (`DATABASE_URL`, `JWT_SECRET_KEY`, `BACKEND_CORS_ORIGINS`) are injected as env vars, not committed.
