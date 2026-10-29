"""Project management tasks: the List view rows, the task screen, and every task edit."""
from datetime import date, datetime, time
from typing import Any, Literal

from pydantic import Field, model_validator

from app.schemas.common import ApiModel, PageMeta
from app.schemas.files import FileRef
from app.schemas.projects import Priority

TaskType = Literal["task", "milestone"]


class RecurrenceIn(ApiModel):
    """Custom Recurrence: every n days / weeks / months / years, on weekdays (0 Sunday .. 6 Saturday),
    ending never, on a date, or after n occurrences."""
    every: int = Field(1, ge=1, le=365)
    unit: Literal["day", "week", "month", "year"]
    weekdays: list[int] = []
    ends: Literal["never", "on", "after"] = "never"
    end_date: date | None = None
    count: int | None = Field(None, ge=1, le=1000)

    @model_validator(mode="after")
    def _check(self) -> "RecurrenceIn":
        if any(d < 0 or d > 6 for d in self.weekdays):
            raise ValueError("Weekdays run from 0 (Sunday) to 6 (Saturday).")
        if self.ends == "on" and self.end_date is None:
            raise ValueError("Pick the date the recurrence ends on.")
        if self.ends == "after" and self.count is None:
            raise ValueError("Say after how many occurrences the recurrence ends.")
        return self


class TaskFieldsIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(None, max_length=5000)
    task_type: TaskType = "task"
    priority: Priority | None = None
    start_date: date | None = None
    start_time: time | None = None
    due_date: date | None = None
    due_time: time | None = None
    time_estimate_minutes: int | None = Field(None, ge=0)
    rating: int | None = Field(None, ge=0, le=3)
    url: str | None = Field(None, max_length=2000)
    recurrence: RecurrenceIn | None = None


class TaskCreateIn(TaskFieldsIn):
    """Add Task. Give workspaceId (and listId), or parentTaskId for a subtask."""
    workspace_id: int | None = None
    task_list_id: int | None = None
    parent_task_id: int | None = None
    status_id: int | None = None
    assignee_ids: list[int] = []
    tag_ids: list[int] = []

    @model_validator(mode="after")
    def _where(self) -> "TaskCreateIn":
        if self.workspace_id is None and self.parent_task_id is None:
            raise ValueError("Give the workspace or the parent task.")
        return self


class TaskIn(TaskFieldsIn):
    """Edit Task: the task's own fields, replaced as a whole. rowVersion from the last read."""
    row_version: str | None = None


class StatusChangeIn(ApiModel):
    status_id: int
    row_version: str | None = None


class AssigneeIn(ApiModel):
    employee_id: int
    story_points: int | None = Field(None, ge=0, le=100)


class AssigneesIn(ApiModel):
    assignees: list[AssigneeIn]


class TaskTagsIn(ApiModel):
    tag_ids: list[int]


class MoveIn(ApiModel):
    """Move To, Convert to Subtask (parentTaskId) or back to a task (no parent), and reordering."""
    workspace_id: int | None = None
    task_list_id: int | None = None
    parent_task_id: int | None = None
    sort_order: int | None = None
    row_version: str | None = None


class RowVersionIn(ApiModel):
    row_version: str | None = None


class LocationValueIn(ApiModel):
    """A location custom field's value (Map view)."""
    address: str = Field(min_length=1, max_length=500)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class FieldValueIn(ApiModel):
    """Text, a number, true / false, a list (labels: option names; people: employee ids), or a location
    {address, lat, lng}. null clears."""
    value: str | int | float | bool | list[str | int] | LocationValueIn | None = None


class DependencyIn(ApiModel):
    other_task_id: int
    kind: Literal["waiting_on", "blocking", "linked"]


class ChecklistItemIn(ApiModel):
    item_text: str = Field(min_length=1, max_length=500)
    is_done: bool = False
    sort_order: int | None = None
    row_version: str | None = None


class ExtensionRequestIn(ApiModel):
    new_due_date: date
    reason: str = Field(min_length=1, max_length=1000)


