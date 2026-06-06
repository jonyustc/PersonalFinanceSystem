from datetime import date
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


PortfolioTxnType = Literal["buy", "sell", "deposit", "withdraw", "income"]


class StockCreate(BaseModel):
    symbol: str = Field(min_length=1, max_length=20)
    name: str = Field(min_length=1, max_length=255)
    exchange: str | None = Field(default=None, max_length=80)
    currency: str = Field(default="BDT", min_length=3, max_length=3)
    last_price: Decimal = Field(default=Decimal("0"), ge=0)


class StockUpdate(BaseModel):
    symbol: str | None = Field(default=None, min_length=1, max_length=20)
    name: str | None = Field(default=None, min_length=1, max_length=255)
    exchange: str | None = Field(default=None, max_length=80)
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    last_price: Decimal | None = Field(default=None, ge=0)


class StockResponse(StockCreate):
    id: UUID

    class Config:
        from_attributes = True


class StockPriceRefreshResponse(BaseModel):
    updated: int
    source: str
    fetched_at: str
    missing_symbols: list[str] = Field(default_factory=list)
    stocks: list[StockResponse] = Field(default_factory=list)


class DseStockSearchResponse(BaseModel):
    symbol: str
    name: str
    last_price: Decimal
    source: str
    fetched_at: str


class PortfolioTransactionCreate(BaseModel):
    stock_id: UUID | None = None
    stock: StockCreate | None = None
    broker_account_id: UUID | None = None
    txn_type: PortfolioTxnType
    quantity: Decimal = Field(default=Decimal("0"), ge=0)
    price: Decimal = Field(default=Decimal("0"), ge=0)
    fees: Decimal | None = Field(default=None, ge=0)
    txn_date: date = Field(default_factory=date.today)
    notes: str | None = Field(default=None, max_length=255)

    @model_validator(mode="after")
    def validate_transaction_shape(self) -> "PortfolioTransactionCreate":
        if self.txn_type in {"buy", "sell", "income"} and not (self.stock_id or self.stock):
            raise ValueError("Stock is required for buy, sell, and income transactions")
        if self.txn_type in {"buy", "sell"} and (self.quantity <= 0 or self.price <= 0):
            raise ValueError("Quantity and price are required for buy and sell transactions")
        if self.txn_type == "income" and self.price <= 0:
            raise ValueError("Income amount is required")
        if self.txn_type in {"deposit", "withdraw"} and self.price <= 0:
            raise ValueError("Amount is required for deposit and withdraw")
        return self


class PortfolioTransactionResponse(BaseModel):
    id: UUID
    stock_id: UUID | None
    broker_account_id: UUID | None
    txn_type: str
    quantity: Decimal
    price: Decimal
    fees: Decimal
    total_amount: Decimal
    cash_flow: Decimal
    txn_date: date
    notes: str | None = None
    stock: StockResponse | None = None

    class Config:
        from_attributes = True


class DividendCreate(BaseModel):
    stock_id: UUID
    amount: Decimal = Field(gt=0)
    payment_date: date = Field(default_factory=date.today)
    notes: str | None = Field(default=None, max_length=255)
    broker_account_id: UUID | None = None


class DividendResponse(BaseModel):
    id: UUID
    stock_id: UUID
    amount: Decimal
    payment_date: date
    notes: str | None = None
    stock: StockResponse | None = None

    class Config:
        from_attributes = True


class HoldingResponse(BaseModel):
    stock: StockResponse
    quantity: Decimal
    avg_buy_price: Decimal
    invested_amount: Decimal
    market_value: Decimal
    unrealized_profit_loss: Decimal
    unrealized_percent: Decimal
    realized_profit_loss: Decimal
    dividend_income: Decimal
    total_profit_loss: Decimal


class DividendReportRow(BaseModel):
    stock_id: UUID
    stock_name: str
    year: int
    dividend_gain: Decimal


class BrokerAccountSummary(BaseModel):
    id: UUID
    name: str
    balance: Decimal
    currency: str


class PortfolioSummaryResponse(BaseModel):
    total_principal_investment: Decimal
    invested_capital: Decimal
    active_cost_basis: Decimal
    current_equity_value: Decimal
    unrealized_gain_loss: Decimal
    cash_balance: Decimal
    total_portfolio_value: Decimal
    total_realized_capital_gain_loss: Decimal
    dividend_income: Decimal
    total_realized_profit: Decimal
    overall_profit_loss: Decimal
    return_percent: Decimal
    broker_accounts: list[BrokerAccountSummary]
    holdings: list[HoldingResponse]
    dividend_report: list[DividendReportRow]
