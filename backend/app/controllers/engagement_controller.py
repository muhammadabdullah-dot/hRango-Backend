"""HTTP shape for Engagement: envelopes, rowVersion text <-> bytes, rows -> response models."""
from datetime import date
from typing import Any, TypeVar

from fastapi import Response

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import ApiModel, paginated
from app.schemas.engagement import (CommentEditIn, CommentIn, CommentOut, MySurveyOut, PostIn, PostOut, ReactorOut,
                                    ResponseIn, ResponseOut, SettingsIn, SettingsOut, SurveyIn, SurveyListOut,
                                    SurveyOut, SurveyResultsOut, ViewOut)
from app.services import engagement_service as svc

M = TypeVar("M", bound=ApiModel)


def _to(model: type[M], row: dict[str, Any]) -> M:
    values = dict(row)
    if "row_version" in values:
        values["row_version"] = row_version_out(values["row_version"])
    if "replies" in values:
        values["replies"] = [_to(CommentOut, r) for r in values["replies"]]
    return model(**values)


def _page(result: tuple[int, list[dict[str, Any]]], paging: PageParams, model: type[ApiModel]) -> dict:
    total, rows = result
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _to(model, r))


# --------------------------------------------------------------------------- posts

def list_posts(db: Db, ctx: RequestContext, mode: str, author_id: int | None, q: str | None, hidden_only: bool,
               paging: PageParams) -> dict:
    return _page(svc.list_posts(db, ctx, mode, author_id, q, hidden_only, paging.page, paging.page_size), paging,
                 PostOut)


def get_post(db: Db, ctx: RequestContext, post_id: int) -> dict:
    return {"data": _to(PostOut, svc.get_post(db, ctx, post_id))}


def create_post(db: Db, ctx: RequestContext, body: PostIn) -> dict:
    return {"data": _to(PostOut, svc.save_post(db, ctx, None, body, None))}


def update_post(db: Db, ctx: RequestContext, post_id: int, body: PostIn) -> dict:
    return {"data": _to(PostOut, svc.save_post(db, ctx, post_id, body, row_version_in(body.row_version)))}


def delete_post(db: Db, ctx: RequestContext, post_id: int, row_version: str | None) -> None:
    svc.delete_post(db, ctx, post_id, row_version_in(row_version))


def view_post(db: Db, ctx: RequestContext, post_id: int) -> dict:
    return {"data": ViewOut(**svc.view_post(db, ctx, post_id))}


def pin_post(db: Db, ctx: RequestContext, post_id: int, pinned: bool) -> dict:
    return {"data": _to(PostOut, svc.pin_post(db, ctx, post_id, pinned))}


def hide_post(db: Db, ctx: RequestContext, post_id: int, hidden: bool, reason: str | None) -> dict:
    return {"data": _to(PostOut, svc.hide_post(db, ctx, post_id, hidden, reason))}


def react(db: Db, ctx: RequestContext, post_id: int, kind: str | None) -> dict:
    return {"data": _to(PostOut, svc.react(db, ctx, post_id, kind))}


def list_reactions(db: Db, ctx: RequestContext, post_id: int, kind: str | None, paging: PageParams) -> dict:
    return _page(svc.list_reactions(db, ctx, post_id, kind, paging.page, paging.page_size), paging, ReactorOut)


# --------------------------------------------------------------------------- comments

def list_comments(db: Db, ctx: RequestContext, post_id: int, paging: PageParams) -> dict:
    return _page(svc.list_comments(db, ctx, post_id, paging.page, paging.page_size), paging, CommentOut)


def add_comment(db: Db, ctx: RequestContext, post_id: int, body: CommentIn) -> dict:
    return {"data": _to(CommentOut, svc.add_comment(db, ctx, post_id, body))}


def edit_comment(db: Db, ctx: RequestContext, comment_id: int, body: CommentEditIn) -> dict:
    return {"data": _to(CommentOut, svc.edit_comment(db, ctx, comment_id, body, row_version_in(body.row_version)))}


