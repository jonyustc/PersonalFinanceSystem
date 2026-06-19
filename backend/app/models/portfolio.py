from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Boolean, Date, ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.base import TimestampMixin, UUIDMixin


# Portfolio kinds drive the SIP vs Trading separation from the spec.
PORTFOLIO_KINDS = ("long_term_sip", "mid_term_trading", "general")


class Portfolio(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "portfolios"
    __table_args__ = (
        UniqueConstraint("user_id", "name", name="uq_portfolio_user_name"),
    )

    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    kind: Mapped[str] = mapped_column(String(30), default="general", nullable=False)
    description: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # When set, this portfolio mirrors a broker account (broker account = portfolio).
    broker_account_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("accounts.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )


class PortfolioValueSnapshot(UUIDMixin, TimestampMixin, Base):
    """Daily point-in-time valuation, captured lazily when a summary is read.

    One row per (user, portfolio, date). Account-wide series are produced by
    summing same-date rows across the user's portfolios.
    """

    __tablename__ = "portfolio_value_snapshots"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "portfolio_id",
            "snapshot_date",
            name="uq_portfolio_snapshot_day",
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    portfolio_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("portfolios.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    snapshot_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    equity_value: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    cash_balance: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    total_value: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    invested_capital: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    realized_gain: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    unrealized_gain: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    dividend_income: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    total_return: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
