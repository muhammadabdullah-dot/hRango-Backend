"""Webhooks: outside systems told about events. The secret is made here and shown once."""
import json
import secrets
from typing import Any

from app.core import events
from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import integrations_repo

DELIVERY_STATUSES = ("pending", "delivered", "failed")


def new_secret() -> str:
    return "whsec_" + secrets.token_urlsafe(32)


def _events_json(chosen: list[str]) -> str:
    cleaned = sorted({e.strip() for e in chosen if e and e.strip()})
    bad = [e for e in cleaned if not events.valid_subscription(e)]
    if not cleaned or bad:
        raise AppError(422, "VALIDATION_FAILED", f"Unknown events: {', '.join(bad) or 'none chosen'}.",
                       {"events": "Choose events from the list, \"module.*\" or \"*\"."})
    return json.dumps(cleaned)


def list_webhooks(db: Db, ctx: RequestContext, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return integrations_repo.list_webhooks(db, ctx.company_id, page, page_size)


def get_webhook(db: Db, ctx: RequestContext, webhook_id: int) -> dict[str, Any]:
    return integrations_repo.get_webhook(db, ctx.company_id, webhook_id)


def create_webhook(db: Db, ctx: RequestContext, name: str, url: str, chosen: list[str],
                   is_active: bool) -> dict[str, Any]:
    return integrations_repo.save_webhook(db, ctx.company_id, ctx.user_id, None, name, url.strip(),
                                          _events_json(chosen), is_active, new_secret(), None)


def update_webhook(db: Db, ctx: RequestContext, webhook_id: int, name: str, url: str, chosen: list[str],
                   is_active: bool, row_version: bytes) -> dict[str, Any]:
    return integrations_repo.save_webhook(db, ctx.company_id, ctx.user_id, webhook_id, name, url.strip(),
                                          _events_json(chosen), is_active, None, row_version)


def rotate_secret(db: Db, ctx: RequestContext, webhook_id: int, row_version: bytes) -> dict[str, Any]:
    row = integrations_repo.get_webhook(db, ctx.company_id, webhook_id)
    return integrations_repo.save_webhook(db, ctx.company_id, ctx.user_id, webhook_id, row["name"], row["url"],
                                          row["events"], bool(row["is_active"]), new_secret(), row_version)


def delete_webhook(db: Db, ctx: RequestContext, webhook_id: int, row_version: bytes) -> None:
    integrations_repo.delete_webhook(db, ctx.company_id, ctx.user_id, webhook_id, row_version)


def ping(db: Db, ctx: RequestContext, webhook_id: int) -> dict[str, Any]:
    return integrations_repo.ping(db, ctx.company_id, ctx.user_id, webhook_id)


def list_deliveries(db: Db, ctx: RequestContext, webhook_id: int, status: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    if status is not None and status not in DELIVERY_STATUSES:
        raise AppError(422, "VALIDATION_FAILED", "status is not valid.", {"status": "pending, delivered or failed."})
    return integrations_repo.list_deliveries(db, ctx.company_id, webhook_id, status, page, page_size)


def redeliver(db: Db, ctx: RequestContext, delivery_id: int) -> None:
    integrations_repo.redeliver(db, ctx.company_id, ctx.user_id, delivery_id)
