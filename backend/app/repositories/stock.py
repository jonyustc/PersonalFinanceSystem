from datetime import date
from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.account import Account
from app.models.portfolio import Portfolio, PortfolioValueSnapshot
from app.models.stock import Dividend, Holding, PortfolioTransaction, Stock


class StockRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ----- Portfolios -------------------------------------------------------
    async def portfolios(self, user_id: UUID) -> list[Portfolio]:
        result = await self.db.execute(
            select(Portfolio)
            .where(Portfolio.user_id == user_id)
            .order_by(Portfolio.is_default.desc(), Portfolio.created_at)
        )
        return list(result.scalars())

    async def get_portfolio(self, user_id: UUID, portfolio_id: UUID) -> Portfolio | None:
        result = await self.db.execute(
            select(Portfolio).where(
                Portfolio.user_id == user_id, Portfolio.id == portfolio_id
            )
        )
        return result.scalar_one_or_none()

    async def get_default_portfolio(self, user_id: UUID) -> Portfolio | None:
        result = await self.db.execute(
            select(Portfolio)
            .where(Portfolio.user_id == user_id, Portfolio.is_default.is_(True))
            .order_by(Portfolio.created_at)
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def get_portfolio_by_name(self, user_id: UUID, name: str) -> Portfolio | None:
        result = await self.db.execute(
            select(Portfolio).where(
                Portfolio.user_id == user_id,
                func.lower(Portfolio.name) == name.strip().lower(),
            )
        )
        return result.scalar_one_or_none()

    # ----- Snapshots --------------------------------------------------------
    async def get_snapshot(
        self, user_id: UUID, portfolio_id: UUID, snapshot_date: date
    ) -> PortfolioValueSnapshot | None:
        result = await self.db.execute(
            select(PortfolioValueSnapshot).where(
                PortfolioValueSnapshot.user_id == user_id,
                PortfolioValueSnapshot.portfolio_id == portfolio_id,
                PortfolioValueSnapshot.snapshot_date == snapshot_date,
            )
        )
        return result.scalar_one_or_none()

    async def snapshots(
        self, user_id: UUID, portfolio_id: UUID | None = None
    ) -> list[PortfolioValueSnapshot]:
        query = select(PortfolioValueSnapshot).where(
            PortfolioValueSnapshot.user_id == user_id
        )
        if portfolio_id is not None:
            query = query.where(PortfolioValueSnapshot.portfolio_id == portfolio_id)
        query = query.order_by(PortfolioValueSnapshot.snapshot_date)
        result = await self.db.execute(query)
        return list(result.scalars())

    async def stocks(self) -> list[Stock]:
        result = await self.db.execute(select(Stock).order_by(Stock.name))
        return list(result.scalars())

    async def get_stock(self, stock_id: UUID) -> Stock | None:
        return await self.db.get(Stock, stock_id)

    async def get_stock_by_symbol(self, symbol: str) -> Stock | None:
        result = await self.db.execute(select(Stock).where(func.upper(Stock.symbol) == symbol.strip().upper()))
        return result.scalar_one_or_none()

    async def get_or_create_stock(self, payload) -> Stock:
        symbol = payload.symbol.strip().upper()
        existing = (await self.db.execute(select(Stock).where(func.upper(Stock.symbol) == symbol))).scalar_one_or_none()
        if existing:
            existing.name = payload.name
            existing.exchange = payload.exchange
            existing.currency = payload.currency.upper()
            existing.last_price = payload.last_price
            return existing
        stock = Stock(
            symbol=symbol,
            name=payload.name.strip(),
            exchange=payload.exchange,
            currency=payload.currency.upper(),
            last_price=payload.last_price,
        )
        self.db.add(stock)
        await self.db.flush()
        return stock

    async def transactions(
        self, user_id: UUID, limit: int = 100, portfolio_id: UUID | None = None
    ) -> list[PortfolioTransaction]:
        query = (
            select(PortfolioTransaction)
            .options(selectinload(PortfolioTransaction.stock))
            .where(PortfolioTransaction.user_id == user_id)
        )
        if portfolio_id is not None:
            query = query.where(PortfolioTransaction.portfolio_id == portfolio_id)
        query = query.order_by(
            PortfolioTransaction.txn_date.desc(), PortfolioTransaction.created_at.desc()
        ).limit(limit)
        result = await self.db.execute(query)
        return list(result.scalars())

    async def get_transaction(self, user_id: UUID, transaction_id: UUID) -> PortfolioTransaction | None:
        result = await self.db.execute(
            select(PortfolioTransaction)
            .options(selectinload(PortfolioTransaction.stock))
            .where(PortfolioTransaction.user_id == user_id, PortfolioTransaction.id == transaction_id)
        )
        return result.scalar_one_or_none()

    async def holdings(
        self, user_id: UUID, portfolio_id: UUID | None = None
    ) -> list[Holding]:
        query = (
            select(Holding)
            .options(selectinload(Holding.stock))
            .where(Holding.user_id == user_id)
        )
        if portfolio_id is not None:
            query = query.where(Holding.portfolio_id == portfolio_id)
        query = query.order_by(Holding.created_at)
        result = await self.db.execute(query)
        return list(result.scalars())

    async def holding_for_update(self, user_id: UUID, stock_id: UUID) -> Holding | None:
        result = await self.db.execute(select(Holding).where(Holding.user_id == user_id, Holding.stock_id == stock_id))
        return result.scalar_one_or_none()

    async def dividends(
        self, user_id: UUID, portfolio_id: UUID | None = None
    ) -> list[Dividend]:
        query = (
            select(Dividend)
            .options(selectinload(Dividend.stock))
            .where(Dividend.user_id == user_id)
        )
        if portfolio_id is not None:
            query = query.where(Dividend.portfolio_id == portfolio_id)
        query = query.order_by(Dividend.payment_date.desc())
        result = await self.db.execute(query)
        return list(result.scalars())

    async def broker_accounts(self, user_id: UUID) -> list[Account]:
        linked_broker_account_ids = (
            select(PortfolioTransaction.broker_account_id)
            .where(
                PortfolioTransaction.user_id == user_id,
                PortfolioTransaction.broker_account_id.is_not(None),
            )
            .distinct()
        )
        result = await self.db.execute(
            select(Account)
            .where(Account.user_id == user_id, Account.archived.is_(False))
            .where(Account.is_active.is_(True))
            .where(
                or_(
                    func.lower(func.replace(Account.account_subtype, " ", "_")).in_(
                        ("stock_broker", "broker", "stock", "stocks")
                    ),
                    Account.id.in_(linked_broker_account_ids),
                )
            )
            .order_by(Account.name)
        )
        return list(result.scalars())
