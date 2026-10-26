"""Sign-in, sessions and permission checks."""
from datetime import datetime
from typing import Any

from app.core.db import Db


def login_get(db: Db, email: str) -> dict[str, Any] | None:
    return db.call_one("auth.usp_login_get", email=email)


def session_create(db: Db, user_id: int, device: str | None, ip_address: str | None,
                   expires_at: datetime) -> dict[str, Any]:
    return db.call_one("auth.usp_session_create", user_id=user_id, device=device, ip_address=ip_address,
                       expires_at=expires_at.replace(tzinfo=None))


def session_context(db: Db, session_id: int, user_id: int, company_id: int | None) -> dict[str, Any] | None:
    return db.call_one("auth.usp_session_context", session_id=session_id, user_id=user_id, company_id=company_id)


def session_end(db: Db, session_id: int) -> None:
    db.call("auth.usp_session_end", session_id=session_id)


def permission_check(db: Db, company_id: int, user_id: int, code: str) -> dict[str, Any]:
    return db.call_one("auth.usp_permission_check", company_id=company_id, user_id=user_id, code=code)


def user_permissions(db: Db, company_id: int, user_id: int) -> list[dict[str, Any]]:
    return db.call("auth.usp_user_permission_list", company_id=company_id, user_id=user_id)
