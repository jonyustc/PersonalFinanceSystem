# Personal Finance Management API

Production-ready FastAPI backend for web and Android clients. It uses async SQLAlchemy, PostgreSQL, Alembic migrations, JWT authentication, clean service/repository layers, CORS, rate limiting, and typed Pydantic DTOs.

## Features

- Authentication: register, login, refresh token, current user, change password
- Users: profile update, default currency, soft delete
- Accounts: cash, bank, debit card, credit card, mobile banking
- Categories: income and expense CRUD
- Transactions: income, expense, transfer, automatic balance updates, filters, pagination, monthly summary
- Budgets: monthly budget, spending comparison, remaining amount, overspending flag
- Portfolio: buy/sell stocks, holdings, average buy price, profit/loss, dividends
- Dashboard: balances, income, expense, savings, net worth, investments, recent transactions, chart data
- Reports: monthly expenses, category report, income report, net worth trend, portfolio performance
- Notifications: budget/reminder-ready notification storage

## Project Structure

```text
backend/
  app/
    api/v1/endpoints/   # HTTP route handlers
    core/               # config, security, logging, rate limiting
    db/                 # async database session and metadata
    models/             # SQLAlchemy entities
    repositories/       # database access
    schemas/            # Pydantic request/response DTOs
    services/           # business logic
    utils/              # shared helpers
  alembic/              # migrations
  tests/                # pytest tests
```

## Quick Start

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Create PostgreSQL database and user:

```sql
CREATE USER finance WITH PASSWORD 'finance';
CREATE DATABASE personal_finance OWNER finance;
```

Run migrations:

```bash
alembic upgrade head
```

Start the API:

```bash
uvicorn app.main:app --reload
```

Open:

- API docs: `http://127.0.0.1:8000/docs`
- OpenAPI JSON: `http://127.0.0.1:8000/api/v1/openapi.json`

## Environment Variables

Copy `.env.example` to `.env` and update:

- `DATABASE_URL`
- `JWT_SECRET_KEY`
- `BACKEND_CORS_ORIGINS`
- token expiry settings

Use a long random `JWT_SECRET_KEY` in production and serve the API behind HTTPS.

## Tests

```bash
pytest
```

## API Overview

Authentication:

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/change-password`

Finance:

- `GET|POST /api/v1/accounts`
- `GET|PATCH|DELETE /api/v1/accounts/{account_id}`
- `GET|POST /api/v1/categories`
- `GET|PATCH|DELETE /api/v1/categories/{category_id}`
- `GET|POST /api/v1/transactions`
- `GET|PATCH|DELETE /api/v1/transactions/{transaction_id}`
- `GET /api/v1/transactions/monthly-summary`
- `GET|POST /api/v1/budgets`
- `PATCH|DELETE /api/v1/budgets/{budget_id}`
- `POST /api/v1/portfolio/transactions`
- `GET /api/v1/portfolio/summary`
- `GET|POST /api/v1/portfolio/dividends`
- `GET /api/v1/dashboard`
- `GET /api/v1/reports/*`
- `GET|POST /api/v1/notifications`

## Production Notes

- Run with a process manager such as Gunicorn/Uvicorn workers.
- Use managed PostgreSQL with backups and connection pooling.
- Store secrets in a vault or deployment secret manager.
- Restrict CORS origins to real web and mobile gateway domains.
- Add Redis-backed rate limiting before high-traffic deployment.
- Add background workers for scheduled bill reminders and budget alerts.
