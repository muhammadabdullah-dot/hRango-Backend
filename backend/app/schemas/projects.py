"""Project management: workspaces (the Create Workspace wizard), members and workspace roles,
statuses, organizer features, column permissions, custom fields, folders, lists, views, tags,
favourites and history. Tasks are in projects_tasks.py; comments, files, time, reminders and
sharing in projects_collab.py."""
from datetime import datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Privacy = Literal["private", "workspace", "public"]
StatusGroup = Literal["not_started", "active", "done", "closed"]
WorkspaceRole = Literal["workspace_admin", "hr", "manager", "team_leader", "contributor"]
ViewType = Literal["list", "board", "calendar", "map", "activity", "team", "table", "timeline", "gantt",
                   "mind_map", "workload", "custom"]
FeatureCode = Literal["priority", "sprints", "email", "tags", "custom_fields", "multiple_assignees",
                      "time_tracking", "time_estimate", "remap_subtask_due_dates", "wip_limits", "story_points",
                      "incomplete_warning", "dependency_warning", "reschedule_dependencies", "show_status_progress"]
PermissionLevel = Literal["default", "can_edit", "can_view", "private"]
FieldType = Literal["text", "long_text", "number", "money", "date", "checkbox", "dropdown", "labels", "email",
                    "phone", "website", "rating", "progress_manual", "people"]
Priority = Literal["urgent", "high", "normal", "low"]


# --------------------------------------------------------------------------- templates, people

class TemplateViewOut(ApiModel):
    view_type: str
    name: str
    is_default: bool


class TemplateStatusOut(ApiModel):
    name: str
    color: str | None
    status_group: str


class TemplateFeatureOut(ApiModel):
    feature_code: str
    name: str


class TemplateOut(ApiModel):
    id: str
    code: str
    name: str
    description: str | None
    views: list[TemplateViewOut]
    statuses: list[TemplateStatusOut]
    features: list[TemplateFeatureOut]


class PersonOut(ApiModel):
    id: str
    code: str | None
    name: str
    designation_name: str | None
    department_name: str | None
    photo_file_id: str | None
    # Signed link to the employee's photo (expires).
    photo_url: str | None = None
    member_role: str | None


# --------------------------------------------------------------------------- workspace

class StatusIn(ApiModel):
    id: int | None = None
    name: str = Field(min_length=1, max_length=200)
    color: str | None = Field(None, max_length=20)
    status_group: StatusGroup
    wip_limit: int | None = Field(None, ge=1)


class ViewChoiceIn(ApiModel):
    view_type: ViewType
    is_default: bool = False


class FeatureIn(ApiModel):
    feature_code: FeatureCode
    setting_value: str | None = Field(None, max_length=4000)


class MemberIn(ApiModel):
    employee_id: int
    member_role: WorkspaceRole = "contributor"


class WorkspaceCreateIn(ApiModel):
    """The whole Create Workspace wizard. Leave statuses, views or features out to take the template's."""
    name: str = Field(min_length=3, max_length=50)
    description: str | None = Field(None, max_length=300)
    privacy: Privacy
    owner_id: int
    department_id: int
    workflow_template: str = "work_starter"
    status_mode: Literal["default", "custom"] = "default"
    status_template: str | None = None
    statuses: list[StatusIn] | None = None
    views: list[ViewChoiceIn] | None = None
    features: list[FeatureIn] | None = None
    members: list[MemberIn] = []


class WorkspaceIn(ApiModel):
    name: str = Field(min_length=3, max_length=50)
    description: str | None = Field(None, max_length=300)
    privacy: Privacy
    owner_id: int
    department_id: int
    row_version: str | None = None


class StatusesIn(ApiModel):
    status_mode: Literal["default", "custom"] | None = None
    status_template: str | None = None
    statuses: list[StatusIn]
    row_version: str | None = None


class FeaturesIn(ApiModel):
    features: list[FeatureIn]
    row_version: str | None = None


class StatusOut(ApiModel):
    id: str
    name: str
    color: str | None
    status_group: str
    sort_order: int | None
    wip_limit: int | None


class FeatureOut(ApiModel):
    feature_code: str
    setting_value: str | None


class MemberOut(ApiModel):
    employee_id: str
    name: str
    designation_name: str | None
    department_name: str | None
    member_role: str


class ViewOut(ApiModel):
    id: str
    task_list_id: str | None
    view_type: str
    name: str
    config: dict[str, Any] | None
    is_pinned: bool
    is_private: bool
    is_protected: bool
    is_default: bool
    is_required: bool
    sort_order: int | None
    owner_id: str | None
    row_version: str


class FolderOut(ApiModel):
    id: str
    name: str
    sort_order: int | None
    row_version: str


class ListOut(ApiModel):
    __local_times__ = frozenset({'start_at', 'end_at'})  # wall-clock, no zone
    id: str
    folder_id: str | None
    name: str
    privacy: str | None
    color: str | None
    description: str | None
    start_at: datetime | None
    end_at: datetime | None
    priority: str | None
    sort_order: int | None
    task_count: int
    closed_count: int
    # Progress Status Bar: closed tasks as a share of all tasks in the list.
    progress_percent: int
    last_modified_at: datetime | None
    member_ids: list[str]
    row_version: str


