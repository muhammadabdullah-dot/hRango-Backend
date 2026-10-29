"""HTTP shape for project management extras: Notepad, Personal List, recents, dashboards, overdue settings."""
from datetime import date
from typing import Any

from app.controllers.projects_controller import to_model
from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.projects_collab import CommentOut
from app.schemas.projects_extras import (HomeDashboardOut, NoteArchiveIn, NoteConvertedOut, NoteConvertIn, NoteIn,
                                         NoteOut, NoteVersionOut, OverdueSettingsIn, OverdueSettingsOut,
                                         PersonalItemOut, RecentOut, ScopeDashboardOut)
from app.schemas.projects_tasks import TaskRowOut
from app.services import projects_extras_service as s


# --------------------------------------------------------------------------- notepad

def list_notes(db: Db, ctx: RequestContext, archived: bool, q: str | None, paging: PageParams) -> dict:
    total, rows = s.list_notes(db, ctx, archived, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: to_model(NoteOut, r))


def create_note(db: Db, ctx: RequestContext, body: NoteIn) -> dict:
    return {"data": to_model(NoteOut, s.save_note(db, ctx, None, body, None))}


def update_note(db: Db, ctx: RequestContext, note_id: int, body: NoteIn) -> dict:
    return {"data": to_model(NoteOut, s.save_note(db, ctx, note_id, body, row_version_in(body.row_version)))}


def archive_note(db: Db, ctx: RequestContext, note_id: int, body: NoteArchiveIn) -> dict:
    row = s.archive_note(db, ctx, note_id, body.archived, row_version_in(body.row_version))
    return {"data": to_model(NoteOut, row)}


def delete_note(db: Db, ctx: RequestContext, note_id: int, row_version: str | None) -> None:
    s.delete_note(db, ctx, note_id, row_version_in(row_version))


def note_history(db: Db, ctx: RequestContext, note_id: int) -> dict:
    return {"data": [NoteVersionOut(**r) for r in s.note_history(db, ctx, note_id)]}


def convert_note(db: Db, ctx: RequestContext, note_id: int, body: NoteConvertIn) -> dict:
    return {"data": NoteConvertedOut(**s.convert_note(db, ctx, note_id, body))}


# --------------------------------------------------------------------------- personal list

def list_personal(db: Db, ctx: RequestContext) -> dict:
    return {"data": [to_model(PersonalItemOut, r) for r in s.list_personal(db, ctx)]}


def add_personal(db: Db, ctx: RequestContext, title: str, due_date: date | None) -> dict:
    return {"data": to_model(PersonalItemOut, s.add_personal(db, ctx, title, due_date))}


def set_personal_done(db: Db, ctx: RequestContext, item_id: int, done: bool, row_version: str | None) -> dict:
    return {"data": to_model(PersonalItemOut, s.set_personal_done(db, ctx, item_id, done, row_version_in(row_version)))}


def delete_personal(db: Db, ctx: RequestContext, item_id: int, row_version: str | None) -> None:
    s.delete_personal(db, ctx, item_id, row_version_in(row_version))


# --------------------------------------------------------------------------- recents

def record_recent(db: Db, ctx: RequestContext, entity_type: str, entity_id: int) -> None:
    s.record_recent(db, ctx, entity_type, entity_id)


def list_recents(db: Db, ctx: RequestContext, workspace_id: int | None, folder_id: int | None, limit: int) -> dict:
    return {"data": [RecentOut(**r) for r in s.list_recents(db, ctx, workspace_id, folder_id, limit)]}


# --------------------------------------------------------------------------- dashboards

def home_dashboard(db: Db, ctx: RequestContext) -> dict:
    out = s.home_dashboard(db, ctx)
    out["my_work"] = [to_model(TaskRowOut, r, ctx.company_id) for r in out["my_work"]]
    out["assigned_comments"] = [to_model(CommentOut, c) for c in out["assigned_comments"]]
    return {"data": HomeDashboardOut(**out)}


def _resource(row: dict[str, Any], company_id: int) -> dict[str, Any]:
    url = file_url(row["file_id"], company_id) if row.get("file_id") is not None else row.get("web_url")
    return {**row, "url": url}


def scope_dashboard(db: Db, ctx: RequestContext, workspace_id: int | None, folder_id: int | None) -> dict:
    out = s.scope_dashboard(db, ctx, workspace_id, folder_id)
    out["resources"] = [_resource(r, ctx.company_id) for r in out["resources"]]
    return {"data": ScopeDashboardOut(**out)}


# --------------------------------------------------------------------------- overdue settings

def get_overdue_settings(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    return {"data": to_model(OverdueSettingsOut, s.get_overdue_settings(db, ctx, workspace_id))}


def save_overdue_settings(db: Db, ctx: RequestContext, workspace_id: int, body: OverdueSettingsIn) -> dict:
    row = s.save_overdue_settings(db, ctx, workspace_id, body.penalty_percent, body.max_extensions,
                                  row_version_in(body.row_version, required=False))
    return {"data": to_model(OverdueSettingsOut, row)}
