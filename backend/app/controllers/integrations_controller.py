import json
from typing import Any

from app.core import events
from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.integrations import (DeliveryOut, EventTypeOut, PingOut, WebhookIn, WebhookOut,
                                      WebhookWithSecretOut)
from app.services import integrations_service as svc


def _fields(row: dict[str, Any]) -> dict[str, Any]:
    secret = row["secret"] or ""
    return {**row, "events": json.loads(row["events"] or "[]"), "row_version": row_version_out(row["row_version"]),
            "secret_hint": f"whsec_...{secret[-4:]}" if secret else ""}


def _webhook(row: dict[str, Any]) -> WebhookOut:
    return WebhookOut(**_fields(row))


def event_types() -> dict:
    return {"data": [EventTypeOut(**e) for e in events.catalogue()]}


def list_webhooks(db: Db, ctx: RequestContext, paging: PageParams) -> dict:
    total, rows = svc.list_webhooks(db, ctx, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _webhook)


def get_webhook(db: Db, ctx: RequestContext, webhook_id: int) -> dict:
    return {"data": _webhook(svc.get_webhook(db, ctx, webhook_id))}


def create_webhook(db: Db, ctx: RequestContext, body: WebhookIn) -> dict:
    row = svc.create_webhook(db, ctx, body.name, body.url, body.events, body.is_active)
    return {"data": WebhookWithSecretOut(**_fields(row))}


def update_webhook(db: Db, ctx: RequestContext, webhook_id: int, body: WebhookIn) -> dict:
    row = svc.update_webhook(db, ctx, webhook_id, body.name, body.url, body.events, body.is_active,
                             row_version_in(body.row_version))
    return {"data": _webhook(row)}


def rotate_secret(db: Db, ctx: RequestContext, webhook_id: int, row_version: str) -> dict:
    return {"data": WebhookWithSecretOut(**_fields(svc.rotate_secret(db, ctx, webhook_id, row_version_in(row_version))))}


def delete_webhook(db: Db, ctx: RequestContext, webhook_id: int, row_version: str | None) -> None:
    svc.delete_webhook(db, ctx, webhook_id, row_version_in(row_version))


def ping(db: Db, ctx: RequestContext, webhook_id: int) -> dict:
    return {"data": PingOut(**svc.ping(db, ctx, webhook_id))}


def list_deliveries(db: Db, ctx: RequestContext, webhook_id: int, status: str | None, paging: PageParams) -> dict:
    total, rows = svc.list_deliveries(db, ctx, webhook_id, status, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: DeliveryOut(**r))


def redeliver(db: Db, ctx: RequestContext, delivery_id: int) -> None:
    svc.redeliver(db, ctx, delivery_id)
