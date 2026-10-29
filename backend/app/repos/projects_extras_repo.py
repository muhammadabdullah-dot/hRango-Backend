"""Project management extras data access: Notepad, Personal List, recents, dashboards, overdue settings."""
from datetime import date
from typing import Any

from app.core.db import Db

Rows = list[dict[str, Any]]


# --------------------------------------------------------------------------- notepad

def list_notes(db: Db, company_id: int, actor_user_id: int, archived: bool, search: str | None, page: int,
               page_size: int) -> tuple[int, Rows]:
    total, rows = db.call_sets("pm.usp_note_list", company_id=company_id, actor_user_id=actor_user_id,
                               archived=archived, search=search, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_note(db: Db, company_id: int, actor_user_id: int, note_id: int) -> dict[str, Any]:
    _total, rows = db.call_sets("pm.usp_note_list", company_id=company_id, actor_user_id=actor_user_id, id=note_id)
    return rows[0]


def save_note(db: Db, company_id: int, actor_user_id: int, note_id: int | None, title: str,
              content_html: str | None, row_version: bytes | None) -> dict[str, Any]:
    _total, rows = db.call_sets("pm.usp_note_save", company_id=company_id, actor_user_id=actor_user_id, id=note_id,
                                title=title, content_html=content_html, row_version=row_version)
    return rows[0]


def archive_note(db: Db, company_id: int, actor_user_id: int, note_id: int, archived: bool,
                 row_version: bytes) -> dict[str, Any]:
    _total, rows = db.call_sets("pm.usp_note_archive", company_id=company_id, actor_user_id=actor_user_id, id=note_id,
                                archived=archived, row_version=row_version)
    return rows[0]


def delete_note(db: Db, company_id: int, actor_user_id: int, note_id: int, row_version: bytes) -> None:
    db.call("pm.usp_note_delete", company_id=company_id, actor_user_id=actor_user_id, id=note_id,
            row_version=row_version)


def note_history(db: Db, company_id: int, actor_user_id: int, note_id: int) -> Rows:
    return db.call("pm.usp_note_history", company_id=company_id, actor_user_id=actor_user_id, id=note_id)


def list_workspace(db: Db, company_id: int, actor_user_id: int, task_list_id: int) -> int:
    return db.call_one("pm.usp_note_convert_place", company_id=company_id, actor_user_id=actor_user_id,
                       task_list_id=task_list_id)["workspace_id"]


# --------------------------------------------------------------------------- personal list

def list_personal(db: Db, company_id: int, actor_user_id: int) -> Rows:
    return db.call("pm.usp_personal_item_list", company_id=company_id, actor_user_id=actor_user_id)


def add_personal(db: Db, company_id: int, actor_user_id: int, title: str, due_date: date | None) -> dict[str, Any]:
    return db.call_one("pm.usp_personal_item_add", company_id=company_id, actor_user_id=actor_user_id, title=title,
                       due_date=due_date)


def set_personal_done(db: Db, company_id: int, actor_user_id: int, item_id: int, done: bool,
                      row_version: bytes) -> dict[str, Any]:
    return db.call_one("pm.usp_personal_item_set_done", company_id=company_id, actor_user_id=actor_user_id,
                       id=item_id, is_done=done, row_version=row_version)


def delete_personal(db: Db, company_id: int, actor_user_id: int, item_id: int, row_version: bytes) -> None:
    db.call("pm.usp_personal_item_delete", company_id=company_id, actor_user_id=actor_user_id, id=item_id,
            row_version=row_version)


# --------------------------------------------------------------------------- recents

def record_recent(db: Db, company_id: int, actor_user_id: int, entity_type: str, entity_id: int) -> None:
    db.call("pm.usp_recent_record", company_id=company_id, actor_user_id=actor_user_id, entity_type=entity_type,
            entity_id=entity_id)


def list_recents(db: Db, company_id: int, actor_user_id: int, workspace_id: int | None, folder_id: int | None,
                 limit: int) -> Rows:
    return db.call("pm.usp_recent_list", company_id=company_id, actor_user_id=actor_user_id,
                   workspace_id=workspace_id, folder_id=folder_id, limit=limit)


# --------------------------------------------------------------------------- dashboards

def home_dashboard(db: Db, company_id: int, actor_user_id: int) -> list[Rows]:
    return db.call_sets("pm.usp_dashboard_home", company_id=company_id, actor_user_id=actor_user_id)


def scope_dashboard(db: Db, company_id: int, actor_user_id: int, workspace_id: int | None,
                    folder_id: int | None) -> list[Rows]:
    return db.call_sets("pm.usp_dashboard_scope", company_id=company_id, actor_user_id=actor_user_id,
                        workspace_id=workspace_id, folder_id=folder_id)


# --------------------------------------------------------------------------- overdue settings

def get_overdue_settings(db: Db, company_id: int, actor_user_id: int, workspace_id: int) -> dict[str, Any]:
    return db.call_one("pm.usp_workspace_overdue_setting_get", company_id=company_id, actor_user_id=actor_user_id,
                       workspace_id=workspace_id)


def save_overdue_settings(db: Db, company_id: int, actor_user_id: int, workspace_id: int, penalty_percent: float,
                          max_extensions: int, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_workspace_overdue_setting_save", company_id=company_id, actor_user_id=actor_user_id,
                       workspace_id=workspace_id, penalty_percent=penalty_percent, max_extensions=max_extensions,
                       row_version=row_version)
