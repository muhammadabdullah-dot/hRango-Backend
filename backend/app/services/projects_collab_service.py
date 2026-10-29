"""Project management collaboration rules: comments, attachments, time tracking, reminders and
sharing. Access and workspace-role rules are in the pm procedures; nothing here sends anything."""
import json
import secrets
from datetime import datetime
from typing import Any

from app.core.db import Db
from app.core.errors import invalid
from app.middlewares.auth import RequestContext
from app.repos import projects_collab_repo
from app.schemas.projects_collab import (SHARE_PROPERTIES, AttachmentIn, AttachmentLinkIn, CommentEditIn, CommentIn,
                                         ReminderIn, ShareIn, TimeEntryIn)
from app.services.projects_service import dumps, naive_utc

Rows = list[dict[str, Any]]


def _loads(text: str | None) -> Any:
    return json.loads(text) if text else None


def shape_comment(row: dict[str, Any]) -> dict[str, Any]:
    out = dict(row)
    out["reactions"] = _loads(out.pop("reactions_json", None)) or []
    out["mentions"] = _loads(out.pop("mentions_json", None)) or []
    return out


def _mentions(body: CommentIn | CommentEditIn) -> str:
    return dumps([m.model_dump(by_alias=False) for m in body.mentions])


# --------------------------------------------------------------------------- comments

def list_comments(db: Db, ctx: RequestContext, task_id: int) -> Rows:
    return [shape_comment(r) for r in projects_collab_repo.list_comments(db, ctx.company_id, ctx.user_id, task_id)]


def add_comment(db: Db, ctx: RequestContext, task_id: int, body: CommentIn) -> dict[str, Any]:
    return shape_comment(projects_collab_repo.save_comment(db, ctx.company_id, ctx.user_id, None, task_id, body.parent_id,
                                                           body.body, body.assigned_to_id, _mentions(body), None))


def edit_comment(db: Db, ctx: RequestContext, comment_id: int, body: CommentEditIn, row_version: bytes) -> dict[str, Any]:
    return shape_comment(projects_collab_repo.save_comment(db, ctx.company_id, ctx.user_id, comment_id, None, None,
                                                           body.body, None, _mentions(body), row_version))


def assign_comment(db: Db, ctx: RequestContext, comment_id: int, assigned_to_id: int | None) -> dict[str, Any]:
    return shape_comment(projects_collab_repo.assign_comment(db, ctx.company_id, ctx.user_id, comment_id,
                                                             assigned_to_id))


def resolve_comment(db: Db, ctx: RequestContext, comment_id: int, resolved: bool) -> dict[str, Any]:
    return shape_comment(projects_collab_repo.resolve_comment(db, ctx.company_id, ctx.user_id, comment_id, resolved))


def react_comment(db: Db, ctx: RequestContext, comment_id: int, reaction: str | None) -> dict[str, Any]:
    return shape_comment(projects_collab_repo.react_comment(db, ctx.company_id, ctx.user_id, comment_id, reaction))


def delete_comment(db: Db, ctx: RequestContext, comment_id: int, row_version: bytes) -> None:
    projects_collab_repo.delete_comment(db, ctx.company_id, ctx.user_id, comment_id, row_version)


# --------------------------------------------------------------------------- attachments

def list_attachments(db: Db, ctx: RequestContext, task_id: int) -> Rows:
    return projects_collab_repo.list_attachments(db, ctx.company_id, ctx.user_id, task_id)


def add_attachment(db: Db, ctx: RequestContext, task_id: int, body: AttachmentIn) -> dict[str, Any]:
    return projects_collab_repo.add_attachment(db, ctx.company_id, ctx.user_id, task_id, body.file_id)


def delete_attachment(db: Db, ctx: RequestContext, attachment_id: int) -> None:
    projects_collab_repo.delete_attachment(db, ctx.company_id, ctx.user_id, attachment_id)


def add_attachment_link(db: Db, ctx: RequestContext, task_id: int, body: AttachmentLinkIn) -> dict[str, Any]:
    # TODO(pm): once storage is connected (T9), check the caller's connection to body.provider and read the
    # file's name, type and size from the provider instead of trusting the picker.
    if not body.web_url.lower().startswith("https://"):
        raise invalid("A link must begin with https://.", "webUrl")
    return projects_collab_repo.add_attachment_link(db, ctx.company_id, ctx.user_id, task_id, body.provider,
                                                    body.external_id, body.name, body.web_url, body.mime_type,
                                                    body.size_bytes)


def delete_attachment_link(db: Db, ctx: RequestContext, link_id: int) -> None:
    projects_collab_repo.delete_attachment_link(db, ctx.company_id, ctx.user_id, link_id)


# --------------------------------------------------------------------------- time

def list_time_entries(db: Db, ctx: RequestContext, task_id: int) -> Rows:
    return projects_collab_repo.list_time_entries(db, ctx.company_id, ctx.user_id, task_id)


