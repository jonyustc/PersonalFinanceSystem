from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.core.config import settings
from app.services.auth import AuthService


def _fake_user(email: str):
    now = datetime.now(UTC)
    return SimpleNamespace(
        id=uuid4(),
        full_name="Existing User",
        email=email,
        currency="BDT",
        is_active=True,
        created_at=now,
        updated_at=now,
    )


class _FakeDb:
    def __init__(self):
        self.commits = 0

    async def commit(self):
        self.commits += 1


class _FakeUserRepo:
    def __init__(self, existing):
        self._existing = existing
        self.created = []

    async def get_by_email(self, email):
        if self._existing is not None and self._existing.email == email.lower():
            return self._existing
        return None

    async def create(self, data):
        user = _fake_user(data["email"])
        user.full_name = data["full_name"]
        self.created.append(data)
        return user


def _service(existing):
    service = AuthService(_FakeDb())
    service.users = _FakeUserRepo(existing)
    return service


@pytest.fixture(autouse=True)
def _configure_google(monkeypatch):
    monkeypatch.setattr(settings, "GOOGLE_CLIENT_IDS", "test-client-id")

    async def fake_verify(token, allowed_client_ids):
        assert allowed_client_ids == ["test-client-id"]
        return {"email": token, "name": "Google Name", "email_verified": True}

    monkeypatch.setattr("app.services.auth.verify_google_id_token", fake_verify)


@pytest.mark.asyncio
async def test_google_login_reuses_existing_user_by_email():
    existing = _fake_user("user@example.com")
    service = _service(existing)

    result = await service.login_with_google("USER@example.com")

    assert result.user.email == "user@example.com"
    assert result.user.id == existing.id
    assert service.users.created == []  # no duplicate user created
    assert result.access_token and result.refresh_token


@pytest.mark.asyncio
async def test_google_login_creates_user_when_email_unknown():
    service = _service(existing=None)

    result = await service.login_with_google("new@example.com")

    assert result.user.email == "new@example.com"
    assert len(service.users.created) == 1
    assert service.users.created[0]["full_name"] == "Google Name"
    assert service.db.commits == 1