class WorkspaceSummaryOut(ApiModel):
    id: str
    name: str
    description: str | None
    privacy: str
    department_id: str | None
    department_name: str | None
    owner_id: str
    owner_name: str | None
    # The caller's workspace role; null when they are not a member of a workspace they can read.
    my_role: str | None
    is_favorite: bool
    is_hidden: bool
    member_count: int
    cover_file_id: str | None = None
    # The banner image: id, name and a signed link (expires).
    cover: FileRef | None = None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class WorkspaceOut(WorkspaceSummaryOut):
    workflow_template: str
    workflow_template_name: str
    status_mode: str
    status_template: str | None
    statuses: list[StatusOut]
    features: list[FeatureOut]
    members: list[MemberOut]
    views: list[ViewOut]
    folders: list[FolderOut]
    lists: list[ListOut]


class CoverIn(ApiModel):
    """A cover image uploaded first (POST /api/files, module projects): PNG, JPG, GIF or WEBP. null removes it."""
    file_id: int | None = None
    row_version: str


class MembersIn(ApiModel):
    members: list[MemberIn] = Field(min_length=1)


class MemberRoleIn(ApiModel):
    member_role: WorkspaceRole


# --------------------------------------------------------------------------- column permissions

class RoleLevelIn(ApiModel):
    member_role: WorkspaceRole
    permission_level: PermissionLevel


class MemberLevelIn(ApiModel):
    employee_id: int
    permission_level: PermissionLevel


class ColumnPermissionIn(ApiModel):
    default_level: PermissionLevel = "default"
    roles: list[RoleLevelIn] = []
    members: list[MemberLevelIn] = []


class RoleLevelOut(ApiModel):
    member_role: str
    permission_level: str


class MemberLevelOut(ApiModel):
    employee_id: str
    employee_name: str | None
    permission_level: str


class ColumnPermissionOut(ApiModel):
    column_key: str
    default_level: str
    roles: list[RoleLevelOut]
    members: list[MemberLevelOut]


class ColumnPermissionsOut(ApiModel):
    columns: list[ColumnPermissionOut]
    # Levels in effect for the caller, for columns that have any permission set.
    my_levels: dict[str, str]


# --------------------------------------------------------------------------- custom fields

class CustomFieldIn(ApiModel):
    """config by type: dropdown / labels {"options": [names]}; number / money {"min", "max"} (money also
    {"currency"}); rating {"max"} (default 5); progress_manual {"end"} (default 100)."""
    name: str = Field(min_length=1, max_length=200)
    field_type: FieldType
    description: str | None = Field(None, max_length=1000)
    config: dict[str, Any] | None = None
    row_version: str | None = None


class CustomFieldOut(ApiModel):
    id: str
    workspace_id: str
    name: str
    field_type: str
    description: str | None
    config: dict[str, Any] | None
    sort_order: int | None
    row_version: str


# --------------------------------------------------------------------------- folders, lists, views

class FolderIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    sort_order: int | None = None
    row_version: str | None = None


class ListIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    folder_id: int | None = None
    privacy: Privacy = "workspace"
    color: str | None = Field(None, max_length=20)
    description: str | None = Field(None, max_length=500)
    start_at: datetime | None = None
    end_at: datetime | None = None
    priority: Priority | None = None
    sort_order: int | None = None
    member_ids: list[int] | None = None
    row_version: str | None = None


class ViewIn(ApiModel):
    """config holds the Customize View settings: columns, filters, sort, grouping, subtask display."""
    view_type: ViewType
    name: str = Field(min_length=1, max_length=200)
    task_list_id: int | None = None
    config: dict[str, Any] | None = None
    is_pinned: bool = False
    is_private: bool = False
    is_protected: bool = False
    is_default: bool = False
    row_version: str | None = None


# --------------------------------------------------------------------------- favourites, tags, history

class FavoriteIn(ApiModel):
    entity_type: Literal["workspace", "folder", "task_list", "task"]
    entity_id: int
    kind: Literal["favorite", "hidden"] = "favorite"
    on: bool = True


class FavoriteOut(ApiModel):
    id: str
    entity_type: str
    entity_id: str
    kind: str
    name: str
    workspace_id: str
    created_at: datetime


class TagIn(ApiModel):
    name: str = Field(min_length=1, max_length=25)
    color: str | None = Field(None, max_length=20)
    row_version: str | None = None


class TagOut(ApiModel):
    id: str
    workspace_id: str
    name: str
    color: str | None
    task_count: int
    row_version: str


class ActivityOut(ApiModel):
    id: str
    entity_type: str
    entity_id: str
    item_code: str | None
    item_name: str | None
    action_name: str
    field_name: str | None
    old_value: str | None
    new_value: str | None
    performed_by_user_id: str | None
    performed_by_name: str | None
    performed_at: datetime
