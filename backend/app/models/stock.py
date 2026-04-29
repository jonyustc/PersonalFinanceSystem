import enum
from datetime import date
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import TimestampMixin, UUIDMixin


class PortfolioTransactionType(str, enum.Enum):
    BUY = "buy"
    SELL = "sell"


class Stock(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "stocks"

    symbol: Mapped[str] = mapped_column(
        String(20), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    exchange: Mapped[Optional[str]] = mapped_column(String(80))
    currency: Mapped[str] = mapped_column(
        String(3), default="USD", nullable=False)
    last_price: Mapped[Decimal] = mapped_column(
        Numeric(14, 4), default=0, nullable=False)

    holdings = relationship("Holding", back_populates="stock")


class PortfolioTransaction(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "portfolio_transactions"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    stock_id: Mapped[UUID] = mapped_column(UUID(as_uuid=True), ForeignKey(
        "stocks.id", ondelete="RESTRICT"), index=True)
    txn_type: Mapped[PortfolioTransactionType] = mapped_column(
        String(20), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(14, 4), nullable=False)
    fees: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=0, nullable=False)
    txn_date: Mapped[date] = mapped_column(Date, nullable=False)

    stock = relationship("Stock")


class Holding(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "holdings"
    __table_args__ = (UniqueConstraint(
        "user_id", "stock_id", name="uq_user_stock_holding"),)

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    stock_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("stocks.id", ondelete="CASCADE"), index=True)
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(18, 6), default=0, nullable=False)
    avg_buy_price: Mapped[Decimal] = mapped_column(
        Numeric(14, 4), default=0, nullable=False)
    realized_profit_loss: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=0, nullable=False)

    user = relationship("User", back_populates="holdings")
    stock = relationship("Stock", back_populates="holdings")


class Dividend(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "dividends"

    user_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    stock_id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("stocks.id", ondelete="CASCADE"), index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    payment_date: Mapped[date] = mapped_column(Date, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(String(255))

    stock = relationship("Stock")
