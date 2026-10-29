"""Project management with AI (Backend Dependencies T2 and T10). Every route answers 503 AI_UNAVAILABLE
while no model is connected (app.core.ai); the shapes below are what the screens will read."""
from datetime import date, datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import ApiModel


class AiContextIn(ApiModel):
    doc_id: int | None = None
    task_id: int | None = None


class AiWriteIn(ApiModel):
    """Writing with AI in docs and task descriptions. text: the selection."""
    action: Literal["improve", "summarize", "template", "email", "table", "blog", "continue"]
    prompt: str | None = Field(None, max_length=4000)
    text: str | None = Field(None, max_length=50_000)
    context: AiContextIn | None = None


class AiHtmlOut(ApiModel):
    html: str


class AiTaskIn(ApiModel):
    task_id: int


class AiDocSuggestIn(ApiModel):
    doc_id: int | None = None
    title: str = Field(min_length=1, max_length=200)


class LineUpItemOut(ApiModel):
    """Daily task line-up: the caller's tasks for the day, ranked."""
    task_id: str
    name: str
    rank: int
    reason: str


class ReminderSuggestionOut(ApiModel):
    __local_times__ = frozenset({"remind_at"})
    remind_at: datetime
    reason: str


class AtRiskTaskOut(ApiModel):
    task_id: str
    name: str
    due_date: date | None
    predicted_delay_days: int
    reason: str


class AssignSuggestionOut(ApiModel):
    employee_id: str
    name: str
    score: float
    reason: str


class DependencyRiskOut(ApiModel):
    task_ids: list[str]
    risk_level: Literal["low", "medium", "high"]
    reason: str


class DocTemplateOut(ApiModel):
    name: str
    outline_html: str


class DocSuggestOut(ApiModel):
    templates: list[DocTemplateOut]
    outline_html: str | None


class RelatedItemOut(ApiModel):
    id: str
    name: str
    reason: str | None = None


class RelatedOut(ApiModel):
    docs: list[RelatedItemOut]
    files: list[RelatedItemOut]
    tasks: list[RelatedItemOut]


class CommentSuggestOut(ApiModel):
    suggestions: list[str]


class ExtensionSuggestionOut(ApiModel):
    task_id: str
    name: str
    due_date: date | None
    suggested_due_date: date
    reason: str


class SearchResultOut(ApiModel):
    entity_type: Literal["task", "doc", "task_list", "folder", "workspace"]
    entity_id: str
    name: str
    workspace_id: str | None
    score: float


class WorkloadSuggestionOut(ApiModel):
    task_id: str
    name: str
    from_employee_id: str | None
    to_employee_id: str
    reason: str


class SummaryOut(ApiModel):
    html: str
    metrics: dict[str, Any]
