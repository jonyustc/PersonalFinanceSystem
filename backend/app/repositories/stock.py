from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.account import Account
from app.models.stock import Dividend, Holding, PortfolioTransaction, Stock


class StockRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

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

    async def transactions(self, user_id: UUID, limit: int = 100) -> list[PortfolioTransaction]:
        result = await self.db.execute(
            select(PortfolioTransaction)
            .options(selectinload(PortfolioTransaction.stock))
            .where(PortfolioTransaction.user_id == user_id)
            .order_by(PortfolioTransaction.txn_date.desc(), PortfolioTransaction.created_at.desc())
            .limit(limit)
        )
        return list(result.scalars())

    async def get_transaction(self, user_id: UUID, transaction_id: UUID) -> PortfolioTransaction | None:
        result = await self.db.execute(
            select(PortfolioTransaction)
            .options(selectinload(PortfolioTransaction.stock))
            .where(PortfolioTransaction.user_id == user_id, PortfolioTransaction.id == transaction_id)
        )
        return result.scalar_one_or_none()

    async def holdings(self, user_id: UUID) -> list[Holding]:
        result = await self.db.execute(
            select(Holding).options(selectinload(Holding.stock)).where(Holding.user_id == user_id).order_by(Holding.created_at)
        )
        return list(result.scalars())

    async def holding_for_update(self, user_id: UUID, stock_id: UUID) -> Holding | None:
        result = await self.db.execute(select(Holding).where(Holding.user_id == user_id, Holding.stock_id == stock_id))
        return result.scalar_one_or_none()

    async def dividends(self, user_id: UUID) -> list[Dividend]:
        result = await self.db.execute(
            select(Dividend).options(selectinload(Dividend.stock)).where(Dividend.user_id == user_id).order_by(Dividend.payment_date.desc())
        )
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
