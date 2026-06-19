from datetime import date
from decimal import Decimal
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.services.portfolio import PortfolioService
from app.schemas.stock import PortfolioTransactionCreate


class _FakeDb:
    def __init__(self):
        self.commits = 0
        self.rollbacks = 0

    async def commit(self):
        self.commits += 1

    async def rollback(self):
        self.rollbacks += 1


class _FakeRepo:
    def __init__(self, *, transactions, holdings, dividends, broker_accounts):
        self._transactions = transactions
        self._holdings = holdings
        self._dividends = dividends
        self._broker_accounts = broker_accounts

    async def transactions(self, user_id, limit=100, portfolio_id=None):
        return self._transactions

    async def holdings(self, user_id, portfolio_id=None):
        return self._holdings

    async def dividends(self, user_id, portfolio_id=None):
        return self._dividends

    async def broker_accounts(self, user_id):
        return self._broker_accounts


@pytest.mark.asyncio
async def test_summary_uses_derived_cash_and_lists_broker_accounts():
    user_id = uuid4()
    stock_id = uuid4()
    account_id = uuid4()
    stock = SimpleNamespace(
        id=stock_id,
        symbol="LBSL",
        name="LBSL",
        exchange="DSE",
        currency="BDT",
        last_price=Decimal("0"),
    )
    service = PortfolioService(_FakeDb())
    service.repo = _FakeRepo(
        transactions=[],
        holdings=[
            SimpleNamespace(
                portfolio_id=None,
                stock_id=stock_id,
                stock=stock,
                quantity=Decimal("100"),
                avg_buy_price=Decimal("50"),
                realized_profit_loss=Decimal("0"),
            )
        ],
        dividends=[],
        broker_accounts=[
            SimpleNamespace(
                id=account_id,
                name="LBSL",
                balance=Decimal("175865"),
                currency="BDT",
            )
        ],
    )

    summary = await service.summary(user_id)

    assert summary["active_cost_basis"] == Decimal("5000")
    assert summary["current_equity_value"] == Decimal("5000")
    # Cash is derived from portfolio activity (no txns here => 0), not the broker
    # account balance, which would double-count separately tracked capital.
    assert summary["cash_balance"] == Decimal("0")
    assert summary["total_portfolio_value"] == Decimal("5000")
    assert summary["holdings"][0]["stock"] == stock
    # Broker accounts are still surfaced for reference.
    assert summary["broker_accounts"][0]["balance"] == Decimal("175865")


@pytest.mark.asyncio
async def test_summary_falls_back_to_existing_holdings_when_rebuild_fails():
    user_id = uuid4()
    stock_id = uuid4()
    db = _FakeDb()
    stock = SimpleNamespace(
        id=stock_id,
        symbol="LBSL",
        name="LBSL",
        exchange="DSE",
        currency="BDT",
        last_price=Decimal("75"),
    )
    service = PortfolioService(db)
    service.repo = _FakeRepo(
        transactions=[
            SimpleNamespace(
                portfolio_id=None,
                stock_id=stock_id,
                txn_type="sell",
                quantity=Decimal("10"),
                price=Decimal("75"),
                fees=Decimal("0"),
                txn_date=None,
            )
        ],
        holdings=[
            SimpleNamespace(
                portfolio_id=None,
                stock_id=stock_id,
                stock=stock,
                quantity=Decimal("100"),
                avg_buy_price=Decimal("50"),
                realized_profit_loss=Decimal("0"),
            )
        ],
        dividends=[],
        broker_accounts=[],
    )

    async def fail_rebuild(_user_id):
        raise HTTPException(400, "Sell quantity exceeds holding")

    service._rebuild_derived = fail_rebuild

    summary = await service.summary(user_id)

    assert db.rollbacks == 1
    assert summary["current_equity_value"] == Decimal("7500")
    assert summary["active_cost_basis"] == Decimal("5000")
    assert summary["holdings"][0]["quantity"] == Decimal("100")


def test_portfolio_income_accepts_payment_date_alias():
    stock_id = uuid4()

    payload = PortfolioTransactionCreate(
        stock_id=stock_id,
        txn_type="income",
        quantity=Decimal("1"),
        price=Decimal("125"),
        payment_date=date(2026, 6, 11),
        record_date=date(2026, 5, 20),
    )

    assert payload.txn_date == date(2026, 6, 11)
    assert payload.payment_date == date(2026, 6, 11)
    assert payload.record_date == date(2026, 5, 20)


def _txn(portfolio_id, stock_id, txn_type, qty, price, txn_date=date(2026, 1, 1)):
    return SimpleNamespace(
        portfolio_id=portfolio_id,
        stock_id=stock_id,
        txn_type=txn_type,
        quantity=Decimal(qty),
        price=Decimal(price),
        fees=Decimal("0"),
        txn_date=txn_date,
    )


