"""Platform staff rules that do not need the data; the rest are in db/procedures/plat."""
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, invalid
from app.core.security import create_staff_token, hash_password, staff_token_expiry, verify_password
from app.repos import platform_repo

_BAD_LOGIN = AppError(401, "BAD_CREDENTIALS", "The email or password is not correct.")


def _check_password(password: str) -> None:
    if not any(ch.isalpha() for ch in password) or not any(ch.isdigit() for ch in password):
        raise invalid("Use at least 12 characters with letters and digits.", "password")


def login(db: Db, email: str, password: str, device: str | None, ip_address: str | None) -> tuple[str, dict[str, Any]]:
    """The same answer for an unknown email and a wrong password; a failed attempt is logged."""
    account = platform_repo.login_get(db, email.strip().lower())
    if account is None or not verify_password(password, account["password_hash"]):
        platform_repo.audit(db, account["id"] if account else None, "sign_in_failed", ip_address,
                            None if account else email.strip().lower()[:200])
        raise _BAD_LOGIN
    if not account["is_active"]:
        raise AppError(403, "ACCOUNT_DISABLED", "This account is switched off.")
    expires_at = staff_token_expiry()
    session = platform_repo.session_create(db, account["id"], device, ip_address, expires_at)
    return create_staff_token(session["session_id"], account["id"], expires_at), account


def add_staff(db: Db, actor_id: int, fields: dict[str, Any]) -> dict[str, Any]:
    password = fields.get("password")
    if not password:
        raise invalid("A password is required for a new staff member.", "password")
    _check_password(password)
    return platform_repo.save_staff(db, actor_id, None, fields, hash_password(password), None)


def update_staff(db: Db, actor_id: int, staff_id: int, fields: dict[str, Any], row_version: bytes) -> dict[str, Any]:
    return platform_repo.save_staff(db, actor_id, staff_id, fields, None, row_version)


def set_password(db: Db, actor_id: int, staff_id: int, password: str) -> None:
    _check_password(password)
    platform_repo.set_password(db, actor_id, staff_id, hash_password(password))
