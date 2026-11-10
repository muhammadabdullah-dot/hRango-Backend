"""Platform staff: sign-in, sessions, accounts and their audit trail."""
from datetime import datetime
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def login_get(db: Db, email: str) -> Row | None:
    return db.call_one("plat.usp_staff_login_get", email=email)


def session_create(db: Db, staff_id: int, device: str | None, ip_address: str | None, expires_at: datetime) -> Row:
    return db.call_one("plat.usp_staff_session_create", staff_id=staff_id, device=device, ip_address=ip_address,
                       expires_at=expires_at.replace(tzinfo=None))


def session_context(db: Db, session_id: int, staff_id: int) -> Row | None:
    return db.call_one("plat.usp_staff_session_context", session_id=session_id, staff_id=staff_id)


def session_end(db: Db, session_id: int) -> None:
    db.call("plat.usp_staff_session_end", session_id=session_id)


def audit(db: Db, staff_id: int | None, action: str, ip_address: str | None = None, detail: str | None = None) -> None:
    db.call("plat.usp_staff_audit_add", staff_id=staff_id, action=action, ip_address=ip_address, detail=detail)


def list_staff(db: Db, search: str | None, page: int, page_size: int) -> tuple[int, list[Row]]:
    sets = db.call_sets("plat.usp_staff_list", search=search, page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1]


def get_staff(db: Db, staff_id: int) -> Row:
    return db.call_one("plat.usp_staff_get", id=staff_id)


def save_staff(db: Db, actor_id: int, staff_id: int | None, f: Row, password_hash: str | None,
               row_version: bytes | None) -> Row:
    return db.call_one("plat.usp_staff_save", actor_id=actor_id, id=staff_id, email=f["email"],
                       display_name=f["display_name"], role=f["role"], is_active=f["is_active"],
                       password_hash=password_hash, row_version=row_version)


def set_password(db: Db, actor_id: int, staff_id: int, password_hash: str) -> None:
    db.call("plat.usp_staff_password_set", actor_id=actor_id, id=staff_id, password_hash=password_hash)


def list_audit(db: Db, page: int, page_size: int) -> tuple[int, list[Row]]:
    sets = db.call_sets("plat.usp_staff_audit_list", page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1]
