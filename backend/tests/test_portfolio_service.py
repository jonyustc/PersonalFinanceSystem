from decimal import Decimal
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.services.portfolio import PortfolioService


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

    async def transactions(self, user_id, limit=100):
        return self._transactions

    async def holdings(self, user_id):
        return self._holdings

    async def dividends(self, user_id):
        return self._dividends

    async def broker_accounts(self, user_id):
        return self._broker_accounts


@pytest.mark.asyncio
async def test_summary_uses_existing_holdings_and_broker_cash_without_trade_rows():
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
    assert summary["cash_balance"] == Decimal("175865")
    assert summary["total_portfolio_value"] == Decimal("180865")
    assert summary["holdings"][0]["stock"] == stock


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
