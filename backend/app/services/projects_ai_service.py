"""Project management with AI (Backend Dependencies T2, T10). No model is connected yet: every function
asks app.core.ai first, which answers 503 AI_UNAVAILABLE while settings.ai_provider is blank, so the
screens hide their AI panels. When a provider is connected, each function builds its prompt from the
caller's data (only what they may see) and returns the shape in schemas/projects_ai.py.

TODO(pm-ai): implement each feature once a provider is chosen; until then a configured provider answers
501 AI_NOT_IMPLEMENTED. Server jobs from T10 (overdue / story point upkeep #7, automatic progress updates
#10, adaptive reminders #13) are not built."""
from datetime import date
from typing import Any

from app.core import ai
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.schemas.projects_ai import AiDocSuggestIn, AiTaskIn, AiWriteIn


def _not_built(feature: str) -> AppError:
    return AppError(501, "AI_NOT_IMPLEMENTED", f"{feature} with AI is not available yet.")


def write(ctx: RequestContext, body: AiWriteIn) -> dict[str, Any]:
    ai.ensure_available()
    raise _not_built("Writing")


def line_up(ctx: RequestContext, day: date | None) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("The daily line-up")


def standup(ctx: RequestContext, scope: str, workspace_id: int | None, date_from: date | None,
            date_to: date | None) -> dict[str, Any]:
    ai.ensure_available()
    raise _not_built("The standup summary")


def suggest_reminders(ctx: RequestContext, body: AiTaskIn) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("Reminder suggestions")


def at_risk(ctx: RequestContext, workspace_id: int | None) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("At-risk tasks")


def suggest_assignees(ctx: RequestContext, body: AiTaskIn) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("Assignment suggestions")


def dependency_risk(ctx: RequestContext, workspace_id: int | None) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("Dependency risk")


def doc_suggest(ctx: RequestContext, body: AiDocSuggestIn) -> dict[str, Any]:
    ai.ensure_available()
    raise _not_built("Document suggestions")


def related(ctx: RequestContext, task_id: int) -> dict[str, Any]:
    ai.ensure_available()
    raise _not_built("Recommendations")


def comment_suggest(ctx: RequestContext, body: AiTaskIn) -> dict[str, Any]:
    ai.ensure_available()
    raise _not_built("Comment suggestions")


def extension_suggestions(ctx: RequestContext, workspace_id: int | None) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("Extension suggestions")


def search(ctx: RequestContext, q: str) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("Smart search")


def workload(ctx: RequestContext, workspace_id: int | None) -> list[dict[str, Any]]:
    ai.ensure_available()
    raise _not_built("Workload rebalancing")


def summary(ctx: RequestContext, workspace_id: int | None, folder_id: int | None, date_from: date | None,
            date_to: date | None) -> dict[str, Any]:
    ai.ensure_available()
    raise _not_built("Project summaries")
