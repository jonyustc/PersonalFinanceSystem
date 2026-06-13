"""Verify Google "Sign in with Google" ID tokens.

Uses Google's published JWKS to validate the token signature locally, then
checks the issuer, audience (our OAuth client IDs), and expiry. Relies only on
httpx + python-jose, which are already project dependencies.
"""

from __future__ import annotations

import time

import httpx
from jose import jwt
from jose.exceptions import JWTError

# Google rotates these signing keys; we cache them with a short TTL.
GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}
_CERTS_TTL_SECONDS = 3600

_certs_cache: dict[str, object] = {"keys": None, "expires_at": 0.0}


class GoogleTokenError(ValueError):
    """Raised when a Google ID token cannot be trusted."""


async def _get_google_certs() -> dict:
    now = time.time()
    cached = _certs_cache["keys"]
    if cached is not None and float(_certs_cache["expires_at"]) > now:
        return cached  # type: ignore[return-value]

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(GOOGLE_CERTS_URL)
        response.raise_for_status()
        certs = response.json()

    _certs_cache["keys"] = certs
    _certs_cache["expires_at"] = now + _CERTS_TTL_SECONDS
    return certs


async def verify_google_id_token(token: str, allowed_client_ids: list[str]) -> dict:
    """Validate a Google ID token and return its claims.

    Raises GoogleTokenError on any verification failure.
    """
    if not allowed_client_ids:
        raise GoogleTokenError("Google login is not configured")

    try:
        header = jwt.get_unverified_header(token)
    except JWTError as exc:
        raise GoogleTokenError("Malformed Google token") from exc

    kid = header.get("kid")
    certs = await _get_google_certs()
    jwk_data = next((k for k in certs.get("keys", []) if k.get("kid") == kid), None)
    if jwk_data is None:
        # Key may have just rotated; bust the cache and try once more.
        _certs_cache["expires_at"] = 0.0
        certs = await _get_google_certs()
        jwk_data = next((k for k in certs.get("keys", []) if k.get("kid") == kid), None)
    if jwk_data is None:
        raise GoogleTokenError("Unknown Google signing key")

    try:
        # Signature and expiry are verified here; audience/issuer are checked
        # manually below so we can allow several client IDs (web + mobile).
        claims = jwt.decode(
            token,
            jwk_data,
            algorithms=["RS256"],
            options={"verify_aud": False, "verify_iss": False},
        )
    except JWTError as exc:
        raise GoogleTokenError("Invalid Google token") from exc

    if claims.get("aud") not in allowed_client_ids:
        raise GoogleTokenError("Token audience mismatch")
    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise GoogleTokenError("Invalid token issuer")

    email = claims.get("email")
    if not email:
        raise GoogleTokenError("Token missing email")
    if claims.get("email_verified") in (False, "false"):
        raise GoogleTokenError("Google email is not verified")

    return claims
