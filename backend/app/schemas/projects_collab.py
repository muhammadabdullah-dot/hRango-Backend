"""Project management collaboration: comments, attachments, time tracking, reminders, sharing."""
from datetime import datetime
from typing import Literal

from pydantic import Field, model_validator

from app.schemas.common import ApiModel

SHARE_PROPERTIES = ("task_name_status", "assignee", "priority", "due_date", "description", "comments", "attachments",
                    "custom_fields", "subtasks", "tags", "checklists", "cover_image")
ShareProperty = Literal["task_name_status", "assignee", "priority", "due_date", "description", "comments",
                        "attachments", "custom_fields", "subtasks", "tags", "checklists", "cover_image"]


# --------------------------------------------------------------------------- comments

class MentionIn(ApiModel):
    """@person (employeeId) or a task (taskId)."""
    employee_id: int | None = None
    task_id: int | None = None

    @model_validator(mode="after")
    def _one(self) -> "MentionIn":
        if (self.employee_id is None) == (self.task_id is None):
            raise ValueError("Mention either a person or a task.")
        return self


class CommentIn(ApiModel):
    body: str = Field(min_length=1, max_length=2000)
    parent_id: int | None = None
    assigned_to_id: int | None = None
    mentions: list[MentionIn] = []


class CommentEditIn(ApiModel):
    body: str = Field(min_length=1, max_length=2000)
    mentions: list[MentionIn] = []
    row_version: str | None = None


class CommentAssignIn(ApiModel):
    assigned_to_id: int | None = None


class CommentResolveIn(ApiModel):
    resolved: bool


class ReactionIn(ApiModel):
    """like or an emoji; null takes the caller's reaction off."""
    reaction: str | None = Field(None, max_length=30)


class ReactionOut(ApiModel):
    employee_id: str
    reaction: str


class MentionOut(ApiModel):
    employee_id: str | None = None
    name: str | None = None
    task_id: str | None = None
    task_code: str | None = None
    task_name: str | None = None


class CommentOut(ApiModel):
    id: str
    task_id: str
    parent_id: str | None
    author_id: str
    author_name: str
    body: str
    assigned_to_id: str | None
    assigned_to_name: str | None
    assigned_by_id: str | None
    assigned_by_name: str | None
    is_resolved: bool
    resolved_by_id: str | None
    resolved_by_name: str | None
    resolved_at: datetime | None
    edited_at: datetime | None
    created_at: datetime
    reply_count: int
    reactions: list[ReactionOut]
    mentions: list[MentionOut]
    row_version: str


# --------------------------------------------------------------------------- attachments

class AttachmentIn(ApiModel):
    """A file uploaded first (POST /api/files, module projects): PDF, DOCX, XLSX, PNG or JPG up to 10 MB."""
    file_id: int


class AttachmentOut(ApiModel):
    id: str
    task_id: str
    file_id: str
    name: str
    mime_type: str | None
    size_bytes: int | None
    # Who attached it to the task.
    uploaded_by_user_id: str | None
    uploaded_by_name: str | None
    created_at: datetime
    # Signed download link (expires).
    url: str


# --------------------------------------------------------------------------- time

class TimeEntryIn(ApiModel):
    """Start and stop, or start and minutes. employeeId: someone else's time (managers and above)."""
    start_at: datetime
    end_at: datetime | None = None
    minutes: int | None = Field(None, gt=0, le=24 * 60)
    notes: str | None = Field(None, max_length=165)
    employee_id: int | None = None
    row_version: str | None = None


class TimerStopIn(ApiModel):
    notes: str | None = Field(None, max_length=165)


class TimeEntryOut(ApiModel):
    __local_times__ = frozenset({'start_at', 'end_at'})  # wall-clock, no zone
    id: str
    task_id: str
    employee_id: str
    employee_name: str
    start_at: datetime
    end_at: datetime | None
    minutes: int | None
    is_running: bool
    notes: str | None
    row_version: str


# --------------------------------------------------------------------------- reminders

class ReminderIn(ApiModel):
    entity_type: Literal["task", "task_list", "workspace"]
    entity_id: int
    name: str | None = Field(None, max_length=200)
    remind_at: datetime
    assignee_id: int | None = None
    notify_before_minutes: int | None = Field(None, ge=0)
    reminder_kind: Literal["soft", "hard"] | None = None
    row_version: str | None = None


class ReminderOut(ApiModel):
    __local_times__ = frozenset({'remind_at'})  # wall-clock, no zone
    id: str
    workspace_id: str
    entity_type: str
    entity_id: str
    entity_name: str | None
    name: str
    owner_id: str
    owner_name: str
    assignee_id: str | None
    assignee_name: str | None
    remind_at: datetime
    notify_before_minutes: int | None
    reminder_kind: str | None
    notified_at: datetime | None
    created_at: datetime
    row_version: str


# --------------------------------------------------------------------------- sharing

class ShareMemberIn(ApiModel):
    employee_id: int | None = None
    email: str | None = Field(None, max_length=254)
    access_level: Literal["full_edit", "limited", "commenter"]

    @model_validator(mode="after")
    def _who(self) -> "ShareMemberIn":
        if (self.employee_id is None) == (self.email is None):
            raise ValueError("Share with a person or an email address.")
        return self


class ShareIn(ApiModel):
    entity_type: Literal["task", "task_list", "workspace"]
    entity_id: int
    share_scope: Literal["list", "page"] = "list"
    is_public: bool = False
    allow_open_tasks: bool = True
    valid_from: datetime | None = None
    valid_to: datetime | None = None
    max_access: int | None = Field(None, ge=1)
    properties: list[ShareProperty] | None = None
    members: list[ShareMemberIn] = []
    row_version: str | None = None


class ShareMemberOut(ApiModel):
    id: str
    employee_id: str | None
    employee_name: str | None
    email: str | None
    access_level: str


class ShareOut(ApiModel):
    """The saved settings, or the defaults (id null) when the item has not been shared yet."""
    __local_times__ = frozenset({'valid_from', 'valid_to'})  # wall-clock, no zone
    id: str | None
    entity_type: str
    entity_id: str
    share_scope: str
    token: str | None
    # Address of the private link; no page serves it yet.
    link: str | None
    is_public: bool
    allow_open_tasks: bool
    valid_from: datetime | None
    valid_to: datetime | None
    max_access: int | None
    access_count: int
    properties: list[str]
    members: list[ShareMemberOut]
    row_version: str | None
