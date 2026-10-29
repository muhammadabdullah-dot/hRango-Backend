"""Project management extras: Notepad (T3), overdue settings (T5), recents and dashboards (T7), Personal
List (T11). Notes, the Personal List and recents are the caller's own (per sign-in); the procedures
filter on the caller. Access to workspaces, tasks and docs is decided in the pm procedures."""
from collections import defaultdict
from decimal import Decimal
from typing import Any

from app.core.db import Db
from app.core.errors import forbidden
from app.middlewares.auth import RequestContext
from app.repos import auth_repo, projects_docs_repo, projects_extras_repo, projects_tasks_repo
from app.schemas.projects_extras import NoteConvertIn, NoteIn
from app.services.projects_collab_service import shape_comment
from app.services.projects_docs_service import counts, text_of
from app.services.projects_service import dumps
from app.services.projects_tasks_service import hidden_columns, shape_task

Rows = list[dict[str, Any]]


def _require(db: Db, ctx: RequestContext, code: str) -> None:
    """A second permission an action needs besides the one its route checked."""
    row = auth_repo.permission_check(db, ctx.company_id, ctx.user_id, code)
    if not row or not row["allowed"]:
        raise forbidden()


# --------------------------------------------------------------------------- notepad

def list_notes(db: Db, ctx: RequestContext, archived: bool, q: str | None, page: int,
               page_size: int) -> tuple[int, Rows]:
    return projects_extras_repo.list_notes(db, ctx.company_id, ctx.user_id, archived, q, page, page_size)


def save_note(db: Db, ctx: RequestContext, note_id: int | None, body: NoteIn,
              row_version: bytes | None) -> dict[str, Any]:
    return projects_extras_repo.save_note(db, ctx.company_id, ctx.user_id, note_id, body.title.strip(),
                                          body.content_html, row_version)


def archive_note(db: Db, ctx: RequestContext, note_id: int, archived: bool, row_version: bytes) -> dict[str, Any]:
    return projects_extras_repo.archive_note(db, ctx.company_id, ctx.user_id, note_id, archived, row_version)


def delete_note(db: Db, ctx: RequestContext, note_id: int, row_version: bytes) -> None:
    projects_extras_repo.delete_note(db, ctx.company_id, ctx.user_id, note_id, row_version)


def note_history(db: Db, ctx: RequestContext, note_id: int) -> Rows:
    return projects_extras_repo.note_history(db, ctx.company_id, ctx.user_id, note_id)


def convert_note(db: Db, ctx: RequestContext, note_id: int, body: NoteConvertIn) -> dict[str, Any]:
    """Makes a task (name = title, description = the note's text) or a doc (title and HTML) from a note, then
    deletes, archives or keeps the note, in one transaction. The task / doc procedures check the workspace
    role (team leaders and above add tasks; members add docs)."""
    _require(db, ctx, "projects.tasks.create" if body.to == "task" else "projects.docs.create")
    note = projects_extras_repo.get_note(db, ctx.company_id, ctx.user_id, note_id)
    workspace_id = body.workspace_id
    if body.list_id is not None:
        workspace_id = projects_extras_repo.list_workspace(db, ctx.company_id, ctx.user_id, body.list_id)
    out: dict[str, Any] = {}
    with db.transaction():
        if body.to == "task":
            text = text_of(note["content_html"])
            values = {"workspace_id": workspace_id, "task_list_id": body.list_id, "name": note["title"][:200],
                      "description": text[:5000] or None, "assignee_ids": "[]", "tag_ids": "[]"}
            sets = projects_tasks_repo.save_task(db, ctx.company_id, ctx.user_id, None, values, None)
            out["task_id"] = sets[0][0]["id"]
        else:
            words, characters = counts(note["content_html"])
            values = {"title": note["title"][:50], "content": dumps({}), "content_html": note["content_html"] or "",
                      "visibility": "workspace", "folder_id": None, "task_list_id": body.list_id,
                      "cover_file_id": None, "settings": None, "word_count": words, "character_count": characters}
            _total, docs, _c, _l = projects_docs_repo.save_doc(db, ctx.company_id, ctx.user_id, None, workspace_id,
                                                               values, None)
            out["doc_id"] = docs[0]["id"]
        if body.original == "delete":
            projects_extras_repo.delete_note(db, ctx.company_id, ctx.user_id, note_id, note["row_version"])
        elif body.original == "archive":
            projects_extras_repo.archive_note(db, ctx.company_id, ctx.user_id, note_id, True, note["row_version"])
    return out


