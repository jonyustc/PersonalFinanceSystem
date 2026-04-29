from datetime import date
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.stock import PortfolioTransactionType
from app.schemas.common import Timestamped


class StockCreate(BaseModel):
    symbol: str = Field(min_length=1, max_length=20)
    name: str = Field(min_length=1, max_length=255)
    exchange: str | None = None
    currency: str = Field(default="USD", min_length=3, max_length=3)
    last_price: Decimal = Field(default=Decimal("0"), ge=0)


class StockResponse(Timestamped):
    symbol: str
    name: str
    exchange: str | None
    currency: str
    last_price: Decimal


class PortfolioTransactionCreate(BaseModel):
    stock: StockCreate
    txn_type: PortfolioTransactionType
    quantity: Decimal = Field(gt=0, max_digits=18, decimal_places=6)
    price: Decimal = Field(gt=0, max_digits=14, decimal_places=4)
    fees: Decimal = Field(default=Decimal("0"), ge=0)
    txn_date: date


class PortfolioTransactionResponse(Timestamped):
    stock_id: UUID
    txn_type: PortfolioTransactionType
    quantity: Decimal
    price: Decimal
    fees: Decimal
    txn_date: date


class DividendCreate(BaseModel):
    stock_id: UUID
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)
    payment_date: date
    notes: str | None = None


class DividendResponse(Timestamped):
    stock_id: UUID
    amount: Decimal
    payment_date: date
    notes: str | None


class HoldingResponse(Timestamped):
    stock: StockResponse
    quantity: Decimal
    avg_buy_price: Decimal
    realized_profit_loss: Decimal
    market_value: Decimal
    unrealized_profit_loss: Decimal


class PortfolioSummary(BaseModel):
    total_market_value: Decimal
    total_cost_basis: Decimal
    total_unrealized_profit_loss: Decimal
    total_realized_profit_loss: Decimal
    holdings: list[HoldingResponse]
