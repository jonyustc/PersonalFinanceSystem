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
    message: str | None = None


class DseStockSearchResponse(BaseModel):
    symbol: str
    name: str
    last_price: Decimal
    source: str
    fetched_at: str


class DseDividendEstimateResponse(BaseModel):
    symbol: str
    found: bool
    source: str | None = None
    record_date: date | None = None
    payment_date: date | None = None
    year: int | None = None
    cash_dividend_percent: Decimal | None = None
    dividend_per_share: Decimal | None = None
    eligible_quantity: Decimal = Decimal("0")
    gross_amount: Decimal = Decimal("0")
    tax_rate_percent: Decimal = Decimal("10")
    tax_amount: Decimal = Decimal("0")
    net_amount: Decimal = Decimal("0")
    message: str | None = None


class PortfolioTransactionCreate(BaseModel):
    portfolio_id: UUID | None = None
    stock_id: UUID | None = None
    stock: StockCreate | None = None
    broker_account_id: UUID | None = None
    txn_type: PortfolioTxnType
    quantity: Decimal = Field(default=Decimal("0"), ge=0)
    price: Decimal = Field(default=Decimal("0"), ge=0)
    fees: Decimal | None = Field(default=None, ge=0)
    txn_date: date = Field(default_factory=date.today)
    payment_date: date | None = None
    record_date: date | None = None
    notes: str | None = Field(default=None, max_length=255)

    @model_validator(mode="before")
    @classmethod
    def normalize_payment_date(cls, data):
        if (
            isinstance(data, dict)
            and data.get("payment_date") is not None
            and data.get("txn_date") is None
        ):
            return {**data, "txn_date": data["payment_date"]}
        return data

    @model_validator(mode="after")
    def validate_transaction_shape(self) -> "PortfolioTransactionCreate":
        if self.txn_type == "income":
            self.payment_date = self.payment_date or self.txn_date
            self.txn_date = self.payment_date
        elif self.payment_date is None:
            self.payment_date = self.txn_date
        if self.txn_type in {"buy", "sell", "income"} and not (
            self.stock_id or self.stock
        ):
            raise ValueError("Stock is required for buy, sell, and income transactions")
        if self.txn_type in {"buy", "sell"} and (self.quantity <= 0 or self.price <= 0):
            raise ValueError(
                "Quantity and price are required for buy and sell transactions"
            )
        if self.txn_type == "income" and self.price <= 0:
            raise ValueError("Income amount is required")
        if self.txn_type in {"deposit", "withdraw"} and self.price <= 0:
            raise ValueError("Amount is required for deposit and withdraw")
        return self


class PortfolioTransactionResponse(BaseModel):
    id: UUID
    portfolio_id: UUID | None = None
    stock_id: UUID | None
    broker_account_id: UUID | None
    txn_type: str
    quantity: Decimal
    price: Decimal
    fees: Decimal
    total_amount: Decimal
    cash_flow: Decimal
    txn_date: date
    payment_date: date | None = None
    record_date: date | None = None
    notes: str | None = None
    stock: StockResponse | None = None

    class Config:
        from_attributes = True


class DividendCreate(BaseModel):
    stock_id: UUID
    amount: Decimal = Field(gt=0)
    payment_date: date = Field(default_factory=date.today)
    record_date: date | None = None
    notes: str | None = Field(default=None, max_length=255)
    broker_account_id: UUID | None = None
    portfolio_id: UUID | None = None


class DividendResponse(BaseModel):
    id: UUID
    stock_id: UUID
    amount: Decimal
    payment_date: date
    record_date: date | None = None
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
    # --- Cost-basis architecture + advanced investor analytics (additive) ---
    broker_cost_basis: Decimal = Decimal("0")
    market_price: Decimal = Decimal("0")
    effective_cost_basis: Decimal = Decimal("0")
    net_capital_invested: Decimal = Decimal("0")
    capital_recovery_percent: Decimal = Decimal("0")
    wealth_multiple: Decimal = Decimal("0")
    total_return: Decimal = Decimal("0")
    portfolio_id: UUID | None = None


