"""Engagement data access: eng.usp_post_*, eng.usp_post_comment_*, eng.usp_survey_* and the settings."""
from datetime import date
from typing import Any

from app.core.db import Db

Row = dict[str, Any]
Rows = list[Row]


def _page(sets: list[Rows]) -> tuple[int, Rows]:
    return sets[0][0]["total"], sets[1]


# --------------------------------------------------------------------------- posts

def list_posts(db: Db, company_id: int, actor_user_id: int, mode: str, author_id: int | None, search: str | None,
               hidden_only: bool, page: int, page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("eng.usp_post_list", company_id=company_id, actor_user_id=actor_user_id, mode=mode,
                              author_id=author_id, search=search, hidden_only=hidden_only, page=page,
                              page_size=page_size))


def get_post(db: Db, company_id: int, actor_user_id: int, post_id: int) -> Row:
    return db.call_one("eng.usp_post_get", company_id=company_id, actor_user_id=actor_user_id, id=post_id)


def save_post(db: Db, company_id: int, actor_user_id: int, post_id: int | None, body: str | None, visibility: str,
              department_id: int | None, branch_id: int | None, media: str, mentions: str,
              row_version: bytes | None) -> Row:
    return db.call_one("eng.usp_post_save", company_id=company_id, actor_user_id=actor_user_id, id=post_id, body=body,
                       visibility=visibility, department_id=department_id, branch_id=branch_id, media=media,
                       mentions=mentions, row_version=row_version)


def delete_post(db: Db, company_id: int, actor_user_id: int, post_id: int, row_version: bytes) -> None:
    db.call("eng.usp_post_delete", company_id=company_id, actor_user_id=actor_user_id, id=post_id,
            row_version=row_version)


def view_post(db: Db, company_id: int, actor_user_id: int, post_id: int) -> Row:
    return db.call_one("eng.usp_post_view", company_id=company_id, actor_user_id=actor_user_id, id=post_id)


def pin_post(db: Db, company_id: int, actor_user_id: int, post_id: int, pinned: bool) -> Row:
    return db.call_one("eng.usp_post_pin", company_id=company_id, actor_user_id=actor_user_id, id=post_id,
                       is_pinned=pinned)


def hide_post(db: Db, company_id: int, actor_user_id: int, post_id: int, hidden: bool, reason: str | None) -> Row:
    return db.call_one("eng.usp_post_hide", company_id=company_id, actor_user_id=actor_user_id, id=post_id,
                       is_hidden=hidden, reason=reason)


def react(db: Db, company_id: int, actor_user_id: int, post_id: int, kind: str | None) -> Row:
    return db.call_one("eng.usp_post_react", company_id=company_id, actor_user_id=actor_user_id, id=post_id, kind=kind)


def list_reactions(db: Db, company_id: int, actor_user_id: int, post_id: int, kind: str | None, page: int,
                   page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("eng.usp_post_reaction_list", company_id=company_id, actor_user_id=actor_user_id,
                              id=post_id, kind=kind, page=page, page_size=page_size))


# --------------------------------------------------------------------------- comments

def list_comments(db: Db, company_id: int, actor_user_id: int, post_id: int, page: int,
                  page_size: int) -> tuple[int, Rows, Rows]:
    sets = db.call_sets("eng.usp_post_comment_list", company_id=company_id, actor_user_id=actor_user_id,
                        post_id=post_id, page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1], sets[2]


def save_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int | None, post_id: int | None,
                 parent_id: int | None, body: str, mentions: str, row_version: bytes | None) -> Row:
    return db.call_one("eng.usp_post_comment_save", company_id=company_id, actor_user_id=actor_user_id, id=comment_id,
                       post_id=post_id, parent_id=parent_id, body=body, mentions=mentions, row_version=row_version)


def delete_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int, row_version: bytes) -> None:
    db.call("eng.usp_post_comment_delete", company_id=company_id, actor_user_id=actor_user_id, id=comment_id,
            row_version=row_version)


