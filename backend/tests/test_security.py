from uuid import uuid4

from app.core.security import create_access_token, decode_token, get_password_hash, verify_password


def test_password_hash_roundtrip():
    hashed = get_password_hash("correct-horse-battery")
    assert verify_password("correct-horse-battery", hashed)
    assert not verify_password("wrong", hashed)


def test_access_token_roundtrip():
    user_id = uuid4()
    token = create_access_token(user_id)
    payload = decode_token(token)
    assert payload["sub"] == str(user_id)
    assert payload["type"] == "access"
