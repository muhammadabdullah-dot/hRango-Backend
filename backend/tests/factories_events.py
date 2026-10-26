"""Test helpers for what modules publish: rows in core.outbox_event and inbox notifications. Read with plain
SQL so module tests do not depend on the integrations or inbox endpoints."""
import json
from typing import Any

from app.core.db import Db


def _rows(db: Db, sql: str, *params) -> list[dict[str, Any]]:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]
    finally:
        cur.close()


def events(db: Db, company_id: int, event_type: str, entity_id: int | str | None = None) -> list[dict[str, Any]]:
    """Events of a type for the company (optionally for one entity), oldest first, with `data` = parsed payload."""
    rows = _rows(db, "SELECT id, event_type, entity_type, entity_id, payload FROM core.outbox_event "
                     "WHERE company_id = ? AND event_type = ? AND (? IS NULL OR entity_id = ?) ORDER BY id",
                 company_id, event_type, entity_id, entity_id)
    for r in rows:
        r["data"] = json.loads(r["payload"])
    return rows


def notifications(db: Db, company_id: int, employee_id: int, entity_type: str | None = None,
                  entity_id: int | str | None = None) -> list[dict[str, Any]]:
    """Notifications sent to the sign-in accounts of an employee, oldest first."""
    return _rows(db, "SELECT n.id, n.notification_type, n.title, n.body, n.link, n.entity_type, n.entity_id "
                     "FROM core.notification n JOIN auth.user_account u ON u.id = n.user_account_id "
                     "WHERE n.company_id = ? AND u.employee_id = ? AND (? IS NULL OR n.entity_type = ?) "
                     "AND (? IS NULL OR n.entity_id = ?) ORDER BY n.id",
                 company_id, employee_id, entity_type, entity_type, entity_id, entity_id)


def user_notifications(db: Db, company_id: int, user_id: int, entity_type: str | None = None) -> list[dict[str, Any]]:
    return _rows(db, "SELECT id, notification_type, title, body, link, entity_type, entity_id FROM core.notification "
                     "WHERE company_id = ? AND user_account_id = ? AND (? IS NULL OR entity_type = ?) ORDER BY id",
                 company_id, user_id, entity_type, entity_type)
