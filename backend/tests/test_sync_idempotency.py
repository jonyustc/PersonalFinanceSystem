"""Idempotent client-UUID creates for offline-sync replay.

A transaction created offline carries a client-generated UUID. When the mobile
app replays that create on sync, the server must return the stored row instead
of inserting a duplicate and re-applying the balance.
"""
from decimal import Decimal
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.schemas.budget import BudgetCreate
from app.schemas.transaction import TransactionCreate
from app.services.budget import BudgetService
from app.services.transaction import TransactionService


class _FakeDb:
    def __init__(self, existing):
        self._existing = existing
        self.committed = False
        self.added = []

    async def get(self, model, obj_id):
        # Mimics AsyncSession.get: returns the stored row for this id, if any.
        if self._existing is not None and obj_id == self._existing.id:
            return self._existing
        return None

    def add(self, obj):
        self.added.append(obj)

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def _payload(txn_id, account_id):
    return TransactionCreate(
        id=txn_id,
        account_id=account_id,
        type="expense",
        amount=Decimal("10"),
    )


@pytest.mark.asyncio
async def test_create_with_existing_id_returns_stored_row_without_reapplying():
    user_id = uuid4()
    txn_id = uuid4()
    existing = SimpleNamespace(id=txn_id, user_id=user_id, amount=Decimal("10"))
    db = _FakeDb(existing)
    service = TransactionService(db)

    result = await service.create(user_id, _payload(txn_id, uuid4()))

    assert result is existing
    # No insert, no balance mutation, no commit: the replay was a no-op.
    assert db.added == []
    assert db.committed is False


@pytest.mark.asyncio
async def test_create_with_id_owned_by_another_user_is_rejected():
    txn_id = uuid4()
    existing = SimpleNamespace(id=txn_id, user_id=uuid4(), amount=Decimal("10"))
    db = _FakeDb(existing)
    service = TransactionService(db)

    with pytest.raises(HTTPException) as exc:
        await service.create(uuid4(), _payload(txn_id, uuid4()))
    assert exc.value.status_code == 409


class _FakeBudgetDb:
    """Fake session for BudgetService.upsert_budget: `scalar` returns the row
    matched by (user, category, month); `get` returns the row matched by id."""

    def __init__(self, by_key=None, by_id=None):
        self._by_key = by_key
        self._by_id = by_id
        self.added = []
        self.committed = False

    async def scalar(self, stmt):
        return self._by_key

    async def get(self, model, obj_id):
        if self._by_id is not None and obj_id == self._by_id.id:
            return self._by_id
        return None

    def add(self, obj):
        self.added.append(obj)

    async def commit(self):
        self.committed = True

    async def refresh(self, obj):
        pass

    async def rollback(self):
        pass


def _budget_payload(budget_id):
    return BudgetCreate(
        id=budget_id,
        category_id=uuid4(),
        amount=Decimal("100"),
        month="2026-07",
    )


@pytest.mark.asyncio
async def test_budget_upsert_uses_client_id_on_create():
    budget_id = uuid4()
    db = _FakeBudgetDb()
    service = BudgetService(db)

    result = await service.upsert_budget(uuid4(), _budget_payload(budget_id))

    # The new row keeps the client id so the mobile mirror doesn't duplicate it.
    assert result.id == budget_id
    assert db.added and db.added[0].id == budget_id


@pytest.mark.asyncio
async def test_budget_upsert_updates_existing_and_ignores_client_id():
    existing = SimpleNamespace(id=uuid4(), amount=Decimal("50"))
    db = _FakeBudgetDb(by_key=existing)
    service = BudgetService(db)

    result = await service.upsert_budget(uuid4(), _budget_payload(uuid4()))

    # A replayed/edited budget updates the amount in place; no insert.
    assert result is existing
    assert existing.amount == Decimal("100")
    assert db.added == []


@pytest.mark.asyncio
async def test_budget_upsert_rejects_id_owned_by_another_user():
    budget_id = uuid4()
    other = SimpleNamespace(id=budget_id, user_id=uuid4())
    db = _FakeBudgetDb(by_id=other)
    service = BudgetService(db)

    with pytest.raises(HTTPException) as exc:
        await service.upsert_budget(uuid4(), _budget_payload(budget_id))
    assert exc.value.status_code == 409
