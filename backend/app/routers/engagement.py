"""Engagement: the company newsfeed (posts with photos and videos, reactions, comments with replies and
likes, views, My Posts), its moderation and settings, and surveys (builder, publishing, answering,
results). Announcements are under /organisation/announcements."""
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import engagement_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.common import Item, Paginated
from app.schemas.engagement import (ClosingDateIn, CommentEditIn, CommentIn, CommentOut, HideIn, LikeIn, MySurveyOut,
                                    PinIn, PostIn, PostOut, ReactionIn, ReactorOut, ResponseIn, ResponseOut,
                                    RowVersionIn, SettingsIn, SettingsOut, SurveyIn, SurveyListOut, SurveyOut,
                                    SurveyResultsOut, ViewOut)

router = APIRouter(prefix="/engagement", tags=["engagement"])
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED


def _deleted() -> Response:
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- newsfeed

@router.get("/posts", response_model=Paginated[PostOut])
def list_feed(q: str | None = None, author_id: int | None = Query(None, alias="authorId"),
              paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("engagement.feed.view"))) -> dict:
    """The newsfeed: what the caller may read, pinned posts first, then newest first."""
    return c.list_posts(db, ctx, "feed", author_id, q, False, paging)


@router.get("/my-posts", response_model=Paginated[PostOut])
def list_my_posts(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.feed.view"))) -> dict:
    """My Posts: the caller's own posts, hidden ones included."""
    return c.list_posts(db, ctx, "mine", None, q, False, paging)


@router.get("/posts/{post_id}", response_model=Item[PostOut])
def get_post(post_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("engagement.feed.view"))) -> dict:
    return c.get_post(db, ctx, post_id)


@router.post("/posts", response_model=Item[PostOut], status_code=CREATED)
def create_post(body: PostIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("engagement.feed.create"))) -> dict:
    return c.create_post(db, ctx, body)


@router.put("/posts/{post_id}", response_model=Item[PostOut])
def update_post(post_id: int, body: PostIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("engagement.feed.edit"))) -> dict:
    """Edit Post: the author only."""
    return c.update_post(db, ctx, post_id, body)


@router.delete("/posts/{post_id}", status_code=NO_CONTENT)
def delete_post(post_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require_any("engagement.feed.delete",
                                                          "engagement.moderation.delete"))) -> Response:
    """The author (engagement.feed.delete) or a moderator of the author (engagement.moderation.delete)."""
    c.delete_post(db, ctx, post_id, row_version)
    return _deleted()


@router.post("/posts/{post_id}/view", response_model=Item[ViewOut])
def view_post(post_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("engagement.feed.view"))) -> dict:
    """Counts the caller's view once ("2.5k Views"); the author's own views do not count."""
    return c.view_post(db, ctx, post_id)


@router.put("/posts/{post_id}/reaction", response_model=Item[PostOut])
def react(post_id: int, body: ReactionIn, db: Db = Depends(get_db),
          ctx: RequestContext = Depends(require("engagement.feed.create"))) -> dict:
    return c.react(db, ctx, post_id, body.kind)


@router.get("/posts/{post_id}/reactions", response_model=Paginated[ReactorOut])
def list_reactions(post_id: int, kind: str | None = None, paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(require("engagement.feed.view"))) -> dict:
    """Reactions on Post: who reacted and how."""
    return c.list_reactions(db, ctx, post_id, kind, paging)


@router.get("/posts/{post_id}/comments", response_model=Paginated[CommentOut])
def list_comments(post_id: int, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.feed.view"))) -> dict:
    """Threads, oldest first: each top-level comment with its replies."""
    return c.list_comments(db, ctx, post_id, paging)


@router.post("/posts/{post_id}/comments", response_model=Item[CommentOut], status_code=CREATED)
def add_comment(post_id: int, body: CommentIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("engagement.feed.create"))) -> dict:
    return c.add_comment(db, ctx, post_id, body)


@router.put("/comments/{comment_id}", response_model=Item[CommentOut])
def edit_comment(comment_id: int, body: CommentEditIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("engagement.feed.edit"))) -> dict:
    return c.edit_comment(db, ctx, comment_id, body)


@router.delete("/comments/{comment_id}", status_code=NO_CONTENT)
def delete_comment(comment_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require_any("engagement.feed.delete",
                                                             "engagement.moderation.delete"))) -> Response:
    c.delete_comment(db, ctx, comment_id, row_version)
    return _deleted()


@router.put("/comments/{comment_id}/like", response_model=Item[CommentOut])
def like_comment(comment_id: int, body: LikeIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("engagement.feed.create"))) -> dict:
    return c.like_comment(db, ctx, comment_id, body.liked)


# --------------------------------------------------------------------------- moderation

@router.get("/moderation/posts", response_model=Paginated[PostOut])
def list_moderation(q: str | None = None, author_id: int | None = Query(None, alias="authorId"),
                    hidden_only: bool = Query(False, alias="hiddenOnly"), paging: PageParams = Depends(page_params),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("engagement.moderation.view"))) -> dict:
    """Every post of the authors the caller moderates, whatever its audience, hidden ones included."""
    return c.list_posts(db, ctx, "moderation", author_id, q, hidden_only, paging)


