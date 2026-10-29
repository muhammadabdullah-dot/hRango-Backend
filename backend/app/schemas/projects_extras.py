"""Project management extras: Notepad (T3), overdue settings (T5), recents and dashboards (T7) and the
Personal List (T11)."""
from datetime import date, datetime, time
from typing import Literal

from pydantic import Field, model_validator

from app.schemas.common import ApiModel
from app.schemas.projects_collab import CommentOut
from app.schemas.projects_tasks import TaskRowOut

RecentEntity = Literal["workspace", "folder", "task_list", "task", "doc"]


# --------------------------------------------------------------------------- notepad

class NoteIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    content_html: str | None = Field(None, max_length=1_000_000)
    row_version: str | None = None


class NoteArchiveIn(ApiModel):
    row_version: str | None = None
    # false restores an archived note.
    archived: bool = True


class NoteConvertIn(ApiModel):
    """A task goes into listId (or the workspace's top level); a doc into workspaceId (or the list's
    workspace). original: what happens to the note afterwards."""
    to: Literal["task", "doc"]
    list_id: int | None = None
    workspace_id: int | None = None
    original: Literal["delete", "archive", "keep"] = "keep"

    @model_validator(mode="after")
    def _where(self) -> "NoteConvertIn":
        if self.list_id is None and self.workspace_id is None:
            raise ValueError("Choose the workspace or list it goes to.")
        return self


class NoteOut(ApiModel):
    id: str
    title: str
    content_html: str | None
    archived: bool
    version: int
    created_at: datetime
    updated_at: datetime
    row_version: str


class NoteVersionOut(ApiModel):
    version: int
    title: str
    content_html: str | None
    edited_at: datetime
    edited_by_name: str | None


class NoteConvertedOut(ApiModel):
    task_id: str | None = None
    doc_id: str | None = None


# --------------------------------------------------------------------------- personal list

class PersonalItemIn(ApiModel):
    title: str = Field(min_length=1, max_length=120)
    due_date: date | None = None


class PersonalItemDoneIn(ApiModel):
    done: bool
    row_version: str | None = None


class PersonalItemOut(ApiModel):
    id: str
    title: str
    done: bool
    due_date: date | None
    created_at: datetime
    row_version: str


# --------------------------------------------------------------------------- recents

class RecentIn(ApiModel):
    entity_type: RecentEntity
    entity_id: int


class RecentOut(ApiModel):
    entity_type: str
    entity_id: str
    name: str
    workspace_id: str
    workspace_name: str | None
    opened_at: datetime


# --------------------------------------------------------------------------- overdue settings

class OverdueSettingsIn(ApiModel):
    """penaltyPercent: share of a closed-late task's story points taken off; maxExtensions: extension
    requests allowed per task."""
    penalty_percent: float = Field(ge=0, le=100)
    max_extensions: int = Field(ge=0, le=10)
    row_version: str | None = None


class OverdueSettingsOut(ApiModel):
    workspace_id: str
    penalty_percent: float
    max_extensions: int
    # Null until the settings are first saved (the defaults are shown).
    row_version: str | None


# --------------------------------------------------------------------------- dashboards

class HomeRecentOut(ApiModel):
    type: str
    id: str
    name: str
    workspace_id: str
    opened_at: datetime


class AgendaItemOut(ApiModel):
    task_id: str
    name: str
    due_date: date | None
    due_time: time | None
    workspace_id: str


class ActivityDayOut(ApiModel):
    date: date
    completed: int
    assigned: int


class HomeDashboardOut(ApiModel):
    recents: list[HomeRecentOut]
    agenda: list[AgendaItemOut]
    my_work: list[TaskRowOut]
    assigned_comments: list[CommentOut]
    activity: list[ActivityDayOut]


class StatusCountOut(ApiModel):
    status_id: str
    name: str
    color: str | None
    status_group: str
    count: int


class AssigneeCountOut(ApiModel):
    employee_id: str
    name: str | None
    open: int
    total: int


class DocSummaryOut(ApiModel):
    id: str
    workspace_id: str
    title: str
    folder_id: str | None
    list_id: str | None
    owner_name: str | None
    word_count: int
    updated_at: datetime


class BookmarkOut(ApiModel):
    entity_type: str
    entity_id: str
    name: str | None
    workspace_id: str
    created_at: datetime


class ResourceOut(ApiModel):
    """A file on a task in scope, or a link to external storage (provider set)."""
    id: str
    task_id: str
    task_name: str
    file_id: str | None
    name: str
    mime_type: str | None
    size_bytes: int | None
    provider: str | None
    # Signed download link (expires), or the provider's address.
    url: str | None
    created_at: datetime


class ScopeDashboardOut(ApiModel):
    by_status: list[StatusCountOut]
    by_assignee: list[AssigneeCountOut]
    due_this_week: int
    overdue: int
    completed_this_week: int
    unassigned: int
    recent_docs: list[DocSummaryOut]
    bookmarks: list[BookmarkOut]
    resources: list[ResourceOut]

