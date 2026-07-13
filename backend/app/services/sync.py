"""Delta-sync read model for offline clients.

``GET /sync/changes?since=<ts>`` returns, per resource, the rows whose
``updated_at`` is newer than the client's watermark, plus tombstones for rows
hard-deleted since then and a fresh ``server_time`` the client stores as its
next watermark. Rows are serialized with the SAME response schemas the existing
list endpoints use, so the mobile mirror can parse them with its current
mappers. ``since=None`` (first sync) returns everything.
"""
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.budget import Budget
from app.models.category import Category
from app.models.monthly_income import MonthlyIncome
from app.models.portfolio import Portfolio
from app.models.stock import PortfolioTransaction, Stock
from app.models.sync import SyncTombstone
from app.models.transaction import Transaction
from app.schemas.account import AccountResponse
from app.schemas.stock import PortfolioResponse, StockResponse
from app.schemas.transaction import TransactionResponse
from app.services.category import CategoryService
from app.services.portfolio import PortfolioService


class SyncService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def changes(self, user_id: UUID, since: datetime | None) -> dict:
        # Capture the watermark BEFORE reading: any row committed during this
        # request keeps updated_at <= server_time and is caught next sync, so a
        # concurrent write is re-sent (harmless upsert) rather than lost.
        server_time = datetime.now(UTC)

        accounts = await self._user_rows(Account, user_id, since)
        categories = await self._user_rows(Category, user_id, since)
        transactions = await self._user_rows(Transaction, user_id, since)
        budgets = await self._user_rows(Budget, user_id, since)
        incomes = await self._user_rows(MonthlyIncome, user_id, since)
        portfolios = await self._user_rows(Portfolio, user_id, since)
        portfolio_txns = await self._user_rows(PortfolioTransaction, user_id, since)
        stocks = await self._stock_rows(since)

        cat_service = CategoryService(self.db)
        pf_service = PortfolioService(self.db)

        changes = {
            "accounts": [AccountResponse.model_validate(a) for a in accounts],
            "categories": [cat_service.to_dict(c) for c in categories],
            "transactions": [TransactionResponse.model_validate(t) for t in transactions],
            "budgets": [self._budget_dict(b) for b in budgets],
            "monthly_income": [self._income_dict(m) for m in incomes],
            "stocks": [StockResponse.model_validate(s) for s in stocks],
            # Mirror the /portfolio/transactions list: derived fields via
            # _response_transaction, and deposits are internal-only.
            "portfolio_transactions": [
                await pf_service._response_transaction(p)
                for p in portfolio_txns
                if p.txn_type != "deposit"
            ],
            "portfolios": [PortfolioResponse.model_validate(p) for p in portfolios],
        }

        return {
            "server_time": server_time,
            "changes": changes,
            "tombstones": await self._tombstones(user_id, since),
        }

    async def _user_rows(self, model, user_id: UUID, since: datetime | None):
        stmt = select(model).where(model.user_id == user_id)
        if since is not None:
            stmt = stmt.where(model.updated_at > since)
        return list((await self.db.execute(stmt)).scalars())

    async def _stock_rows(self, since: datetime | None):
        # Stocks are a shared (non-user-scoped) reference table of DSE symbols.
        stmt = select(Stock)
        if since is not None:
            stmt = stmt.where(Stock.updated_at > since)
        return list((await self.db.execute(stmt)).scalars())

    async def _tombstones(self, user_id: UUID, since: datetime | None):
        stmt = select(SyncTombstone).where(SyncTombstone.user_id == user_id)
        if since is not None:
            stmt = stmt.where(SyncTombstone.deleted_at > since)
        rows = list((await self.db.execute(stmt)).scalars())
        return [
            {
                "resource": r.resource,
                "entity_id": r.entity_id,
                "deleted_at": r.deleted_at,
            }
            for r in rows
        ]

    def _budget_dict(self, b: Budget) -> dict:
        return {
            "id": b.id,
            "category_id": b.category_id,
            "amount": b.amount,
            "month": b.month,
        }

    def _income_dict(self, m: MonthlyIncome) -> dict:
        return {
            "id": m.id,
            "month": m.month,
            "amount": m.amount,
            "opening_balance": m.opening_balance,
        }