# --------------------------------------------------------------------------- personal list

def list_personal(db: Db, ctx: RequestContext) -> Rows:
    return projects_extras_repo.list_personal(db, ctx.company_id, ctx.user_id)


def add_personal(db: Db, ctx: RequestContext, title: str, due_date) -> dict[str, Any]:
    return projects_extras_repo.add_personal(db, ctx.company_id, ctx.user_id, title.strip(), due_date)


def set_personal_done(db: Db, ctx: RequestContext, item_id: int, done: bool, row_version: bytes) -> dict[str, Any]:
    return projects_extras_repo.set_personal_done(db, ctx.company_id, ctx.user_id, item_id, done, row_version)


def delete_personal(db: Db, ctx: RequestContext, item_id: int, row_version: bytes) -> None:
    projects_extras_repo.delete_personal(db, ctx.company_id, ctx.user_id, item_id, row_version)


# --------------------------------------------------------------------------- recents

def record_recent(db: Db, ctx: RequestContext, entity_type: str, entity_id: int) -> None:
    projects_extras_repo.record_recent(db, ctx.company_id, ctx.user_id, entity_type, entity_id)


def list_recents(db: Db, ctx: RequestContext, workspace_id: int | None, folder_id: int | None, limit: int) -> Rows:
    return projects_extras_repo.list_recents(db, ctx.company_id, ctx.user_id, workspace_id, folder_id, limit)


# --------------------------------------------------------------------------- dashboards

def home_dashboard(db: Db, ctx: RequestContext) -> dict[str, Any]:
    recents, agenda, my_work, levels, comments, activity = projects_extras_repo.home_dashboard(db, ctx.company_id,
                                                                                               ctx.user_id)
    by_workspace: dict[int, Rows] = defaultdict(list)
    for level in levels:
        by_workspace[level["workspace_id"]].append(level)
    return {
        "recents": [{"type": r["entity_type"], "id": r["entity_id"], "name": r["name"],
                     "workspace_id": r["workspace_id"], "opened_at": r["opened_at"]} for r in recents],
        "agenda": agenda,
        "my_work": [shape_task(r, hidden_columns(by_workspace[r["workspace_id"]])) for r in my_work],
        "assigned_comments": [shape_comment(c) for c in comments],
        "activity": activity,
    }


def scope_dashboard(db: Db, ctx: RequestContext, workspace_id: int | None, folder_id: int | None) -> dict[str, Any]:
    by_status, by_assignee, figures, docs, bookmarks, resources = projects_extras_repo.scope_dashboard(
        db, ctx.company_id, ctx.user_id, workspace_id, folder_id)
    return {"by_status": by_status, "by_assignee": by_assignee, **figures[0], "recent_docs": docs,
            "bookmarks": bookmarks, "resources": resources}


# --------------------------------------------------------------------------- overdue settings

def get_overdue_settings(db: Db, ctx: RequestContext, workspace_id: int) -> dict[str, Any]:
    return projects_extras_repo.get_overdue_settings(db, ctx.company_id, ctx.user_id, workspace_id)


def save_overdue_settings(db: Db, ctx: RequestContext, workspace_id: int, penalty_percent: float, max_extensions: int,
                          row_version: bytes | None) -> dict[str, Any]:
    return projects_extras_repo.save_overdue_settings(db, ctx.company_id, ctx.user_id, workspace_id,
                                                      Decimal(str(round(penalty_percent, 2))), max_extensions,
                                                      row_version)
