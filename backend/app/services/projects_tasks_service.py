"""Project management task rules. Workspace roles, column permissions, dependencies, WIP limits and
organizer features are enforced in the pm procedures. Here: JSON shapes, the List view filters, and
hiding the columns a person may not see (Private Field)."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.middlewares.auth import RequestContext
from app.repos import projects_tasks_repo
from app.schemas.projects_tasks import (AssigneeIn, ChecklistItemIn, MoveIn, TaskCreateIn, TaskFieldsIn)
from app.services.projects_service import dumps

Rows = list[dict[str, Any]]

# Row fields behind each List view column, blanked when the column is a Private Field for the caller.
COLUMN_FIELDS: dict[str, tuple[str, ...]] = {
    "assignees": ("assignees",),
    "start_date": ("start_date", "start_time"),
    "due_date": ("due_date", "due_time", "original_due_date", "is_overdue", "recurrence"),
    "priority": ("priority",),
    "tags": ("tags",),
    "dependencies": ("open_dependency_count", "blocking_count", "dependencies"),
    "time_estimate": ("time_estimate_minutes",),
    "time_tracked": ("time_tracked_minutes",),
    "task_id": ("code",),
    "created_by": ("created_by_user_id", "created_by_name"),
    "date_created": ("created_at",),
    "date_closed": ("closed_at",),
    "latest_comment": ("latest_comment",),
    "story_points": ("story_points_total", "rating"),
    "files": ("attachment_count",),
}
LIST_FIELDS = ("assignees", "tags", "dependencies")


def _loads(text: str | None) -> Any:
    return json.loads(text) if text else None


def hidden_columns(levels: Rows) -> list[str]:
    return sorted(r["column_key"] for r in levels if r["permission_level"] == "private")


def shape_task(row: dict[str, Any], hidden: list[str]) -> dict[str, Any]:
    """Turns a task row's JSON columns into lists and blanks the hidden columns."""
    out = dict(row)
    out["assignees"] = _loads(out.pop("assignees_json", None)) or []
    out["tags"] = _loads(out.pop("tags_json", None)) or []
    out["field_values"] = _loads(out.pop("field_values_json", None)) or []
    out["recurrence"] = _loads(out.get("recurrence"))
    body, author, at = out.pop("latest_comment_body", None), out.pop("latest_comment_author", None), \
        out.pop("latest_comment_at", None)
    out["latest_comment"] = {"body": body, "author_name": author, "created_at": at} if body is not None else None
    for key in hidden:
        if key.startswith("cf_"):
            out["field_values"] = [v for v in out["field_values"] if f"cf_{v['custom_field_id']}" != key]
        for name in COLUMN_FIELDS.get(key, ()):
            if name in out:
                out[name] = [] if name in LIST_FIELDS else None
    if "story_points" in hidden:
        for a in out["assignees"]:
            a["story_points"] = None
    return out


def _task_values(body: TaskFieldsIn) -> dict[str, Any]:
    return {"name": body.name, "description": body.description, "task_type": body.task_type, "priority": body.priority,
            "start_date": body.start_date, "start_time": body.start_time, "due_date": body.due_date,
            "due_time": body.due_time, "time_estimate_minutes": body.time_estimate_minutes, "rating": body.rating,
            "url": body.url,
            "recurrence": dumps(body.recurrence.model_dump(by_alias=True)) if body.recurrence else None}


def _csv(values: list[Any] | None) -> str | None:
    return ",".join(str(v) for v in values) if values else None


def list_tasks(db: Db, ctx: RequestContext, workspace_id: int, f: dict[str, Any], page: int,
               page_size: int) -> tuple[int, Rows, Rows, list[str]]:
    filters = {
        "task_list_id": f.get("task_list_id"), "search": f.get("q"), "status_ids": _csv(f.get("status_ids")),
        "status_groups": _csv(f.get("status_groups")), "include_closed": f.get("include_closed", True),
        "priorities": _csv(f.get("priorities")), "assignee_ids": _csv(f.get("assignee_ids")),
        "include_unassigned": f.get("include_unassigned", False), "tag_ids": _csv(f.get("tag_ids")),
        "created_by_ids": _csv(f.get("created_by_ids")), "task_type": f.get("task_type"),
        "due_from": f.get("due_from"), "due_to": f.get("due_to"), "start_from": f.get("start_from"),
        "start_to": f.get("start_to"), "overdue_only": f.get("overdue_only", False),
        "subtasks": f.get("subtasks", "expanded"), "group_by": f.get("group_by", "status"),
        "sort_by": f.get("sort_by", "manual"), "sort_dir": f.get("sort_dir", "asc"),
    }
    total, rows, groups, levels = projects_tasks_repo.list_tasks(db, ctx.company_id, ctx.user_id, workspace_id,
                                                                 filters, page, page_size)
    hidden = hidden_columns(levels)
    return total, [shape_task(r, hidden) for r in rows], groups, hidden


def _detail(sets: list[Rows]) -> dict[str, Any]:
    task, dependencies, checklist, subtasks, extensions, levels = sets
    hidden = hidden_columns(levels)
    out = shape_task(task[0], hidden)
    out.update(dependencies=[] if "dependencies" in hidden else dependencies, checklist=checklist, subtasks=subtasks,
               extensions=extensions, hidden_columns=hidden)
    return out


