"""Webhooks and their deliveries."""
from typing import Any

from app.core.db import Db


def list_webhooks(db: Db, company_id: int, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("core.usp_webhook_list", company_id=company_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_webhook(db: Db, company_id: int, webhook_id: int) -> dict[str, Any]:
    return db.call_one("core.usp_webhook_get", company_id=company_id, id=webhook_id)


def save_webhook(db: Db, company_id: int, actor_user_id: int, webhook_id: int | None, name: str, url: str,
                 events_json: str, is_active: bool, secret: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("core.usp_webhook_save", company_id=company_id, actor_user_id=actor_user_id, id=webhook_id,
                       name=name, url=url, events=events_json, is_active=is_active, secret=secret,
                       row_version=row_version)


def delete_webhook(db: Db, company_id: int, actor_user_id: int, webhook_id: int, row_version: bytes) -> None:
    db.call("core.usp_webhook_delete", company_id=company_id, actor_user_id=actor_user_id, id=webhook_id,
            row_version=row_version)


def ping(db: Db, company_id: int, actor_user_id: int, webhook_id: int) -> dict[str, Any]:
    return db.call_one("core.usp_webhook_ping", company_id=company_id, actor_user_id=actor_user_id, id=webhook_id)


def list_deliveries(db: Db, company_id: int, webhook_id: int, status: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("core.usp_webhook_delivery_list", company_id=company_id, webhook_id=webhook_id,
                               status=status, page=page, page_size=page_size)
    return total[0]["total"], rows


def redeliver(db: Db, company_id: int, actor_user_id: int, delivery_id: int) -> None:
    db.call("core.usp_webhook_redeliver", company_id=company_id, actor_user_id=actor_user_id, id=delivery_id)
