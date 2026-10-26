"""The inbox: the signed-in user's own notifications in the active company. Other modules add
notifications in their procedures with core.usp_notification_add / core.usp_notification_add_employee."""
from typing import Any

from app.core.db import Db
from app.middlewares.auth import RequestContext
from app.repos import inbox_repo


def summary(db: Db, ctx: RequestContext) -> tuple[int, list[dict[str, Any]]]:
    return inbox_repo.summary(db, ctx.company_id, ctx.user_id)


def list_notifications(db: Db, ctx: RequestContext, unread_only: bool, page: int, page_size: int):
    return inbox_repo.list_notifications(db, ctx.company_id, ctx.user_id, unread_only, page, page_size)


def mark_read(db: Db, ctx: RequestContext, notification_id: int | None) -> int:
    return inbox_repo.mark(db, ctx.company_id, ctx.user_id, notification_id, "read")


def clear(db: Db, ctx: RequestContext, notification_id: int | None) -> int:
    return inbox_repo.mark(db, ctx.company_id, ctx.user_id, notification_id, "clear")
