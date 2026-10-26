"""Passwords (scrypt, standard library) and access tokens (JWT, HS256).

A token names its session; the session row decides whether the token still works, so ending a
session signs that device out at once (ACC-14).
"""
import base64
import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import settings

_N, _R, _P = 2**14, 8, 1


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    return "scrypt${}${}${}${}${}".format(_N, _R, _P, base64.b64encode(salt).decode(), base64.b64encode(digest).decode())


def verify_password(password: str, stored: str | None) -> bool:
    try:
        scheme, n, r, p, salt, digest = (stored or "").split("$")
        if scheme != "scrypt":
            return False
        expected = base64.b64decode(digest)
        actual = hashlib.scrypt(password.encode("utf-8"), salt=base64.b64decode(salt), n=int(n), r=int(r),
                                p=int(p), dklen=len(expected))
        return hmac.compare_digest(actual, expected)
    except ValueError:
        return False


def token_expiry() -> datetime:
    return datetime.now(UTC).replace(microsecond=0) + timedelta(hours=settings.token_hours)


def create_token(session_id: int, user_id: int, expires_at: datetime) -> str:
    return jwt.encode({"sid": str(session_id), "sub": str(user_id), "exp": expires_at}, settings.jwt_secret,
                      algorithm="HS256")


def read_token(token: str) -> tuple[int, int] | None:
    """(session_id, user_id), or None when the token is malformed, forged or expired."""
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], options={"require": ["exp", "sid"]})
        return int(claims["sid"]), int(claims["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        return None
