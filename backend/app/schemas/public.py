"""Pages that work without signing in: the public share page of a task, list or workspace (Backend
Dependencies T6). Only the properties the link shows are filled; the others are null."""
from datetime import date, datetime
from decimal import Decimal

from pydantic import Field

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


class PublicShareOut(ApiModel):
    # list (a list's tasks), view (a workspace's tasks), task (a task and its subtasks).
    entity_type: str
    title: str
    # Whether a visitor may open the tasks on the page (GET .../tasks/{taskId}); a shared task's own details
    # come in `task` either way.
    allow_open_tasks: bool
    # What the link shows (Share Tasks Properties); a property left out is null on every task.
    properties: list[str]
    # The page's tasks; subtasks (parentTaskId set) only when "subtasks" is shown.
    tasks: list[PublicTaskRowOut]
    # entityType task: the shared task itself with its details (counted in the same access); null otherwise.
    task: PublicTaskOut | None = None


# ---------------------------------------------------------------- self-service sign-up (roadmap 1.1)

class PublicPlanOut(ApiModel):
    id: str
    name: str
    description: str | None
    price_monthly: Decimal
    price_annual: Decimal
    # None = no employee limit
    employee_limit: int | None


class SignUpIn(ApiModel):
    company_name: str = Field(min_length=2, max_length=200)
    owner_name: str = Field(min_length=2, max_length=200)
    owner_email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    contact_phone: str | None = Field(None, max_length=50)
    country: str | None = Field(None, max_length=100)
    currency: str | None = Field(None, pattern=r"^[A-Z]{3}$")
    timezone: str | None = Field(None, max_length=64, pattern=r"^(UTC|[A-Z][A-Za-z]+(/[A-Za-z0-9_+\-]+){1,2})$")
    plan_id: int | None = None
    # The visitor ticked "I agree to the Terms of Service and Privacy Policy".
    accept_terms: bool


class SignUpOut(ApiModel):
    message: str
