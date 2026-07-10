from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.transaction import TransactionCreate, TransactionUpdate


def _base_payload(**overrides):
    payload = {
        "account_id": uuid4(),
        "type": "expense",
        "amount": Decimal("100"),
    }
    payload.update(overrides)
    return payload


def test_create_with_debt_type_and_counterparty():
    trx = TransactionCreate(**_base_payload(counterparty_name="Rahim", debt_type="lent"))
    assert trx.counterparty_name == "Rahim"
    assert trx.debt_type == "lent"


def test_create_counterparty_alone_is_allowed():
    trx = TransactionCreate(**_base_payload(counterparty_name="Rahim"))
    assert trx.counterparty_name == "Rahim"
    assert trx.debt_type is None


def test_create_debt_type_without_counterparty_rejected():
    with pytest.raises(ValidationError):
        TransactionCreate(**_base_payload(debt_type="borrowed"))


def test_create_debt_type_with_blank_counterparty_rejected():
    with pytest.raises(ValidationError):
        TransactionCreate(**_base_payload(counterparty_name="   ", debt_type="borrowed"))


def test_create_invalid_debt_type_rejected():
    with pytest.raises(ValidationError):
        TransactionCreate(**_base_payload(counterparty_name="Rahim", debt_type="gifted"))


def test_counterparty_whitespace_normalized():
    trx = TransactionCreate(**_base_payload(counterparty_name="  Rahim   Uddin  "))
    assert trx.counterparty_name == "Rahim Uddin"


def test_update_debt_type_requires_counterparty():
    with pytest.raises(ValidationError):
        TransactionUpdate(debt_type="repaid_by_them")


def test_update_debt_type_with_counterparty_ok():
    upd = TransactionUpdate(counterparty_name="Karim", debt_type="repaid_to_them")
    assert upd.counterparty_name == "Karim"
    assert upd.debt_type == "repaid_to_them"