class ExtensionDecisionIn(ApiModel):
    remarks: str | None = Field(None, max_length=1000)
    row_version: str | None = None


# --------------------------------------------------------------------------- output

class AssigneeOut(ApiModel):
    employee_id: str
    name: str
    story_points: int | None = None


class TagRefOut(ApiModel):
    id: str
    name: str
    color: str | None = None


class FieldValueOut(ApiModel):
    custom_field_id: str
    field_value: str | None = None


class LatestCommentOut(ApiModel):
    body: str
    author_name: str | None
    created_at: datetime


class LatestExtensionOut(ApiModel):
    status: str
    new_due_date: date


class TaskRowOut(ApiModel):
    """A task as the List view draws it. Columns the caller may not see (Private Field) come back
    null or empty and are named in hiddenColumns."""
    id: str
    workspace_id: str
    task_list_id: str | None
    list_name: str | None
    parent_task_id: str | None
    parent_name: str | None
    code: str | None
    name: str
    description: str | None
    task_type: str
    status_id: str
    status_name: str
    status_color: str | None
    status_group: str
    priority: str | None
    start_date: date | None
    start_time: time | None
    due_date: date | None
    due_time: time | None
    original_due_date: date | None
    is_overdue: bool | None
    time_estimate_minutes: int | None
    time_tracked_minutes: int | None
    story_points_total: int | None
    # Overdue settings: points taken off a task closed late (0 when on time, null without story points).
    story_points_penalty: float | None = None
    story_points_effective: float | None = None
    rating: int | None
    url: str | None
    recurrence: dict[str, Any] | None
    closed_at: datetime | None
    is_closed_late: bool
    sort_order: int | None
    created_by_user_id: str | None
    created_by_name: str | None
    created_at: datetime | None
    updated_at: datetime | None
    subtask_count: int
    open_subtask_count: int
    comment_count: int
    attachment_count: int | None
    open_dependency_count: int | None
    blocking_count: int | None
    checklist_count: int
    checklist_done_count: int
    latest_comment: LatestCommentOut | None
    # The newest extension request (Overdue tab), or null.
    latest_extension: LatestExtensionOut | None = None
    assignees: list[AssigneeOut]
    tags: list[TagRefOut]
    field_values: list[FieldValueOut]
    cover_file_id: str | None = None
    # The cover image: id, name and a signed link (expires).
    cover: FileRef | None = None
    row_version: str
    # List view only: the row's group, its depth under a parent, and its top-level row.
    group_key: str | None = None
    group_name: str | None = None
    depth: int = 0
    root_id: str | None = None


class DependencyOut(ApiModel):
    id: str
    kind: str
    task_id: str
    code: str
    name: str
    status_name: str
    status_color: str | None
    status_group: str


class ChecklistItemOut(ApiModel):
    id: str
    task_id: str | None = None
    item_text: str
    is_done: bool
    sort_order: int | None
    row_version: str


class SubtaskOut(ApiModel):
    id: str
    code: str
    name: str
    status_name: str
    status_color: str | None
    status_group: str
    due_date: date | None


class ExtensionOut(ApiModel):
    id: str
    requested_by_id: str
    requested_by_name: str
    old_due_date: date | None
    new_due_date: date
    reason: str | None
    status: str
    decided_by_id: str | None
    decided_by_name: str | None
    decided_at: datetime | None
    remarks: str | None
    created_at: datetime
    row_version: str


class TaskOut(TaskRowOut):
    my_role: str | None
    is_favorite: bool
    dependencies: list[DependencyOut]
    checklist: list[ChecklistItemOut]
    subtasks: list[SubtaskOut]
    extensions: list[ExtensionOut]
    hidden_columns: list[str]


class GroupOut(ApiModel):
    key: str
    name: str
    count: int


class TaskPage(ApiModel):
    data: list[TaskRowOut]
    meta: PageMeta
    groups: list[GroupOut]
    hidden_columns: list[str]


class ConvertedOut(ApiModel):
    task_list_id: str
