"""Settings -> Integrations: webhooks that tell outside systems (chat, SMS or mail gateways, ERPs) about
events. Every notification is an event (notification.created); modules publish their own events.
Payload and signature: app/core/events.py."""
from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import integrations_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.integrations import (DeliveryOut, EventTypeOut, PingOut, RotateIn, WebhookIn, WebhookOut,
                                      WebhookWithSecretOut)

router = APIRouter(prefix="/integrations", tags=["integrations"])
VIEW, CREATE = require("integrations.webhooks.view"), require("integrations.webhooks.create")
EDIT, DELETE = require("integrations.webhooks.edit"), require("integrations.webhooks.delete")


@router.get("/events", response_model=Item[list[EventTypeOut]])
def event_types(ctx: RequestContext = Depends(VIEW)) -> dict:
    """The events a webhook can subscribe to."""
    return c.event_types()


@router.get("/webhooks", response_model=Paginated[WebhookOut])
def list_webhooks(paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_webhooks(db, ctx, paging)


@router.post("/webhooks", response_model=Item[WebhookWithSecretOut], status_code=status.HTTP_201_CREATED)
def create_webhook(body: WebhookIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(CREATE)) -> dict:
    """Creates a webhook. The response holds its signing secret; it is not shown again."""
    return c.create_webhook(db, ctx, body)


@router.get("/webhooks/{webhook_id}", response_model=Item[WebhookOut])
def get_webhook(webhook_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.get_webhook(db, ctx, webhook_id)


@router.put("/webhooks/{webhook_id}", response_model=Item[WebhookOut])
def update_webhook(webhook_id: int, body: WebhookIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.update_webhook(db, ctx, webhook_id, body)


@router.post("/webhooks/{webhook_id}/rotate-secret", response_model=Item[WebhookWithSecretOut])
def rotate_secret(webhook_id: int, body: RotateIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.rotate_secret(db, ctx, webhook_id, body.row_version)


@router.delete("/webhooks/{webhook_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_webhook(webhook_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(DELETE)) -> Response:
    c.delete_webhook(db, ctx, webhook_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/webhooks/{webhook_id}/ping", response_model=Item[PingOut], status_code=status.HTTP_202_ACCEPTED)
def ping(webhook_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    """Queues a webhook.ping event for this webhook only."""
    return c.ping(db, ctx, webhook_id)


@router.get("/webhooks/{webhook_id}/deliveries", response_model=Paginated[DeliveryOut])
def list_deliveries(webhook_id: int, status_: str | None = Query(None, alias="status"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_deliveries(db, ctx, webhook_id, status_, paging)


@router.post("/webhooks/deliveries/{delivery_id}/redeliver", status_code=status.HTTP_202_ACCEPTED)
def redeliver(delivery_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> Response:
    c.redeliver(db, ctx, delivery_id)
    return Response(status_code=status.HTTP_202_ACCEPTED)
