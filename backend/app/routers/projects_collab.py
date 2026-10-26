"""Project management collaboration: comments, attachments, time tracking, reminders and sharing.
Included by routers/projects.py under /projects."""
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import projects_collab_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.projects_collab import (AttachmentIn, AttachmentOut, CommentAssignIn, CommentEditIn, CommentIn,
                                         CommentOut, CommentResolveIn, ReactionIn, ReminderIn, ReminderOut, ShareIn,
                                         ShareOut, TimeEntryIn, TimeEntryOut, TimerStopIn)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED


# --------------------------------------------------------------------------- comments

@router.get("/tasks/{task_id}/comments", response_model=Item[list[CommentOut]])
def list_comments(task_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.comments.view"))) -> dict:
    return c.list_comments(db, ctx, task_id)


@router.post("/tasks/{task_id}/comments", response_model=Item[CommentOut], status_code=CREATED)
def add_comment(task_id: int, body: CommentIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.comments.create"))) -> dict:
    return c.add_comment(db, ctx, task_id, body)


@router.put("/comments/{comment_id}", response_model=Item[CommentOut])
def edit_comment(comment_id: int, body: CommentEditIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("projects.comments.edit"))) -> dict:
    return c.edit_comment(db, ctx, comment_id, body)


@router.patch("/comments/{comment_id}/assign", response_model=Item[CommentOut])
def assign_comment(comment_id: int, body: CommentAssignIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("projects.comments.edit"))) -> dict:
    return c.assign_comment(db, ctx, comment_id, body.assigned_to_id)


@router.patch("/comments/{comment_id}/resolve", response_model=Item[CommentOut])
def resolve_comment(comment_id: int, body: CommentResolveIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("projects.comments.edit"))) -> dict:
    return c.resolve_comment(db, ctx, comment_id, body.resolved)


@router.put("/comments/{comment_id}/reaction", response_model=Item[CommentOut])
def react_comment(comment_id: int, body: ReactionIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.comments.create"))) -> dict:
    return c.react_comment(db, ctx, comment_id, body.reaction)


@router.delete("/comments/{comment_id}", status_code=NO_CONTENT)
def delete_comment(comment_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("projects.comments.delete"))) -> Response:
    c.delete_comment(db, ctx, comment_id, row_version)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- attachments

@router.get("/tasks/{task_id}/attachments", response_model=Item[list[AttachmentOut]])
def list_attachments(task_id: int, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("projects.tasks.view"))) -> dict:
    return c.list_attachments(db, ctx, task_id)


@router.post("/tasks/{task_id}/attachments", response_model=Item[AttachmentOut], status_code=CREATED)
def add_attachment(task_id: int, body: AttachmentIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("projects.tasks.edit"))) -> dict:
    return c.add_attachment(db, ctx, task_id, body)


@router.delete("/attachments/{attachment_id}", status_code=NO_CONTENT)
def delete_attachment(attachment_id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("projects.tasks.edit"))) -> Response:
    c.delete_attachment(db, ctx, attachment_id)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- time tracking

@router.get("/tasks/{task_id}/time-entries", response_model=Item[list[TimeEntryOut]])
def list_time_entries(task_id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("projects.time_tracking.view"))) -> dict:
    return c.list_time_entries(db, ctx, task_id)


@router.post("/tasks/{task_id}/time-entries", response_model=Item[TimeEntryOut], status_code=CREATED)
def add_time_entry(task_id: int, body: TimeEntryIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("projects.time_tracking.create"))) -> dict:
    return c.add_time_entry(db, ctx, task_id, body)


@router.put("/time-entries/{entry_id}", response_model=Item[TimeEntryOut])
def update_time_entry(entry_id: int, body: TimeEntryIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("projects.time_tracking.edit"))) -> dict:
    return c.update_time_entry(db, ctx, entry_id, body)


@router.delete("/time-entries/{entry_id}", status_code=NO_CONTENT)
def delete_time_entry(entry_id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("projects.time_tracking.delete"))) -> Response:
    c.delete_time_entry(db, ctx, entry_id)
    return Response(status_code=NO_CONTENT)


@router.post("/tasks/{task_id}/timer/start", response_model=Item[TimeEntryOut], status_code=CREATED)
def start_timer(task_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.time_tracking.create"))) -> dict:
    return c.start_timer(db, ctx, task_id)


@router.post("/timer/stop", response_model=Item[TimeEntryOut])
def stop_timer(body: TimerStopIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.time_tracking.create"))) -> dict:
    return c.stop_timer(db, ctx, body.notes)


# --------------------------------------------------------------------------- reminders

@router.get("/reminders", response_model=Paginated[ReminderOut])
def list_reminders(entity_type: Literal["task", "task_list", "workspace"] | None = Query(None, alias="entityType"),
                   entity_id: int | None = Query(None, alias="entityId"),
                   include_done: bool = Query(False, alias="includeDone"),
                   paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("projects.reminders.view"))) -> dict:
    return c.list_reminders(db, ctx, entity_type, entity_id, include_done, paging)


@router.post("/reminders", response_model=Item[ReminderOut], status_code=CREATED)
def create_reminder(body: ReminderIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("projects.reminders.create"))) -> dict:
    return c.create_reminder(db, ctx, body)


@router.put("/reminders/{reminder_id}", response_model=Item[ReminderOut])
def update_reminder(reminder_id: int, body: ReminderIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("projects.reminders.edit"))) -> dict:
    return c.update_reminder(db, ctx, reminder_id, body)


@router.delete("/reminders/{reminder_id}", status_code=NO_CONTENT)
def delete_reminder(reminder_id: int, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("projects.reminders.delete"))) -> Response:
    c.delete_reminder(db, ctx, reminder_id)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- sharing

@router.get("/shares", response_model=Item[ShareOut])
def get_share(entity_type: Literal["task", "task_list", "workspace"] = Query(alias="entityType"),
              entity_id: int = Query(alias="entityId"), db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("projects.sharing.view"))) -> dict:
    return c.get_share(db, ctx, entity_type, entity_id)


@router.put("/shares", response_model=Item[ShareOut])
def save_share(body: ShareIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.sharing.edit"))) -> dict:
    return c.save_share(db, ctx, body)


@router.delete("/shares/{share_id}", status_code=NO_CONTENT)
def delete_share(share_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("projects.sharing.edit"))) -> Response:
    c.delete_share(db, ctx, share_id)
    return Response(status_code=NO_CONTENT)
