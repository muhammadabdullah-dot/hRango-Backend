"""Inbox data access (core.notification)."""
from typing import Any

from app.core.db import Db


def summary(db: Db, company_id: int, user_id: int) -> tuple[int, list[dict[str, Any]]]:
    unread, latest = db.call_sets("core.usp_notification_summary", company_id=company_id, user_id=user_id, latest=5)
    return unread[0]["unread"], latest


def list_notifications(db: Db, company_id: int, user_id: int, unread_only: bool, page: int,
                       page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("core.usp_notification_list", company_id=company_id, user_id=user_id,
                               unread_only=unread_only, page=page, page_size=page_size)
    return total[0]["total"], rows


def mark(db: Db, company_id: int, user_id: int, notification_id: int | None, action: str) -> int:
    return db.call_one("core.usp_notification_mark", company_id=company_id, user_id=user_id, id=notification_id,
                       action=action)["changed"]
