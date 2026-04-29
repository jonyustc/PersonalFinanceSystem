from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stock import Dividend, PortfolioTransaction, PortfolioTransactionType, Stock
from app.repositories.stock import DividendRepository, HoldingRepository, PortfolioTransactionRepository, StockRepository
from app.schemas.stock import DividendCreate, HoldingResponse, PortfolioSummary, PortfolioTransactionCreate


class PortfolioService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.stocks = StockRepository(db)
        self.transactions = PortfolioTransactionRepository(db)
        self.holdings = HoldingRepository(db)
        self.dividends = DividendRepository(db)

    async def _get_or_create_stock(self, payload) -> Stock:
        stock = await self.stocks.get_by_symbol(payload.symbol)
        if stock:
            stock.name = payload.name
            stock.exchange = payload.exchange
            stock.currency = payload.currency.upper()
            stock.last_price = payload.last_price
            return stock
        data = payload.model_dump()
        data["symbol"] = data["symbol"].upper()
        data["currency"] = data["currency"].upper()
        return await self.stocks.create(data)

    async def trade(self, user_id: UUID, payload: PortfolioTransactionCreate) -> PortfolioTransaction:
        stock = await self._get_or_create_stock(payload.stock)
        holding = await self.holdings.get_by_user_stock(user_id, stock.id)
        if not holding:
            holding = await self.holdings.create({"user_id": user_id, "stock_id": stock.id})
        if payload.txn_type == PortfolioTransactionType.BUY:
            old_cost = holding.quantity * holding.avg_buy_price
            new_cost = payload.quantity * payload.price + payload.fees
            holding.quantity += payload.quantity
            holding.avg_buy_price = (old_cost + new_cost) / holding.quantity
        else:
            if holding.quantity < payload.quantity:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST, detail="Not enough shares to sell")
            proceeds = payload.quantity * payload.price - payload.fees
            cost_basis = payload.quantity * holding.avg_buy_price
            holding.realized_profit_loss += proceeds - cost_basis
            holding.quantity -= payload.quantity
            if holding.quantity == 0:
                holding.avg_buy_price = Decimal("0")
        txn = await self.transactions.create(
            {
                "user_id": user_id,
                "stock_id": stock.id,
                "txn_type": payload.txn_type,
                "quantity": payload.quantity,
                "price": payload.price,
                "fees": payload.fees,
                "txn_date": payload.txn_date,
            }
        )
        await self.db.commit()
        return txn

    async def add_dividend(self, user_id: UUID, payload: DividendCreate) -> Dividend:
        stock = await self.stocks.get(payload.stock_id)
        if not stock:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Stock not found")
        dividend = await self.dividends.create({"user_id": user_id, **payload.model_dump()})
        await self.db.commit()
        return dividend

    async def summary(self, user_id: UUID) -> PortfolioSummary:
        holdings = await self.holdings.list_by_user(user_id)
        rows: list[HoldingResponse] = []
        total_market_value = Decimal("0")
        total_cost_basis = Decimal("0")
        total_unrealized = Decimal("0")
        total_realized = Decimal("0")
        for holding in holdings:
            market_value = holding.quantity * holding.stock.last_price
            cost_basis = holding.quantity * holding.avg_buy_price
            unrealized = market_value - cost_basis
            total_market_value += market_value
            total_cost_basis += cost_basis
            total_unrealized += unrealized
            total_realized += holding.realized_profit_loss
            rows.append(
                HoldingResponse.model_validate(
                    {
                        "id": holding.id,
                        "created_at": holding.created_at,
                        "updated_at": holding.updated_at,
                        "stock": holding.stock,
                        "quantity": holding.quantity,
                        "avg_buy_price": holding.avg_buy_price,
                        "realized_profit_loss": holding.realized_profit_loss,
                        "market_value": market_value,
                        "unrealized_profit_loss": unrealized,
                    }
                )
            )
        return PortfolioSummary(
            total_market_value=total_market_value,
            total_cost_basis=total_cost_basis,
            total_unrealized_profit_loss=total_unrealized,
            total_realized_profit_loss=total_realized,
            holdings=rows,
        )

    async def list_dividends(self, user_id: UUID) -> list[Dividend]:
        return await self.dividends.list_by_user(user_id)
