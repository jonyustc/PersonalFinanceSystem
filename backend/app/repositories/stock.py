from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.models.stock import Dividend, Holding, PortfolioTransaction, Stock
from app.repositories.base import BaseRepository


class StockRepository(BaseRepository[Stock]):
    model = Stock

    async def get_by_symbol(self, symbol: str) -> Stock | None:
        result = await self.db.execute(select(Stock).where(Stock.symbol == symbol.upper()))
        return result.scalar_one_or_none()


class PortfolioTransactionRepository(BaseRepository[PortfolioTransaction]):
    model = PortfolioTransaction


class HoldingRepository(BaseRepository[Holding]):
    model = Holding

    async def get_by_user_stock(self, user_id: UUID, stock_id: UUID) -> Holding | None:
        result = await self.db.execute(select(Holding).where(Holding.user_id == user_id, Holding.stock_id == stock_id))
        return result.scalar_one_or_none()

    async def list_by_user(self, user_id: UUID) -> list[Holding]:
        result = await self.db.execute(
            select(Holding).where(Holding.user_id == user_id).options(selectinload(Holding.stock)).order_by(Holding.created_at)
        )
        return list(result.scalars())


class DividendRepository(BaseRepository[Dividend]):
    model = Dividend

    async def list_by_user(self, user_id: UUID) -> list[Dividend]:
        result = await self.db.execute(select(Dividend).where(Dividend.user_id == user_id).order_by(Dividend.payment_date.desc()))
        return list(result.scalars())