@router.patch("/posts/{post_id}/pin", response_model=Item[PostOut])
def pin_post(post_id: int, body: PinIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("engagement.moderation.edit"))) -> dict:
    return c.pin_post(db, ctx, post_id, body.pinned)


@router.patch("/posts/{post_id}/hide", response_model=Item[PostOut])
def hide_post(post_id: int, body: HideIn, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("engagement.moderation.edit"))) -> dict:
    return c.hide_post(db, ctx, post_id, body.hidden, body.reason)


# --------------------------------------------------------------------------- settings

@router.get("/settings", response_model=Item[SettingsOut])
def get_settings(db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("engagement.settings.general.view"))) -> dict:
    return c.get_settings(db, ctx)


@router.put("/settings", response_model=Item[SettingsOut])
def save_settings(body: SettingsIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.settings.general.edit"))) -> dict:
    return c.save_settings(db, ctx, body)


# --------------------------------------------------------------------------- surveys (HR)

@router.get("/surveys", response_model=Paginated[SurveyListOut])
def list_surveys(q: str | None = None, status_: Literal["draft", "published", "closed"] | None = Query(None, alias="status"),
                 paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("engagement.surveys.view"))) -> dict:
    return c.list_surveys(db, ctx, q, status_, paging)


@router.get("/surveys/{survey_id}", response_model=Item[SurveyOut])
def get_survey(survey_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("engagement.surveys.view"))) -> dict:
    return c.get_survey(db, ctx, survey_id)


@router.post("/surveys", response_model=Item[SurveyOut], status_code=CREATED)
def create_survey(body: SurveyIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.surveys.create"))) -> dict:
    """Saves a draft."""
    return c.create_survey(db, ctx, body)


@router.put("/surveys/{survey_id}", response_model=Item[SurveyOut])
def update_survey(survey_id: int, body: SurveyIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.surveys.edit"))) -> dict:
    """Drafts only: questions, options and audience are replaced."""
    return c.update_survey(db, ctx, survey_id, body)


@router.delete("/surveys/{survey_id}", status_code=NO_CONTENT)
def delete_survey(survey_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.surveys.delete"))) -> Response:
    c.delete_survey(db, ctx, survey_id, row_version)
    return _deleted()


@router.patch("/surveys/{survey_id}/publish", response_model=Item[SurveyOut])
def publish_survey(survey_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("engagement.surveys.publish"))) -> dict:
    return c.publish_survey(db, ctx, survey_id, body.row_version)


@router.patch("/surveys/{survey_id}/close", response_model=Item[SurveyOut])
def close_survey(survey_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("engagement.surveys.close"))) -> dict:
    return c.close_survey(db, ctx, survey_id, body.row_version)


@router.patch("/surveys/{survey_id}/closing-date", response_model=Item[SurveyOut])
def move_closing_date(survey_id: int, body: ClosingDateIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("engagement.surveys.edit"))) -> dict:
    """A published survey's closing date: extend it, or end it earlier."""
    return c.move_closing_date(db, ctx, survey_id, body.closes_on, body.row_version)


@router.get("/surveys/{survey_id}/results", response_model=Item[SurveyResultsOut])
def survey_results(survey_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("engagement.surveys.view"))) -> dict:
    """Totals per question; never who answered what."""
    return c.survey_results(db, ctx, survey_id)


@router.get("/surveys/{survey_id}/responses", response_model=Paginated[ResponseOut])
def list_responses(survey_id: int, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("engagement.survey_responses.view"))) -> dict:
    """Named surveys only: each person's answers (within the caller's scope)."""
    return c.list_responses(db, ctx, survey_id, paging)


@router.get("/surveys/{survey_id}/export")
def export_responses(survey_id: int, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("engagement.surveys.export"))) -> Response:
    """CSV, one row per response; names only for named surveys."""
    return c.export_responses(db, ctx, survey_id)


# --------------------------------------------------------------------------- surveys (answering)

@router.get("/my-surveys", response_model=Paginated[MySurveyOut])
def list_my_surveys(filter_: Literal["pending", "answered", "skipped", "missed", "all"] = Query("pending", alias="filter"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("engagement.survey_responses.respond"))) -> dict:
    """The "Survey Available (n)" popup is filter=pending; meta.total is the count."""
    return c.list_my_surveys(db, ctx, filter_, paging)


@router.get("/my-surveys/{survey_id}", response_model=Item[MySurveyOut])
def get_my_survey(survey_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("engagement.survey_responses.respond"))) -> dict:
    return c.get_my_survey(db, ctx, survey_id)


@router.post("/my-surveys/{survey_id}/response", response_model=Item[MySurveyOut], status_code=CREATED)
def respond(survey_id: int, body: ResponseIn, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("engagement.survey_responses.respond"))) -> dict:
    """Once per person; final once sent."""
    return c.respond(db, ctx, survey_id, body)


@router.post("/my-surveys/{survey_id}/skip", response_model=Item[MySurveyOut])
def skip(survey_id: int, db: Db = Depends(get_db),
         ctx: RequestContext = Depends(require("engagement.survey_responses.respond"))) -> dict:
    return c.skip(db, ctx, survey_id)
