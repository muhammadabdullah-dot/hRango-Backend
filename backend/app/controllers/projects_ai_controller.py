"""HTTP shape for project management with AI: envelopes around the service's answers."""
from datetime import date

from app.middlewares.auth import RequestContext
from app.schemas.projects_ai import (AiDocSuggestIn, AiHtmlOut, AiTaskIn, AiWriteIn, AssignSuggestionOut,
                                     AtRiskTaskOut, CommentSuggestOut, DependencyRiskOut, DocSuggestOut,
                                     ExtensionSuggestionOut, LineUpItemOut, RelatedOut, ReminderSuggestionOut,
                                     SearchResultOut, SummaryOut, WorkloadSuggestionOut)
from app.services import projects_ai_service as s


def write(ctx: RequestContext, body: AiWriteIn) -> dict:
    return {"data": AiHtmlOut(**s.write(ctx, body))}


def line_up(ctx: RequestContext, day: date | None) -> dict:
    return {"data": [LineUpItemOut(**r) for r in s.line_up(ctx, day)]}


def standup(ctx: RequestContext, scope: str, workspace_id: int | None, date_from: date | None,
            date_to: date | None) -> dict:
    return {"data": AiHtmlOut(**s.standup(ctx, scope, workspace_id, date_from, date_to))}


def suggest_reminders(ctx: RequestContext, body: AiTaskIn) -> dict:
    return {"data": [ReminderSuggestionOut(**r) for r in s.suggest_reminders(ctx, body)]}


def at_risk(ctx: RequestContext, workspace_id: int | None) -> dict:
    return {"data": [AtRiskTaskOut(**r) for r in s.at_risk(ctx, workspace_id)]}


def suggest_assignees(ctx: RequestContext, body: AiTaskIn) -> dict:
    return {"data": [AssignSuggestionOut(**r) for r in s.suggest_assignees(ctx, body)]}


def dependency_risk(ctx: RequestContext, workspace_id: int | None) -> dict:
    return {"data": [DependencyRiskOut(**r) for r in s.dependency_risk(ctx, workspace_id)]}


def doc_suggest(ctx: RequestContext, body: AiDocSuggestIn) -> dict:
    return {"data": DocSuggestOut(**s.doc_suggest(ctx, body))}


def related(ctx: RequestContext, task_id: int) -> dict:
    return {"data": RelatedOut(**s.related(ctx, task_id))}


def comment_suggest(ctx: RequestContext, body: AiTaskIn) -> dict:
    return {"data": CommentSuggestOut(**s.comment_suggest(ctx, body))}


def extension_suggestions(ctx: RequestContext, workspace_id: int | None) -> dict:
    return {"data": [ExtensionSuggestionOut(**r) for r in s.extension_suggestions(ctx, workspace_id)]}


def search(ctx: RequestContext, q: str) -> dict:
    return {"data": [SearchResultOut(**r) for r in s.search(ctx, q)]}


def workload(ctx: RequestContext, workspace_id: int | None) -> dict:
    return {"data": [WorkloadSuggestionOut(**r) for r in s.workload(ctx, workspace_id)]}


def summary(ctx: RequestContext, workspace_id: int | None, folder_id: int | None, date_from: date | None,
            date_to: date | None) -> dict:
    return {"data": SummaryOut(**s.summary(ctx, workspace_id, folder_id, date_from, date_to))}
