"""HTTP shape for project management tasks: the List view page, the task screen and task edits."""
from typing import Any

from app.controllers.projects_controller import to_model
from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import PageMeta, paginated
from app.schemas.projects import ActivityOut, CoverIn
from app.schemas.projects_tasks import (AssigneesIn, ChecklistItemIn, ChecklistItemOut, ConvertedOut, DependencyIn,
                                        ExtensionDecisionIn, ExtensionRequestIn, MoveIn, StatusChangeIn, TaskCreateIn,
                                        TaskIn, TaskOut, TaskPage, TaskRowOut, TaskTagsIn)
from app.services import projects_tasks_service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _task(row: dict[str, Any], company_id: int) -> dict:
    return {"data": to_model(TaskOut, {**row, "extensions": [_rv(e) for e in row["extensions"]],
                                       "checklist": [_rv(c) for c in row["checklist"]]}, company_id)}


def list_tasks(db: Db, ctx: RequestContext, workspace_id: int, filters: dict[str, Any], paging: PageParams) -> TaskPage:
    total, rows, groups, hidden = projects_tasks_service.list_tasks(db, ctx, workspace_id, filters, paging.page,
                                                                    paging.page_size)
    page = paginated(rows, total, paging.page, paging.page_size, lambda r: to_model(TaskRowOut, r, ctx.company_id))
    meta: PageMeta = page["meta"]
    return TaskPage(data=page["data"], meta=meta, hidden_columns=hidden,
                    groups=[{"key": g["group_key"], "name": g["group_name"], "count": g["task_count"]} for g in groups])


def get_task(db: Db, ctx: RequestContext, task_id: int) -> dict:
    return _task(projects_tasks_service.get_task(db, ctx, task_id), ctx.company_id)


def create_task(db: Db, ctx: RequestContext, body: TaskCreateIn) -> dict:
    return _task(projects_tasks_service.create_task(db, ctx, body), ctx.company_id)


def update_task(db: Db, ctx: RequestContext, task_id: int, body: TaskIn) -> dict:
    row = projects_tasks_service.update_task(db, ctx, task_id, body, row_version_in(body.row_version))
    return _task(row, ctx.company_id)


def set_status(db: Db, ctx: RequestContext, task_id: int, body: StatusChangeIn) -> dict:
    row = projects_tasks_service.set_status(db, ctx, task_id, body.status_id, row_version_in(body.row_version))
    return _task(row, ctx.company_id)


def set_cover(db: Db, ctx: RequestContext, task_id: int, body: CoverIn) -> dict:
    row = projects_tasks_service.set_cover(db, ctx, task_id, body.file_id, row_version_in(body.row_version))
    return _task(row, ctx.company_id)


def save_assignees(db: Db, ctx: RequestContext, task_id: int, body: AssigneesIn) -> dict:
    return _task(projects_tasks_service.save_assignees(db, ctx, task_id, body.assignees), ctx.company_id)


def save_tags(db: Db, ctx: RequestContext, task_id: int, body: TaskTagsIn) -> dict:
    return _task(projects_tasks_service.save_tags(db, ctx, task_id, body.tag_ids), ctx.company_id)


def move_task(db: Db, ctx: RequestContext, task_id: int, body: MoveIn) -> dict:
    row = projects_tasks_service.move_task(db, ctx, task_id, body, row_version_in(body.row_version))
    return _task(row, ctx.company_id)


def convert_to_list(db: Db, ctx: RequestContext, task_id: int, row_version: str | None) -> dict:
    row = projects_tasks_service.convert_to_list(db, ctx, task_id, row_version_in(row_version))
    return {"data": ConvertedOut(**row)}


def delete_task(db: Db, ctx: RequestContext, task_id: int, row_version: str | None) -> None:
    projects_tasks_service.delete_task(db, ctx, task_id, row_version_in(row_version))


def save_field_value(db: Db, ctx: RequestContext, task_id: int, field_id: int, value: Any) -> dict:
    return _task(projects_tasks_service.save_field_value(db, ctx, task_id, field_id, value), ctx.company_id)


def add_dependency(db: Db, ctx: RequestContext, task_id: int, body: DependencyIn) -> dict:
    return _task(projects_tasks_service.add_dependency(db, ctx, task_id, body.other_task_id, body.kind), ctx.company_id)


def delete_dependency(db: Db, ctx: RequestContext, dependency_id: int) -> None:
    projects_tasks_service.delete_dependency(db, ctx, dependency_id)


def add_checklist_item(db: Db, ctx: RequestContext, task_id: int, body: ChecklistItemIn) -> dict:
    return {"data": to_model(ChecklistItemOut, projects_tasks_service.save_checklist_item(db, ctx, None, task_id, body,
                                                                                         None))}


def update_checklist_item(db: Db, ctx: RequestContext, item_id: int, body: ChecklistItemIn) -> dict:
    row = projects_tasks_service.save_checklist_item(db, ctx, item_id, None, body, row_version_in(body.row_version))
    return {"data": to_model(ChecklistItemOut, row)}


def delete_checklist_item(db: Db, ctx: RequestContext, item_id: int) -> None:
    projects_tasks_service.delete_checklist_item(db, ctx, item_id)


def task_activity(db: Db, ctx: RequestContext, task_id: int, paging: PageParams) -> dict:
    total, rows = projects_tasks_service.task_activity(db, ctx, task_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: ActivityOut(**r))


def request_extension(db: Db, ctx: RequestContext, task_id: int, body: ExtensionRequestIn) -> dict:
    row = projects_tasks_service.request_extension(db, ctx, task_id, body.new_due_date, body.reason)
    return _task(row, ctx.company_id)


def decide_extension(db: Db, ctx: RequestContext, extension_id: int, approve: bool, body: ExtensionDecisionIn) -> dict:
    return _task(projects_tasks_service.decide_extension(db, ctx, extension_id, approve, body.remarks,
                                                         row_version_in(body.row_version)), ctx.company_id)
