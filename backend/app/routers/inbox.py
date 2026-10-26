"""Inbox: the signed-in user's notifications (top-bar bell, mobile Notifications)."""
from fastapi import APIRouter, Depends, Query

from app.controllers import inbox_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.inbox import ChangedOut, InboxSummary, NotificationOut

router = APIRouter(prefix="/inbox", tags=["inbox"])
VIEW = "inbox.notifications.view"


@router.get("", response_model=Item[InboxSummary])
def summary(db: Db = Depends(get_db), ctx: RequestContext = Depends(require(VIEW))) -> dict:
    """Unread count and the latest five, for the top bar."""
    return c.summary(db, ctx)


@router.get("/notifications", response_model=Paginated[NotificationOut])
def list_notifications(unread_only: bool = Query(False, alias="unreadOnly"), paging: PageParams = Depends(page_params),
                       db: Db = Depends(get_db), ctx: RequestContext = Depends(require(VIEW))) -> dict:
    return c.list_notifications(db, ctx, unread_only, paging)


@router.patch("/notifications/read-all", response_model=Item[ChangedOut])
def mark_all_read(db: Db = Depends(get_db), ctx: RequestContext = Depends(require(VIEW))) -> dict:
    return c.mark_read(db, ctx, None)


@router.patch("/notifications/clear-all", response_model=Item[ChangedOut])
def clear_all(db: Db = Depends(get_db), ctx: RequestContext = Depends(require(VIEW))) -> dict:
    return c.clear(db, ctx, None)


@router.patch("/notifications/{notification_id}/read", response_model=Item[ChangedOut])
def mark_read(notification_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require(VIEW))) -> dict:
    return c.mark_read(db, ctx, notification_id)


@router.patch("/notifications/{notification_id}/clear", response_model=Item[ChangedOut])
def clear(notification_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require(VIEW))) -> dict:
    return c.clear(db, ctx, notification_id)
