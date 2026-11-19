"""Public share links (Backend Dependencies T6). A link opens without signing in when "Share link with
anyone" is on; the procedures enforce its validity period and access limit (each page or task opened
counts one access). Here: the answers for a refused link and keeping only the properties it shows.

TODO(pm): rate-limit by client address; a password option; sending invitations to ShareIn.members emails."""
import json
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.core.files import file_url
from app.repos import public_repo
from app.schemas.projects_collab import SHARE_PROPERTIES

Rows = list[dict[str, Any]]
# share_link.entity_type -> what the page shows.
ENTITY = {"task": "task", "task_list": "list", "workspace": "view"}
# A link saved without properties shows everything, as the sharing dialog says (pm.fn_share_tasks agrees).
DEFAULT_PROPERTIES = list(SHARE_PROPERTIES)


def _refuse(state: str) -> AppError:
    if state == "not_started":
        return AppError(410, "SHARE_NOT_STARTED", "This link is not active yet.")
    if state == "expired":
        return AppError(410, "SHARE_EXPIRED", "This link has expired.")
    if state == "exhausted":
        return AppError(410, "SHARE_EXHAUSTED", "This link has been opened as many times as allowed.")
    if state == "tasks_closed":
        return AppError(403, "SHARE_TASKS_CLOSED", "This link does not open tasks.")
    if state == "task_not_found":
        return AppError(404, "NOT_FOUND", "Task not found.")
    return AppError(404, "SHARE_NOT_FOUND", "This link does not exist or is no longer shared.")


def _header(sets: list[Rows]) -> dict[str, Any]:
    head = sets[0][0]
    if head["state"] != "ok":
        raise _refuse(head["state"])
    props = json.loads(head["properties"]) if head.get("properties") else DEFAULT_PROPERTIES
    return {**head, "properties": props}


def _row(t: dict[str, Any], props: set[str]) -> dict[str, Any]:
    return {"id": t["id"], "parent_task_id": t["parent_task_id"], "code": t["code"], "name": t["name"],
            "status_name": t["status_name"], "status_color": t["status_color"], "status_group": t["status_group"],
            "priority": t["priority"] if "priority" in props else None,
            "due_date": t["due_date"] if "due_date" in props else None,
            "assignees": [a["name"] for a in json.loads(t["assignees_json"] or "[]")] if "assignee" in props else None,
            "tags": json.loads(t["tags_json"] or "[]") if "tags" in props else None}


def open_share(db: Db, token: str) -> dict[str, Any]:
    sets = public_repo.open_share(db, token)
    head = _header(sets)
    props = set(head["properties"])
    # A shared task comes with its own details (sets 3 to 8): they are what the link shares.
    task = _detail(sets[2:], props, head["company_id"]) if head["entity_type"] == "task" and len(sets) >= 8 else None
    return {"entity_type": ENTITY.get(head["entity_type"], head["entity_type"]), "title": head["title"],
            "allow_open_tasks": bool(head["allow_open_tasks"]), "properties": head["properties"],
            "tasks": [_row(t, props) for t in sets[1]], "task": task}


def share_task(db: Db, token: str, task_id: int) -> dict[str, Any]:
    sets = public_repo.share_task(db, token, task_id)
    head = _header(sets)
    return _detail(sets[1:], set(head["properties"]), head["company_id"])


def _detail(sets: list[Rows], props: set[str], company_id: int) -> dict[str, Any]:
    """One task from pm.usp_public_share_task_sets: the task, subtasks, checklist, comments, attachments, fields,
    each kept only when the link shows it."""
    task = sets[0][0]
    subtasks, checklist, comments, attachments, fields = sets[1:6]
    out = _row(task, props)
    out["start_date"] = task["start_date"] if "due_date" in props else None
    out["description"] = task["description"] if "description" in props else None
    out["cover_url"] = (file_url(task["cover_file_id"], company_id)
                        if "cover_image" in props and task["cover_file_id"] else None)
    out["subtasks"] = subtasks if "subtasks" in props else None
    out["checklist"] = checklist if "checklists" in props else None
    out["comments"] = comments if "comments" in props else None
    out["attachments"] = ([{**a, "url": file_url(a["file_id"], company_id) if a["file_id"] else a["web_url"]}
                           for a in attachments] if "attachments" in props else None)
    out["custom_fields"] = ([{"name": f["name"], "field_type": f["field_type"], "value": f["field_value"]}
                             for f in fields] if "custom_fields" in props else None)
    return out
