"""Signing in and out."""
from typing import Any

from app.core import login_throttle
from app.core.config import settings
from app.core.db import Db
from app.core.errors import AppError
from app.core.security import create_token, password_matches, token_expiry
from app.repos import auth_repo

_BAD_LOGIN = AppError(401, "INVALID_CREDENTIALS", "Incorrect email or password.")


def login(db: Db, email: str, password: str, device: str | None, ip_address: str | None) -> tuple[str, int, int]:
    """Returns (token, session_id, user_id). The same message, and the same time, for an unknown email and
    a wrong password; repeated failures pause sign-in (app.core.login_throttle)."""
    email = email.strip().lower()
    if settings.login_throttle:
        login_throttle.check(db, "customer", email, ip_address)
    account = auth_repo.login_get(db, email)
    ok = password_matches(password, account["password_hash"] if account else None)
    if settings.login_throttle:
        login_throttle.record(db, "customer", email, ip_address, ok)
    if not ok:
        raise _BAD_LOGIN
    if not account["is_active"]:
        raise AppError(403, "ACCOUNT_DISABLED", "This account is switched off. Ask your administrator.")
    if account["is_blocked"]:
        raise AppError(403, "ORGANISATION_SUSPENDED", "This organisation is suspended. Contact hRango support.")
    expires_at = token_expiry()
    session = auth_repo.session_create(db, account["id"], device, ip_address, expires_at)
    return create_token(session["session_id"], account["id"], expires_at), session["session_id"], account["id"]


def context_row(db: Db, session_id: int, user_id: int) -> dict[str, Any] | None:
    return auth_repo.session_context(db, session_id, user_id, None)


def permissions(db: Db, company_id: int, user_id: int) -> list[dict[str, Any]]:
    return auth_repo.user_permissions(db, company_id, user_id)


def logout(db: Db, session_id: int) -> None:
    auth_repo.session_end(db, session_id)