class DividendReportRow(BaseModel):
    stock_id: UUID
    stock_name: str
    year: int
    dividend_gain: Decimal
    record_date: date | None = None
    payment_date: date | None = None
    cash_dividend_percent: Decimal | None = None
    eligible_quantity: Decimal | None = None
    source: str = "manual"


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
    cagr_percent: Decimal
    broker_accounts: list[BrokerAccountSummary]
    holdings: list[HoldingResponse]
    dividend_report: list[DividendReportRow]
    auto_dividend_report: list[DividendReportRow] = Field(default_factory=list)
    # --- Portfolio Dashboard (default view) per spec; additive fields ---
    portfolio_id: UUID | None = None
    portfolio_name: str | None = None
    total_investment: Decimal = Decimal("0")  # Σ(buy qty × buy price + charges)
    total_dividend_income: Decimal = Decimal("0")
    total_unrealized_gain: Decimal = Decimal("0")
    total_return: Decimal = Decimal("0")  # realized + dividend + unrealized
    roi_percent: Decimal = Decimal("0")
    # --- Advanced Investor Analytics (revealed behind a toggle) ---
    net_capital_invested: Decimal = Decimal("0")
    capital_recovery_percent: Decimal = Decimal("0")
    wealth_multiple: Decimal = Decimal("0")
    total_withdrawals: Decimal = Decimal("0")


class PortfolioCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    kind: Literal["long_term_sip", "mid_term_trading", "general"] = "general"
    description: str | None = Field(default=None, max_length=255)


class PortfolioUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    kind: Literal["long_term_sip", "mid_term_trading", "general"] | None = None
    description: str | None = Field(default=None, max_length=255)


class PortfolioResponse(BaseModel):
    id: UUID
    name: str
    kind: str
    description: str | None = None
    is_default: bool
    broker_account_id: UUID | None = None

    class Config:
        from_attributes = True


class AnnualPerformanceRow(BaseModel):
    year: int
    beginning_value: Decimal
    new_investment: Decimal
    realized_gain: Decimal
    dividend_income: Decimal
    unrealized_gain: Decimal
    ending_value: Decimal
    total_return: Decimal
    annual_return_percent: Decimal


class AnnualPerformanceResponse(BaseModel):
    portfolio_id: UUID | None = None
    rows: list[AnnualPerformanceRow] = Field(default_factory=list)


class PerformanceSeriesPoint(BaseModel):
    period: str  # YYYY-MM
    portfolio_value: Decimal
    cumulative_return: Decimal


class ReturnCompositionRow(BaseModel):
    label: str  # Realized Gain | Unrealized Gain | Dividend Income
    value: Decimal


class AnnualReturnPoint(BaseModel):
    year: int
    annual_return_percent: Decimal


class PerformanceSeriesResponse(BaseModel):
    portfolio_id: UUID | None = None
    growth: list[PerformanceSeriesPoint] = Field(default_factory=list)
    return_composition: list[ReturnCompositionRow] = Field(default_factory=list)
    annual_return: list[AnnualReturnPoint] = Field(default_factory=list)


class StockXirrRow(BaseModel):
    stock_id: UUID
    symbol: str
    name: str
    xirr_percent: Decimal | None = None


class TradeStat(BaseModel):
    symbol: str
    name: str
    profit: Decimal
    return_percent: Decimal | None = None


class PortfolioAnalyticsResponse(BaseModel):
    portfolio_id: UUID | None = None
    # Money-weighted & time-weighted returns
    portfolio_xirr_percent: Decimal | None = None
    cagr_percent: Decimal = Decimal("0")
    stock_xirr: list[StockXirrRow] = Field(default_factory=list)
    # Trade statistics (realized, completed sells)
    win_rate_percent: Decimal = Decimal("0")
    profit_factor: Decimal | None = None
    average_gain_percent: Decimal = Decimal("0")
    average_loss_percent: Decimal = Decimal("0")
    best_trade: TradeStat | None = None
    worst_trade: TradeStat | None = None
    average_holding_period_days: Decimal = Decimal("0")
    portfolio_turnover_ratio: Decimal = Decimal("0")
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