def like_comment(db: Db, company_id: int, actor_user_id: int, comment_id: int, liked: bool) -> Row:
    return db.call_one("eng.usp_post_comment_like", company_id=company_id, actor_user_id=actor_user_id, id=comment_id,
                       liked=liked)


# --------------------------------------------------------------------------- settings

def get_settings(db: Db, company_id: int) -> Row:
    return db.call_one("eng.usp_engagement_settings_get", company_id=company_id)


def save_settings(db: Db, company_id: int, actor_user_id: int, who_may_post: str, allow_comments: bool,
                  max_media_per_post: int, row_version: bytes | None) -> Row:
    return db.call_one("eng.usp_engagement_settings_save", company_id=company_id, actor_user_id=actor_user_id,
                       who_may_post=who_may_post, allow_comments=allow_comments,
                       max_media_per_post=max_media_per_post, row_version=row_version)


# --------------------------------------------------------------------------- surveys

def list_surveys(db: Db, company_id: int, search: str | None, status: str | None, page: int,
                 page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("eng.usp_survey_list", company_id=company_id, search=search, status=status, page=page,
                              page_size=page_size))


def get_survey(db: Db, company_id: int, survey_id: int) -> Row:
    return db.call_one("eng.usp_survey_get", company_id=company_id, id=survey_id)


def save_survey(db: Db, company_id: int, actor_user_id: int, survey_id: int | None, title: str,
                description: str | None, is_anonymous: bool, opens_on: date | None, closes_on: date | None,
                questions: str, audience: str, row_version: bytes | None) -> Row:
    return db.call_one("eng.usp_survey_save", company_id=company_id, actor_user_id=actor_user_id, id=survey_id,
                       title=title, description=description, is_anonymous=is_anonymous, opens_on=opens_on,
                       closes_on=closes_on, questions=questions, audience=audience, row_version=row_version)


def delete_survey(db: Db, company_id: int, actor_user_id: int, survey_id: int, row_version: bytes) -> None:
    db.call("eng.usp_survey_delete", company_id=company_id, actor_user_id=actor_user_id, id=survey_id,
            row_version=row_version)


def survey_action(db: Db, proc: str, company_id: int, actor_user_id: int, survey_id: int, row_version: bytes,
                  **extra: Any) -> Row:
    """eng.usp_survey_publish / _close / _closing_date."""
    return db.call_one(f"eng.usp_survey_{proc}", company_id=company_id, actor_user_id=actor_user_id, id=survey_id,
                       row_version=row_version, **extra)


def survey_results(db: Db, company_id: int, survey_id: int) -> list[Rows]:
    return db.call_sets("eng.usp_survey_results", company_id=company_id, id=survey_id)


def list_responses(db: Db, company_id: int, actor_user_id: int, survey_id: int, permission_code: str,
                   allow_anonymous: bool, page: int, page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("eng.usp_survey_response_list", company_id=company_id, actor_user_id=actor_user_id,
                              id=survey_id, permission_code=permission_code, allow_anonymous=allow_anonymous,
                              page=page, page_size=page_size))


def list_my_surveys(db: Db, company_id: int, actor_user_id: int, filter_: str, page: int,
                    page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("eng.usp_my_survey_list", company_id=company_id, actor_user_id=actor_user_id,
                              filter=filter_, page=page, page_size=page_size))


def get_my_survey(db: Db, company_id: int, actor_user_id: int, survey_id: int) -> Row:
    return db.call_one("eng.usp_my_survey_get", company_id=company_id, actor_user_id=actor_user_id, id=survey_id)


def respond(db: Db, company_id: int, actor_user_id: int, survey_id: int, answers: str) -> Row:
    return db.call_one("eng.usp_survey_respond", company_id=company_id, actor_user_id=actor_user_id, id=survey_id,
                       answers=answers)


def skip(db: Db, company_id: int, actor_user_id: int, survey_id: int) -> Row:
    return db.call_one("eng.usp_survey_skip", company_id=company_id, actor_user_id=actor_user_id, id=survey_id)
