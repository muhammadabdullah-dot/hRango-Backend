"""Project management with AI (Backend Dependencies T2, T10) under /projects/ai. Every route answers
503 {code: AI_UNAVAILABLE} while no model is connected, so the screens can hide their AI panels.
Included by routers/projects.py under /projects."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query

from app.controllers import projects_ai_controller as c
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item
from app.schemas.projects_ai import (AiDocSuggestIn, AiHtmlOut, AiTaskIn, AiWriteIn, AssignSuggestionOut,
                                     AtRiskTaskOut, CommentSuggestOut, DependencyRiskOut, DocSuggestOut,
                                     ExtensionSuggestionOut, LineUpItemOut, RelatedOut, ReminderSuggestionOut,
                                     SearchResultOut, SummaryOut, WorkloadSuggestionOut)

router = APIRouter(prefix="/ai")
AI = require("projects.ai.generate")
UNAVAILABLE = {503: {"description": "AI_UNAVAILABLE: no model is connected"}}


@router.post("/write", response_model=Item[AiHtmlOut], responses=UNAVAILABLE)
def write(body: AiWriteIn, ctx: RequestContext = Depends(AI)) -> dict:
    return c.write(ctx, body)


@router.get("/line-up", response_model=Item[list[LineUpItemOut]], responses=UNAVAILABLE)
def line_up(day: date | None = Query(None, alias="date"), ctx: RequestContext = Depends(AI)) -> dict:
    return c.line_up(ctx, day)


@router.get("/standup", response_model=Item[AiHtmlOut], responses=UNAVAILABLE)
def standup(scope: Literal["me", "team"] = "me", workspace_id: int | None = Query(None, alias="workspaceId"),
            date_from: date | None = Query(None, alias="from"), date_to: date | None = Query(None, alias="to"),
            ctx: RequestContext = Depends(AI)) -> dict:
    return c.standup(ctx, scope, workspace_id, date_from, date_to)


@router.post("/reminders/suggest", response_model=Item[list[ReminderSuggestionOut]], responses=UNAVAILABLE)
def suggest_reminders(body: AiTaskIn, ctx: RequestContext = Depends(AI)) -> dict:
    return c.suggest_reminders(ctx, body)


@router.get("/at-risk", response_model=Item[list[AtRiskTaskOut]], responses=UNAVAILABLE)
def at_risk(workspace_id: int | None = Query(None, alias="workspaceId"), ctx: RequestContext = Depends(AI)) -> dict:
    return c.at_risk(ctx, workspace_id)


@router.post("/assign/suggest", response_model=Item[list[AssignSuggestionOut]], responses=UNAVAILABLE)
def suggest_assignees(body: AiTaskIn, ctx: RequestContext = Depends(AI)) -> dict:
    return c.suggest_assignees(ctx, body)


@router.get("/dependency-risk", response_model=Item[list[DependencyRiskOut]], responses=UNAVAILABLE)
def dependency_risk(workspace_id: int | None = Query(None, alias="workspaceId"),
                    ctx: RequestContext = Depends(AI)) -> dict:
    return c.dependency_risk(ctx, workspace_id)


@router.post("/doc-suggest", response_model=Item[DocSuggestOut], responses=UNAVAILABLE)
def doc_suggest(body: AiDocSuggestIn, ctx: RequestContext = Depends(AI)) -> dict:
    return c.doc_suggest(ctx, body)


@router.get("/related", response_model=Item[RelatedOut], responses=UNAVAILABLE)
def related(task_id: int = Query(alias="taskId"), ctx: RequestContext = Depends(AI)) -> dict:
    return c.related(ctx, task_id)


@router.post("/comment-suggest", response_model=Item[CommentSuggestOut], responses=UNAVAILABLE)
def comment_suggest(body: AiTaskIn, ctx: RequestContext = Depends(AI)) -> dict:
    return c.comment_suggest(ctx, body)


@router.get("/extension-suggestions", response_model=Item[list[ExtensionSuggestionOut]], responses=UNAVAILABLE)
def extension_suggestions(workspace_id: int | None = Query(None, alias="workspaceId"),
                          ctx: RequestContext = Depends(AI)) -> dict:
    return c.extension_suggestions(ctx, workspace_id)


@router.get("/search", response_model=Item[list[SearchResultOut]], responses=UNAVAILABLE)
def search(q: str = Query(min_length=1, max_length=200), ctx: RequestContext = Depends(AI)) -> dict:
    return c.search(ctx, q)


@router.get("/workload", response_model=Item[list[WorkloadSuggestionOut]], responses=UNAVAILABLE)
def workload(workspace_id: int | None = Query(None, alias="workspaceId"), ctx: RequestContext = Depends(AI)) -> dict:
    return c.workload(ctx, workspace_id)


@router.get("/summary", response_model=Item[SummaryOut], responses=UNAVAILABLE)
def summary(workspace_id: int | None = Query(None, alias="workspaceId"),
            folder_id: int | None = Query(None, alias="folderId"),
            date_from: date | None = Query(None, alias="from"), date_to: date | None = Query(None, alias="to"),
            ctx: RequestContext = Depends(AI)) -> dict:
    return c.summary(ctx, workspace_id, folder_id, date_from, date_to)