def get_task(db: Db, ctx: RequestContext, task_id: int) -> dict[str, Any]:
    return _detail(projects_tasks_repo.get_task(db, ctx.company_id, ctx.user_id, task_id))


def create_task(db: Db, ctx: RequestContext, body: TaskCreateIn) -> dict[str, Any]:
    values = _task_values(body)
    values.update(workspace_id=body.workspace_id, task_list_id=body.task_list_id, parent_task_id=body.parent_task_id,
                  status_id=body.status_id, assignee_ids=dumps(body.assignee_ids), tag_ids=dumps(body.tag_ids))
    return _detail(projects_tasks_repo.save_task(db, ctx.company_id, ctx.user_id, None, values, None))


def update_task(db: Db, ctx: RequestContext, task_id: int, body: TaskFieldsIn, row_version: bytes) -> dict[str, Any]:
    return _detail(projects_tasks_repo.save_task(db, ctx.company_id, ctx.user_id, task_id, _task_values(body),
                                                 row_version))


def set_status(db: Db, ctx: RequestContext, task_id: int, status_id: int, row_version: bytes) -> dict[str, Any]:
    return _detail(projects_tasks_repo.set_status(db, ctx.company_id, ctx.user_id, task_id, status_id, row_version))


def set_cover(db: Db, ctx: RequestContext, task_id: int, file_id: int | None, row_version: bytes) -> dict[str, Any]:
    return _detail(projects_tasks_repo.set_cover(db, ctx.company_id, ctx.user_id, task_id, file_id, row_version))


def save_assignees(db: Db, ctx: RequestContext, task_id: int, assignees: list[AssigneeIn]) -> dict[str, Any]:
    payload = dumps([a.model_dump(by_alias=False) for a in assignees])
    return _detail(projects_tasks_repo.save_assignees(db, ctx.company_id, ctx.user_id, task_id, payload))


def save_tags(db: Db, ctx: RequestContext, task_id: int, tag_ids: list[int]) -> dict[str, Any]:
    return _detail(projects_tasks_repo.save_tags(db, ctx.company_id, ctx.user_id, task_id, dumps(tag_ids)))


def move_task(db: Db, ctx: RequestContext, task_id: int, body: MoveIn, row_version: bytes) -> dict[str, Any]:
    return _detail(projects_tasks_repo.move_task(db, ctx.company_id, ctx.user_id, task_id, body.workspace_id,
                                                 body.task_list_id, body.parent_task_id, body.sort_order, row_version))


def convert_to_list(db: Db, ctx: RequestContext, task_id: int, row_version: bytes) -> dict[str, Any]:
    return projects_tasks_repo.convert_to_list(db, ctx.company_id, ctx.user_id, task_id, row_version)


def delete_task(db: Db, ctx: RequestContext, task_id: int, row_version: bytes) -> None:
    projects_tasks_repo.delete_task(db, ctx.company_id, ctx.user_id, task_id, row_version)


def field_value_text(value: Any) -> str | None:
    """Custom field values are stored as text: true / false, numbers, JSON arrays for labels and people."""
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return json.dumps(value)
    return str(value)


def save_field_value(db: Db, ctx: RequestContext, task_id: int, field_id: int, value: Any) -> dict[str, Any]:
    return _detail(projects_tasks_repo.save_field_value(db, ctx.company_id, ctx.user_id, task_id, field_id,
                                                        field_value_text(value)))


def add_dependency(db: Db, ctx: RequestContext, task_id: int, other_task_id: int, kind: str) -> dict[str, Any]:
    return _detail(projects_tasks_repo.add_dependency(db, ctx.company_id, ctx.user_id, task_id, other_task_id, kind))


def delete_dependency(db: Db, ctx: RequestContext, dependency_id: int) -> None:
    projects_tasks_repo.delete_dependency(db, ctx.company_id, ctx.user_id, dependency_id)


def save_checklist_item(db: Db, ctx: RequestContext, item_id: int | None, task_id: int | None, body: ChecklistItemIn,
                        row_version: bytes | None) -> dict[str, Any]:
    return projects_tasks_repo.save_checklist_item(db, ctx.company_id, ctx.user_id, item_id, task_id, body.item_text,
                                                   body.is_done, body.sort_order, row_version)


def delete_checklist_item(db: Db, ctx: RequestContext, item_id: int) -> None:
    projects_tasks_repo.delete_checklist_item(db, ctx.company_id, ctx.user_id, item_id)


def task_activity(db: Db, ctx: RequestContext, task_id: int, page: int, page_size: int) -> tuple[int, Rows]:
    return projects_tasks_repo.task_activity(db, ctx.company_id, ctx.user_id, task_id, page, page_size)


def request_extension(db: Db, ctx: RequestContext, task_id: int, new_due_date: date, reason: str) -> dict[str, Any]:
    return _detail(projects_tasks_repo.request_extension(db, ctx.company_id, ctx.user_id, task_id, new_due_date, reason))


def decide_extension(db: Db, ctx: RequestContext, extension_id: int, approve: bool, remarks: str | None,
                     row_version: bytes) -> dict[str, Any]:
    return _detail(projects_tasks_repo.decide_extension(db, ctx.company_id, ctx.user_id, extension_id, approve, remarks,
                                                        row_version))
