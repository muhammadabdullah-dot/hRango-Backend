"""HTTP shape for the inbox."""
from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.inbox import ChangedOut, InboxSummary, NotificationOut
from app.services import inbox_service


def _note(row: dict[str, Any]) -> NotificationOut:
    return NotificationOut(**row, read=row["read_at"] is not None)


def summary(db: Db, ctx: RequestContext) -> dict:
    unread, latest = inbox_service.summary(db, ctx)
    return {"data": InboxSummary(unread=unread, latest=[_note(r) for r in latest])}


def list_notifications(db: Db, ctx: RequestContext, unread_only: bool, paging: PageParams) -> dict:
    total, rows = inbox_service.list_notifications(db, ctx, unread_only, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _note)


def mark_read(db: Db, ctx: RequestContext, notification_id: int | None) -> dict:
    return {"data": ChangedOut(changed=inbox_service.mark_read(db, ctx, notification_id))}


def clear(db: Db, ctx: RequestContext, notification_id: int | None) -> dict:
    return {"data": ChangedOut(changed=inbox_service.clear(db, ctx, notification_id))}
