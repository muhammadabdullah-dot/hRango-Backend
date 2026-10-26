"""Project management tasks: the List view, the task screen, status moves, assignees, tags, moving
and converting, custom field values, dependencies, checklist, history and extension requests.
Included by routers/projects.py under /projects."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import projects_tasks_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.projects import ActivityOut, CoverIn
from app.schemas.projects_tasks import (AssigneesIn, ChecklistItemIn, ChecklistItemOut, ConvertedOut, DependencyIn,
                                        ExtensionDecisionIn, ExtensionRequestIn, FieldValueIn, MoveIn, RowVersionIn,
                                        StatusChangeIn, TaskCreateIn, TaskIn, TaskOut, TaskPage, TaskTagsIn)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT

VIEW = require("projects.tasks.view")
EDIT = require("projects.tasks.edit")


@router.get("/workspaces/{workspace_id}/tasks", response_model=TaskPage)
def list_tasks(workspace_id: int,
               list_id: int | None = Query(None, alias="listId"),
               q: str | None = None,
               status_ids: list[int] | None = Query(None, alias="statusIds"),
               status_groups: list[Literal["not_started", "active", "done", "closed"]] | None = Query(None, alias="statusGroups"),
               include_closed: bool = Query(True, alias="includeClosed"),
               priorities: list[Literal["urgent", "high", "normal", "low", "none"]] | None = Query(None),
               assignee_ids: list[int] | None = Query(None, alias="assigneeIds"),
               include_unassigned: bool = Query(False, alias="unassigned"),
               tag_ids: list[int] | None = Query(None, alias="tagIds"),
               created_by_ids: list[int] | None = Query(None, alias="createdByIds"),
               task_type: Literal["task", "milestone"] | None = Query(None, alias="taskType"),
               due_from: date | None = Query(None, alias="dueFrom"),
               due_to: date | None = Query(None, alias="dueTo"),
               start_from: date | None = Query(None, alias="startFrom"),
               start_to: date | None = Query(None, alias="startTo"),
               overdue: bool = False,
               subtasks: Literal["expanded", "collapsed", "separate"] = "expanded",
               group_by: Literal["none", "status", "priority", "assignee", "tag", "due_date", "task_type", "list"] =
               Query("status", alias="groupBy"),
               sort_by: Literal["manual", "name", "code", "status", "priority", "due_date", "start_date", "date_created",
                                "date_closed", "time_estimate", "story_points"] = Query("manual", alias="sortBy"),
               sort_dir: Literal["asc", "desc"] = Query("asc", alias="sortDir"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(VIEW)) -> TaskPage:
    filters = {"task_list_id": list_id, "q": q, "status_ids": status_ids, "status_groups": status_groups,
               "include_closed": include_closed, "priorities": priorities, "assignee_ids": assignee_ids,
               "include_unassigned": include_unassigned, "tag_ids": tag_ids, "created_by_ids": created_by_ids,
               "task_type": task_type, "due_from": due_from, "due_to": due_to, "start_from": start_from,
               "start_to": start_to, "overdue_only": overdue, "subtasks": subtasks, "group_by": group_by,
               "sort_by": sort_by, "sort_dir": sort_dir}
    return c.list_tasks(db, ctx, workspace_id, filters, paging)


@router.post("/tasks", response_model=Item[TaskOut], status_code=status.HTTP_201_CREATED)
def create_task(body: TaskCreateIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.tasks.create"))) -> dict:
    return c.create_task(db, ctx, body)


@router.get("/tasks/{task_id}", response_model=Item[TaskOut])
def get_task(task_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.get_task(db, ctx, task_id)


@router.put("/tasks/{task_id}", response_model=Item[TaskOut])
def update_task(task_id: int, body: TaskIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.update_task(db, ctx, task_id, body)


@router.delete("/tasks/{task_id}", status_code=NO_CONTENT)
def delete_task(task_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.tasks.delete"))) -> Response:
    c.delete_task(db, ctx, task_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.patch("/tasks/{task_id}/status", response_model=Item[TaskOut])
def set_status(task_id: int, body: StatusChangeIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.set_status(db, ctx, task_id, body)


@router.put("/tasks/{task_id}/cover", response_model=Item[TaskOut])
def set_cover(task_id: int, body: CoverIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    """Sets (fileId) or removes (fileId null) the task's cover image, uploaded first through POST /api/files."""
    return c.set_cover(db, ctx, task_id, body)


@router.put("/tasks/{task_id}/assignees", response_model=Item[TaskOut])
def save_assignees(task_id: int, body: AssigneesIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("projects.tasks.assign"))) -> dict:
    return c.save_assignees(db, ctx, task_id, body)


@router.put("/tasks/{task_id}/tags", response_model=Item[TaskOut])
def save_tags(task_id: int, body: TaskTagsIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.save_tags(db, ctx, task_id, body)


@router.post("/tasks/{task_id}/move", response_model=Item[TaskOut])
def move_task(task_id: int, body: MoveIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.move_task(db, ctx, task_id, body)


@router.post("/tasks/{task_id}/convert-to-list", response_model=Item[ConvertedOut])
def convert_to_list(task_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.convert_to_list(db, ctx, task_id, body.row_version)


@router.put("/tasks/{task_id}/fields/{field_id}", response_model=Item[TaskOut])
def save_field_value(task_id: int, field_id: int, body: FieldValueIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.save_field_value(db, ctx, task_id, field_id, body.value)


@router.post("/tasks/{task_id}/dependencies", response_model=Item[TaskOut])
def add_dependency(task_id: int, body: DependencyIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.add_dependency(db, ctx, task_id, body)


@router.delete("/dependencies/{dependency_id}", status_code=NO_CONTENT)
def delete_dependency(dependency_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> Response:
    c.delete_dependency(db, ctx, dependency_id)
    return Response(status_code=NO_CONTENT)


@router.post("/tasks/{task_id}/checklist", response_model=Item[ChecklistItemOut], status_code=status.HTTP_201_CREATED)
def add_checklist_item(task_id: int, body: ChecklistItemIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.add_checklist_item(db, ctx, task_id, body)


@router.put("/checklist-items/{item_id}", response_model=Item[ChecklistItemOut])
def update_checklist_item(item_id: int, body: ChecklistItemIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.update_checklist_item(db, ctx, item_id, body)


@router.delete("/checklist-items/{item_id}", status_code=NO_CONTENT)
def delete_checklist_item(item_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> Response:
    c.delete_checklist_item(db, ctx, item_id)
    return Response(status_code=NO_CONTENT)


@router.get("/tasks/{task_id}/activity", response_model=Paginated[ActivityOut])
def task_activity(task_id: int, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.history.view"))) -> dict:
    return c.task_activity(db, ctx, task_id, paging)


@router.post("/tasks/{task_id}/extension-requests", response_model=Item[TaskOut], status_code=status.HTTP_201_CREATED)
def request_extension(task_id: int, body: ExtensionRequestIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("projects.extensions.create"))) -> dict:
    return c.request_extension(db, ctx, task_id, body)


@router.patch("/extension-requests/{extension_id}/approve", response_model=Item[TaskOut])
def approve_extension(extension_id: int, body: ExtensionDecisionIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("projects.extensions.approve"))) -> dict:
    return c.decide_extension(db, ctx, extension_id, True, body)


@router.patch("/extension-requests/{extension_id}/reject", response_model=Item[TaskOut])
def reject_extension(extension_id: int, body: ExtensionDecisionIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("projects.extensions.reject"))) -> dict:
    return c.decide_extension(db, ctx, extension_id, False, body)
