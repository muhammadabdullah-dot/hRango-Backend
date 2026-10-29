"""Pages that work without signing in: the public share page of a task, list or workspace (Backend
Dependencies T6). Only the properties the link shows are filled; the others are null."""
from datetime import date, datetime

from app.schemas.common import ApiModel


class PublicTagOut(ApiModel):
    name: str
    color: str | None = None


class PublicTaskRowOut(ApiModel):
    id: str
    parent_task_id: str | None
    code: str | None
    name: str
    status_name: str
    status_color: str | None
    status_group: str
    # Shown when the link's properties include them, else null.
    priority: str | None = None
    due_date: date | None = None
    assignees: list[str] | None = None
    tags: list[PublicTagOut] | None = None


class PublicShareOut(ApiModel):
    # list (a list's tasks), view (a workspace's tasks), task (a task and its subtasks).
    entity_type: str
    title: str
    allow_open_tasks: bool
    properties: list[str]
    tasks: list[PublicTaskRowOut]


class PublicSubtaskOut(ApiModel):
    id: str
    code: str | None
    name: str
    status_name: str
    status_color: str | None
    status_group: str
    due_date: date | None = None


class PublicChecklistItemOut(ApiModel):
    item_text: str
    is_done: bool


class PublicCommentOut(ApiModel):
    id: str
    parent_id: str | None
    author_name: str | None
    body: str
    created_at: datetime


class PublicAttachmentOut(ApiModel):
    name: str
    mime_type: str | None
    size_bytes: int | None
    # A signed download link (expires), or the external storage address.
    url: str | None


class PublicFieldOut(ApiModel):
    name: str
    field_type: str
    value: str | None


class PublicTaskOut(PublicTaskRowOut):
    description: str | None = None
    start_date: date | None = None
    cover_url: str | None = None
    subtasks: list[PublicSubtaskOut] | None = None
    checklist: list[PublicChecklistItemOut] | None = None
    comments: list[PublicCommentOut] | None = None
    attachments: list[PublicAttachmentOut] | None = None
    custom_fields: list[PublicFieldOut] | None = None
