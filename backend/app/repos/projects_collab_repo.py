"""Project management collaboration data access: comments, attachments, time, reminders, sharing."""
from datetime import datetime
from typing import Any

from app.core.db import Db

Rows = list[dict[str, Any]]


# --------------------------------------------------------------------------- comments

def list_comments(db: Db, company_id: int, actor_user_id: int, task_id: int) -> Rows:
    return db.call("pm.usp_task_comment_list", company_id=company_id, actor_user_id=actor_user_id, task_id=task_id)


def save_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int | None, task_id: int | None,
                 parent_id: int | None, body: str, assigned_to_id: int | None, mentions: str,
                 row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_task_comment_save", company_id=company_id, actor_user_id=actor_user_id, id=comment_id,
                       task_id=task_id, parent_id=parent_id, body=body, assigned_to_id=assigned_to_id,
                       mentions=mentions, row_version=row_version)


def assign_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int,
                   assigned_to_id: int | None) -> dict[str, Any]:
    return db.call_one("pm.usp_task_comment_assign", company_id=company_id, actor_user_id=actor_user_id,
                       id=comment_id, assigned_to_id=assigned_to_id)


def resolve_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int, resolved: bool) -> dict[str, Any]:
    return db.call_one("pm.usp_task_comment_resolve", company_id=company_id, actor_user_id=actor_user_id,
                       id=comment_id, is_resolved=resolved)


def react_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int, reaction: str | None) -> dict[str, Any]:
    return db.call_one("pm.usp_task_comment_react", company_id=company_id, actor_user_id=actor_user_id, id=comment_id,
                       reaction=reaction)


def delete_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int, row_version: bytes) -> None:
    db.call("pm.usp_task_comment_delete", company_id=company_id, actor_user_id=actor_user_id, id=comment_id,
            row_version=row_version)


# --------------------------------------------------------------------------- attachments

def list_attachments(db: Db, company_id: int, actor_user_id: int, task_id: int) -> Rows:
    return db.call("pm.usp_task_attachment_list", company_id=company_id, actor_user_id=actor_user_id, task_id=task_id)


def add_attachment(db: Db, company_id: int, actor_user_id: int, task_id: int, file_id: int) -> dict[str, Any]:
    return db.call_one("pm.usp_task_attachment_add", company_id=company_id, actor_user_id=actor_user_id,
                       task_id=task_id, file_id=file_id)


def delete_attachment(db: Db, company_id: int, actor_user_id: int, attachment_id: int) -> None:
    db.call("pm.usp_task_attachment_delete", company_id=company_id, actor_user_id=actor_user_id, id=attachment_id)


def add_attachment_link(db: Db, company_id: int, actor_user_id: int, task_id: int, provider: str, external_id: str,
                        name: str, web_url: str, mime_type: str | None, size_bytes: int | None) -> dict[str, Any]:
    return db.call_one("pm.usp_task_attachment_link_add", company_id=company_id, actor_user_id=actor_user_id,
                       task_id=task_id, provider=provider, external_id=external_id, name=name, web_url=web_url,
                       mime_type=mime_type, size_bytes=size_bytes)


def delete_attachment_link(db: Db, company_id: int, actor_user_id: int, link_id: int) -> None:
    db.call("pm.usp_task_attachment_link_delete", company_id=company_id, actor_user_id=actor_user_id, id=link_id)


# --------------------------------------------------------------------------- time

def list_time_entries(db: Db, company_id: int, actor_user_id: int, task_id: int) -> Rows:
    return db.call("pm.usp_time_entry_list", company_id=company_id, actor_user_id=actor_user_id, task_id=task_id)


def save_time_entry(db: Db, company_id: int, actor_user_id: int, entry_id: int | None, task_id: int | None,
                    employee_id: int | None, start_at: datetime, end_at: datetime | None, minutes: int | None,
                    notes: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_time_entry_save", company_id=company_id, actor_user_id=actor_user_id, id=entry_id,
                       task_id=task_id, employee_id=employee_id, start_at=start_at, end_at=end_at, minutes=minutes,
                       notes=notes, row_version=row_version)


def delete_time_entry(db: Db, company_id: int, actor_user_id: int, entry_id: int) -> None:
    db.call("pm.usp_time_entry_delete", company_id=company_id, actor_user_id=actor_user_id, id=entry_id)


def start_timer(db: Db, company_id: int, actor_user_id: int, task_id: int) -> dict[str, Any]:
    return db.call_one("pm.usp_time_entry_timer_start", company_id=company_id, actor_user_id=actor_user_id,
                       task_id=task_id)


def stop_timer(db: Db, company_id: int, actor_user_id: int, notes: str | None) -> dict[str, Any]:
    return db.call_one("pm.usp_time_entry_timer_stop", company_id=company_id, actor_user_id=actor_user_id, notes=notes)


# --------------------------------------------------------------------------- reminders

def list_reminders(db: Db, company_id: int, actor_user_id: int, entity_type: str | None, entity_id: int | None,
                   include_done: bool, page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = db.call_sets("pm.usp_reminder_list", company_id=company_id, actor_user_id=actor_user_id,
                               entity_type=entity_type, entity_id=entity_id, include_done=include_done, page=page,
                               page_size=page_size)
    return total[0]["total"], rows


def save_reminder(db: Db, company_id: int, actor_user_id: int, reminder_id: int | None, values: dict[str, Any],
                  row_version: bytes | None) -> dict[str, Any]:
    _total, rows = db.call_sets("pm.usp_reminder_save", company_id=company_id, actor_user_id=actor_user_id,
                                id=reminder_id, **values, row_version=row_version)
    return rows[0]


def delete_reminder(db: Db, company_id: int, actor_user_id: int, reminder_id: int) -> None:
    db.call("pm.usp_reminder_delete", company_id=company_id, actor_user_id=actor_user_id, id=reminder_id)


def deliver_due_reminders(db: Db, company_id: int | None, now: datetime | None) -> int:
    row = db.call_one("pm.usp_reminder_deliver_due", company_id=company_id, now=now)
    return int(row["delivered"]) if row else 0


# --------------------------------------------------------------------------- sharing

def get_share(db: Db, company_id: int, actor_user_id: int, entity_type: str, entity_id: int) -> tuple[Rows, Rows]:
    link, members = db.call_sets("pm.usp_share_link_get", company_id=company_id, actor_user_id=actor_user_id,
                                 entity_type=entity_type, entity_id=entity_id)
    return link, members


def save_share(db: Db, company_id: int, actor_user_id: int, values: dict[str, Any], token: str, properties: str | None,
               members: str, row_version: bytes | None) -> tuple[Rows, Rows]:
    link, rows = db.call_sets("pm.usp_share_link_save", company_id=company_id, actor_user_id=actor_user_id,
                              entity_type=values["entity_type"], entity_id=values["entity_id"], token=token,
                              share_scope=values["share_scope"], is_public=values["is_public"],
                              allow_open_tasks=values["allow_open_tasks"], valid_from=values["valid_from"],
                              valid_to=values["valid_to"], max_access=values["max_access"], properties=properties,
                              members=members, row_version=row_version)
    return link, rows


def delete_share(db: Db, company_id: int, actor_user_id: int, share_id: int) -> None:
    db.call("pm.usp_share_link_delete", company_id=company_id, actor_user_id=actor_user_id, id=share_id)