def delete_comment(db: Db, ctx: RequestContext, comment_id: int, row_version: str | None) -> None:
    svc.delete_comment(db, ctx, comment_id, row_version_in(row_version))


def like_comment(db: Db, ctx: RequestContext, comment_id: int, liked: bool) -> dict:
    return {"data": _to(CommentOut, svc.like_comment(db, ctx, comment_id, liked))}


# --------------------------------------------------------------------------- settings

def get_settings(db: Db, ctx: RequestContext) -> dict:
    return {"data": _to(SettingsOut, svc.get_settings(db, ctx))}


def save_settings(db: Db, ctx: RequestContext, body: SettingsIn) -> dict:
    row = svc.save_settings(db, ctx, body, row_version_in(body.row_version, required=False))
    return {"data": _to(SettingsOut, row)}


# --------------------------------------------------------------------------- surveys

def list_surveys(db: Db, ctx: RequestContext, q: str | None, status: str | None, paging: PageParams) -> dict:
    return _page(svc.list_surveys(db, ctx, q, status, paging.page, paging.page_size), paging, SurveyListOut)


def get_survey(db: Db, ctx: RequestContext, survey_id: int) -> dict:
    return {"data": _to(SurveyOut, svc.get_survey(db, ctx, survey_id))}


def create_survey(db: Db, ctx: RequestContext, body: SurveyIn) -> dict:
    return {"data": _to(SurveyOut, svc.save_survey(db, ctx, None, body, None))}


def update_survey(db: Db, ctx: RequestContext, survey_id: int, body: SurveyIn) -> dict:
    row = svc.save_survey(db, ctx, survey_id, body, row_version_in(body.row_version))
    return {"data": _to(SurveyOut, row)}


def delete_survey(db: Db, ctx: RequestContext, survey_id: int, row_version: str | None) -> None:
    svc.delete_survey(db, ctx, survey_id, row_version_in(row_version))


def publish_survey(db: Db, ctx: RequestContext, survey_id: int, row_version: str | None) -> dict:
    return {"data": _to(SurveyOut, svc.publish_survey(db, ctx, survey_id, row_version_in(row_version)))}


def close_survey(db: Db, ctx: RequestContext, survey_id: int, row_version: str | None) -> dict:
    return {"data": _to(SurveyOut, svc.close_survey(db, ctx, survey_id, row_version_in(row_version)))}


def move_closing_date(db: Db, ctx: RequestContext, survey_id: int, closes_on: date | None,
                      row_version: str | None) -> dict:
    row = svc.move_closing_date(db, ctx, survey_id, closes_on, row_version_in(row_version))
    return {"data": _to(SurveyOut, row)}


def survey_results(db: Db, ctx: RequestContext, survey_id: int) -> dict:
    return {"data": SurveyResultsOut(**svc.survey_results(db, ctx, survey_id))}


def list_responses(db: Db, ctx: RequestContext, survey_id: int, paging: PageParams) -> dict:
    return _page(svc.list_responses(db, ctx, survey_id, paging.page, paging.page_size), paging, ResponseOut)


def export_responses(db: Db, ctx: RequestContext, survey_id: int) -> Response:
    name, text = svc.export_responses(db, ctx, survey_id)
    return Response(content=text.encode("utf-8"), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="{name}"'})


# --------------------------------------------------------------------------- answering

def list_my_surveys(db: Db, ctx: RequestContext, filter_: str, paging: PageParams) -> dict:
    return _page(svc.list_my_surveys(db, ctx, filter_, paging.page, paging.page_size), paging, MySurveyOut)


def get_my_survey(db: Db, ctx: RequestContext, survey_id: int) -> dict:
    return {"data": _to(MySurveyOut, svc.get_my_survey(db, ctx, survey_id))}


def respond(db: Db, ctx: RequestContext, survey_id: int, body: ResponseIn) -> dict:
    return {"data": _to(MySurveyOut, svc.respond(db, ctx, survey_id, body))}


def skip(db: Db, ctx: RequestContext, survey_id: int) -> dict:
    return {"data": _to(MySurveyOut, svc.skip(db, ctx, survey_id))}
