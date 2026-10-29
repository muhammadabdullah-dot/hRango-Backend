"""HTTP shape for project management collaboration: comments, attachments, time, reminders, sharing."""
from typing import Any

from app.controllers.projects_controller import to_model
from app.core.db import Db
from app.core.errors import not_found
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.projects_collab import (AttachmentIn, AttachmentLinkIn, AttachmentOut, CommentEditIn, CommentIn,
                                         CommentOut, ReminderIn, ReminderOut, ShareIn, ShareOut, TimeEntryIn,
                                         TimeEntryOut)
from app.services import projects_collab_service


# --------------------------------------------------------------------------- comments

def list_comments(db: Db, ctx: RequestContext, task_id: int) -> dict:
    return {"data": [to_model(CommentOut, r) for r in projects_collab_service.list_comments(db, ctx, task_id)]}


def add_comment(db: Db, ctx: RequestContext, task_id: int, body: CommentIn) -> dict:
    return {"data": to_model(CommentOut, projects_collab_service.add_comment(db, ctx, task_id, body))}


def edit_comment(db: Db, ctx: RequestContext, comment_id: int, body: CommentEditIn) -> dict:
    row = projects_collab_service.edit_comment(db, ctx, comment_id, body, row_version_in(body.row_version))
    return {"data": to_model(CommentOut, row)}


def assign_comment(db: Db, ctx: RequestContext, comment_id: int, assigned_to_id: int | None) -> dict:
    return {"data": to_model(CommentOut, projects_collab_service.assign_comment(db, ctx, comment_id, assigned_to_id))}


def resolve_comment(db: Db, ctx: RequestContext, comment_id: int, resolved: bool) -> dict:
    return {"data": to_model(CommentOut, projects_collab_service.resolve_comment(db, ctx, comment_id, resolved))}


def react_comment(db: Db, ctx: RequestContext, comment_id: int, reaction: str | None) -> dict:
    return {"data": to_model(CommentOut, projects_collab_service.react_comment(db, ctx, comment_id, reaction))}


def delete_comment(db: Db, ctx: RequestContext, comment_id: int, row_version: str | None) -> None:
    projects_collab_service.delete_comment(db, ctx, comment_id, row_version_in(row_version))


# --------------------------------------------------------------------------- attachments

def _attachment(row: dict, company_id: int) -> AttachmentOut:
    url = file_url(row["file_id"], company_id) if row.get("file_id") is not None else row.get("web_url")
    return AttachmentOut(**row, url=url)


def list_attachments(db: Db, ctx: RequestContext, task_id: int) -> dict:
    rows = projects_collab_service.list_attachments(db, ctx, task_id)
    return {"data": [_attachment(r, ctx.company_id) for r in rows]}


def add_attachment(db: Db, ctx: RequestContext, task_id: int, body: AttachmentIn) -> dict:
    return {"data": _attachment(projects_collab_service.add_attachment(db, ctx, task_id, body), ctx.company_id)}


def add_attachment_link(db: Db, ctx: RequestContext, task_id: int, body: AttachmentLinkIn) -> dict:
    return {"data": _attachment(projects_collab_service.add_attachment_link(db, ctx, task_id, body), ctx.company_id)}


def delete_attachment(db: Db, ctx: RequestContext, attachment_id: str) -> None:
    """An uploaded file's attachment id is a number; a link to external storage is "link-<n>"."""
    link = attachment_id.startswith("link-")
    number = attachment_id[5:] if link else attachment_id
    if not number.isdigit():
        raise not_found("Attachment")
    if link:
        projects_collab_service.delete_attachment_link(db, ctx, int(number))
    else:
        projects_collab_service.delete_attachment(db, ctx, int(number))


# --------------------------------------------------------------------------- time

def list_time_entries(db: Db, ctx: RequestContext, task_id: int) -> dict:
    return {"data": [to_model(TimeEntryOut, r) for r in projects_collab_service.list_time_entries(db, ctx, task_id)]}


def add_time_entry(db: Db, ctx: RequestContext, task_id: int, body: TimeEntryIn) -> dict:
    return {"data": to_model(TimeEntryOut, projects_collab_service.save_time_entry(db, ctx, None, task_id, body, None))}


def update_time_entry(db: Db, ctx: RequestContext, entry_id: int, body: TimeEntryIn) -> dict:
    row = projects_collab_service.save_time_entry(db, ctx, entry_id, None, body, row_version_in(body.row_version))
    return {"data": to_model(TimeEntryOut, row)}


def delete_time_entry(db: Db, ctx: RequestContext, entry_id: int) -> None:
    projects_collab_service.delete_time_entry(db, ctx, entry_id)


def start_timer(db: Db, ctx: RequestContext, task_id: int) -> dict:
    return {"data": to_model(TimeEntryOut, projects_collab_service.start_timer(db, ctx, task_id))}


def stop_timer(db: Db, ctx: RequestContext, notes: str | None) -> dict:
    return {"data": to_model(TimeEntryOut, projects_collab_service.stop_timer(db, ctx, notes))}


# --------------------------------------------------------------------------- reminders

def list_reminders(db: Db, ctx: RequestContext, entity_type: str | None, entity_id: int | None, include_done: bool,
                   paging: PageParams) -> dict:
    total, rows = projects_collab_service.list_reminders(db, ctx, entity_type, entity_id, include_done, paging.page,
                                                         paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: to_model(ReminderOut, r))


def create_reminder(db: Db, ctx: RequestContext, body: ReminderIn) -> dict:
    return {"data": to_model(ReminderOut, projects_collab_service.save_reminder(db, ctx, None, body, None))}


def update_reminder(db: Db, ctx: RequestContext, reminder_id: int, body: ReminderIn) -> dict:
    row = projects_collab_service.save_reminder(db, ctx, reminder_id, body, row_version_in(body.row_version))
    return {"data": to_model(ReminderOut, row)}


def delete_reminder(db: Db, ctx: RequestContext, reminder_id: int) -> None:
    projects_collab_service.delete_reminder(db, ctx, reminder_id)


# --------------------------------------------------------------------------- sharing

def _share(row: dict[str, Any]) -> dict:
    return {"data": ShareOut(**{**row, "row_version": row_version_out(row["row_version"])})}


def get_share(db: Db, ctx: RequestContext, entity_type: str, entity_id: int) -> dict:
    return _share(projects_collab_service.get_share(db, ctx, entity_type, entity_id))


def save_share(db: Db, ctx: RequestContext, body: ShareIn) -> dict:
    return _share(projects_collab_service.save_share(db, ctx, body, row_version_in(body.row_version, required=False)))


def delete_share(db: Db, ctx: RequestContext, share_id: int) -> None:
    projects_collab_service.delete_share(db, ctx, share_id)