def test_core_valuation_matches_spec_broker_and_effective_cost_basis():
    """Spec example: buy 1000@200, sell 500@235, buy 500@205, +10,000 dividend."""
    portfolio_id = uuid4()
    stock_id = uuid4()
    stock = SimpleNamespace(
        id=stock_id, symbol="DEMO", name="Demo", last_price=Decimal("0")
    )
    service = PortfolioService(_FakeDb())
    transactions = [
        _txn(portfolio_id, stock_id, "buy", "1000", "200"),
        _txn(portfolio_id, stock_id, "sell", "500", "235"),
        _txn(portfolio_id, stock_id, "buy", "500", "205"),
    ]
    holdings = [
        SimpleNamespace(
            portfolio_id=portfolio_id,
            stock_id=stock_id,
            stock=stock,
            quantity=Decimal("1000"),
            avg_buy_price=Decimal("202.5"),
            realized_profit_loss=Decimal("17500"),
        )
    ]
    dividends = [
        SimpleNamespace(
            portfolio_id=portfolio_id,
            stock_id=stock_id,
            amount=Decimal("10000"),
            payment_date=date(2026, 3, 1),
            record_date=None,
        )
    ]

    core = service._core_valuation(holdings, dividends, transactions)
    row = core["holding_rows"][0]

    assert row["broker_cost_basis"] == Decimal("202.5")
    assert row["effective_cost_basis"] == Decimal("175")
    assert core["realized_total"] == Decimal("17500")
    assert core["total_buy_investment"] == Decimal("302500")  # 200000 + 102500
    assert core["total_investment"] == Decimal("0")  # no deposits => deposit-based base
    assert core["dividend_income_manual"] == Decimal("10000")


@pytest.mark.asyncio
async def test_total_investment_uses_deposited_cash_and_roi():
    user_id = uuid4()
    stock_id = uuid4()
    stock = SimpleNamespace(
        id=stock_id, symbol="LBSL", name="LBSL", exchange="DSE", currency="BDT",
        last_price=Decimal("75"),
    )
    service = PortfolioService(_FakeDb())
    service.repo = _FakeRepo(
        transactions=[
            SimpleNamespace(
                portfolio_id=None, stock_id=None, txn_type="deposit",
                quantity=Decimal("0"), price=Decimal("175700"), fees=Decimal("0"),
                txn_date=date(2026, 1, 1),
            )
        ],
        holdings=[
            SimpleNamespace(
                portfolio_id=None, stock_id=stock_id, stock=stock,
                quantity=Decimal("100"), avg_buy_price=Decimal("50"),
                realized_profit_loss=Decimal("0"),
            )
        ],
        dividends=[],
        broker_accounts=[],
    )

    summary = await service.summary(user_id)

    # Total Investment = deposited cash, not cumulative buys.
    assert summary["total_investment"] == Decimal("175700")
    # Total Return = unrealized (7500 - 5000) = 2500; ROI = 2500 / 175700.
    assert summary["total_return"] == Decimal("2500")
    assert abs(float(summary["roi_percent"]) - 1.4229) < 0.01


def test_xirr_simple_one_year_double_flow():
    service = PortfolioService(_FakeDb())
    rate = service._xirr(
        [(date(2025, 1, 1), Decimal("-1000")), (date(2026, 1, 1), Decimal("1100"))]
    )
    assert rate is not None
    assert abs(rate - Decimal("10")) < Decimal("0.5")


def test_xirr_requires_sign_change():
    service = PortfolioService(_FakeDb())
    assert (
        service._xirr(
            [(date(2025, 1, 1), Decimal("-1000")), (date(2026, 1, 1), Decimal("-500"))]
        )
        is None
    )


@pytest.mark.asyncio
async def test_summary_includes_manual_dividend_record_and_payment_dates():
    user_id = uuid4()
    stock_id = uuid4()
    stock = SimpleNamespace(
        id=stock_id,
        symbol="LBSL",
        name="LBSL",
        exchange="DSE",
        currency="BDT",
        last_price=Decimal("0"),
    )
    service = PortfolioService(_FakeDb())
    service.repo = _FakeRepo(
        transactions=[],
        holdings=[],
        dividends=[
            SimpleNamespace(
                portfolio_id=None,
                stock_id=stock_id,
                stock=stock,
                amount=Decimal("125"),
                payment_date=date(2026, 6, 11),
                record_date=date(2026, 5, 20),
            )
        ],
        broker_accounts=[],
    )

    summary = await service.summary(user_id)

    row = summary["dividend_report"][0]
    assert row["dividend_gain"] == Decimal("125")
    assert row["record_date"] == date(2026, 5, 20)
    assert row["payment_date"] == date(2026, 6, 11)