def save_time_entry(db: Db, ctx: RequestContext, entry_id: int | None, task_id: int | None, body: TimeEntryIn,
                    row_version: bytes | None) -> dict[str, Any]:
    if body.end_at is None and body.minutes is None:
        raise invalid("Enter the stop time or the time spent.", "endAt")
    return projects_collab_repo.save_time_entry(db, ctx.company_id, ctx.user_id, entry_id, task_id, body.employee_id,
                                                naive_utc(body.start_at), naive_utc(body.end_at), body.minutes,
                                                body.notes, row_version)


def delete_time_entry(db: Db, ctx: RequestContext, entry_id: int) -> None:
    projects_collab_repo.delete_time_entry(db, ctx.company_id, ctx.user_id, entry_id)


def start_timer(db: Db, ctx: RequestContext, task_id: int) -> dict[str, Any]:
    return projects_collab_repo.start_timer(db, ctx.company_id, ctx.user_id, task_id)


def stop_timer(db: Db, ctx: RequestContext, notes: str | None) -> dict[str, Any]:
    return projects_collab_repo.stop_timer(db, ctx.company_id, ctx.user_id, notes)


# --------------------------------------------------------------------------- reminders

def list_reminders(db: Db, ctx: RequestContext, entity_type: str | None, entity_id: int | None, include_done: bool,
                   page: int, page_size: int) -> tuple[int, Rows]:
    return projects_collab_repo.list_reminders(db, ctx.company_id, ctx.user_id, entity_type, entity_id, include_done,
                                               page, page_size)


def save_reminder(db: Db, ctx: RequestContext, reminder_id: int | None, body: ReminderIn,
                  row_version: bytes | None) -> dict[str, Any]:
    values = {"entity_type": body.entity_type, "entity_id": body.entity_id, "name": body.name,
              "remind_at": naive_utc(body.remind_at), "assignee_id": body.assignee_id,
              "notify_before_minutes": body.notify_before_minutes, "reminder_kind": body.reminder_kind}
    return projects_collab_repo.save_reminder(db, ctx.company_id, ctx.user_id, reminder_id, values, row_version)


def delete_reminder(db: Db, ctx: RequestContext, reminder_id: int) -> None:
    projects_collab_repo.delete_reminder(db, ctx.company_id, ctx.user_id, reminder_id)


def deliver_due_reminders(db: Db, company_id: int | None = None, now: datetime | None = None) -> int:
    """Sends every due reminder to its person's inbox (type projects.reminder) and marks it sent; returns how
    many were sent. For a scheduler (the API worker or scripts/nightly.py, every few minutes). `now` is the
    company's wall-clock time; by default each company's own (reminders are entered in local time)."""
    return projects_collab_repo.deliver_due_reminders(db, company_id, now)


# --------------------------------------------------------------------------- sharing

def _share(link: Rows, members: Rows, entity_type: str, entity_id: int) -> dict[str, Any]:
    if not link:
        # Not shared yet: the defaults the dialog opens with.
        return {"id": None, "entity_type": entity_type, "entity_id": entity_id, "share_scope": "list", "token": None,
                "link": None, "is_public": False, "allow_open_tasks": True, "valid_from": None, "valid_to": None,
                "max_access": None, "access_count": 0, "properties": list(SHARE_PROPERTIES), "members": [],
                "row_version": None}
    out = dict(link[0])
    out["properties"] = _loads(out.get("properties")) or list(SHARE_PROPERTIES)
    out["link"] = f"/shared/{out['token']}"
    out["members"] = members
    return out


def get_share(db: Db, ctx: RequestContext, entity_type: str, entity_id: int) -> dict[str, Any]:
    link, members = projects_collab_repo.get_share(db, ctx.company_id, ctx.user_id, entity_type, entity_id)
    return _share(link, members, entity_type, entity_id)


def save_share(db: Db, ctx: RequestContext, body: ShareIn, row_version: bytes | None) -> dict[str, Any]:
    if body.valid_from and body.valid_to and body.valid_to <= body.valid_from:
        raise invalid("The link must expire after it begins.", "validTo")
    # Task Name & Status is always shown (BRD "Share Task Properties").
    properties = list(dict.fromkeys(["task_name_status", *(body.properties or SHARE_PROPERTIES)]))
    values = body.model_dump(by_alias=False, exclude={"properties", "members", "row_version"})
    values["valid_from"], values["valid_to"] = naive_utc(body.valid_from), naive_utc(body.valid_to)
    members = dumps([m.model_dump(by_alias=False) for m in body.members])
    link, rows = projects_collab_repo.save_share(db, ctx.company_id, ctx.user_id, values, secrets.token_urlsafe(24),
                                                 dumps(properties), members, row_version)
    return _share(link, rows, body.entity_type, body.entity_id)


def delete_share(db: Db, ctx: RequestContext, share_id: int) -> None:
    projects_collab_repo.delete_share(db, ctx.company_id, ctx.user_id, share_id)
