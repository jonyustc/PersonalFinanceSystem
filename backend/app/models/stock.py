from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Date, ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base
from app.models.base import TimestampMixin, UUIDMixin


class Stock(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "stocks"

    symbol: Mapped[str] = mapped_column(String(20), nullable=False, unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    exchange: Mapped[str | None] = mapped_column(String(80), nullable=True)
    currency: Mapped[str] = mapped_column(String(3), default="BDT", nullable=False)
    last_price: Mapped[Decimal] = mapped_column(Numeric(14, 4), default=0, nullable=False)

    transactions: Mapped[list["PortfolioTransaction"]] = relationship("PortfolioTransaction", back_populates="stock")
    holdings: Mapped[list["Holding"]] = relationship("Holding", back_populates="stock")
    dividends: Mapped[list["Dividend"]] = relationship("Dividend", back_populates="stock")


class PortfolioTransaction(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "portfolio_transactions"

    user_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    stock_id: Mapped[UUID | None] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("stocks.id", ondelete="RESTRICT"), nullable=True, index=True)
    broker_account_id: Mapped[UUID | None] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True, index=True)
    txn_type: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), default=0, nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(14, 4), default=0, nullable=False)
    fees: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    txn_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    notes: Mapped[str | None] = mapped_column(String(255), nullable=True)

    stock: Mapped[Stock | None] = relationship("Stock", back_populates="transactions")
    broker_account: Mapped["Account | None"] = relationship("Account")


class Holding(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "holdings"
    __table_args__ = (UniqueConstraint("user_id", "stock_id", name="uq_user_stock_holding"),)

    user_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    stock_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("stocks.id", ondelete="CASCADE"), nullable=False, index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), default=0, nullable=False)
    avg_buy_price: Mapped[Decimal] = mapped_column(Numeric(14, 4), default=0, nullable=False)
    realized_profit_loss: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)

    stock: Mapped[Stock] = relationship("Stock", back_populates="holdings")


class Dividend(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "dividends"

    user_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    stock_id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), ForeignKey("stocks.id", ondelete="CASCADE"), nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    payment_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    notes: Mapped[str | None] = mapped_column(String(255), nullable=True)

    stock: Mapped[Stock] = relationship("Stock", back_populates="dividends")
