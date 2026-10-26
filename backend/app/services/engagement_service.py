"""Engagement rules: the newsfeed (posts, reactions, comments, views, moderation), its settings and
surveys. Audience, ownership and moderation rules live in the eng procedures; this layer shapes rows
(JSON columns, signed file links, comment threads, survey results) and builds the CSV export."""
import csv
import io
import json
from collections import defaultdict
from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.middlewares.auth import RequestContext
from app.repos import engagement_repo as repo
from app.schemas.engagement import CommentEditIn, CommentIn, PostIn, ResponseIn, SettingsIn, SurveyIn

Row = dict[str, Any]
Rows = list[Row]
EXPORT_ROWS = 100_000


def _loads(text: str | None) -> Any:
    return json.loads(text) if text else None


def post_link(post_id: Any) -> str:
    """What "Copy link" copies: the post's page in the app."""
    return f"/engagement/posts/{post_id}"


def shape_post(row: Row, company_id: int) -> Row:
    out = dict(row)
    out["reactions"] = _loads(out.pop("reactions_json", None)) or []
    out["mentions"] = _loads(out.pop("mentions_json", None)) or []
    out["media"] = [{**m, "url": file_url(m["file_id"], company_id)} for m in _loads(out.pop("media_json", None)) or []]
    out["author_photo_url"] = file_url(out.pop("author_photo_file_id", None), company_id)
    out.setdefault("can_moderate", False)
    out["link"] = post_link(out["id"])
    return out


def shape_comment(row: Row, company_id: int) -> Row:
    out = dict(row)
    out["mentions"] = _loads(out.pop("mentions_json", None)) or []
    out["author_photo_url"] = file_url(out.pop("author_photo_file_id", None), company_id)
    return out


# --------------------------------------------------------------------------- posts

def list_posts(db: Db, ctx: RequestContext, mode: str, author_id: int | None, search: str | None, hidden_only: bool,
               page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_posts(db, ctx.company_id, ctx.user_id, mode, author_id, search, hidden_only, page, page_size)
    return total, [shape_post(r, ctx.company_id) for r in rows]


def get_post(db: Db, ctx: RequestContext, post_id: int) -> Row:
    return shape_post(repo.get_post(db, ctx.company_id, ctx.user_id, post_id), ctx.company_id)


def save_post(db: Db, ctx: RequestContext, post_id: int | None, body: PostIn, row_version: bytes | None) -> Row:
    row = repo.save_post(db, ctx.company_id, ctx.user_id, post_id, body.body, body.visibility, body.department_id,
                         body.branch_id, json.dumps(body.media_file_ids), json.dumps(body.mention_ids), row_version)
    return shape_post(row, ctx.company_id)


def delete_post(db: Db, ctx: RequestContext, post_id: int, row_version: bytes) -> None:
    repo.delete_post(db, ctx.company_id, ctx.user_id, post_id, row_version)


def view_post(db: Db, ctx: RequestContext, post_id: int) -> Row:
    return repo.view_post(db, ctx.company_id, ctx.user_id, post_id)


def pin_post(db: Db, ctx: RequestContext, post_id: int, pinned: bool) -> Row:
    return shape_post(repo.pin_post(db, ctx.company_id, ctx.user_id, post_id, pinned), ctx.company_id)


def hide_post(db: Db, ctx: RequestContext, post_id: int, hidden: bool, reason: str | None) -> Row:
    return shape_post(repo.hide_post(db, ctx.company_id, ctx.user_id, post_id, hidden, reason), ctx.company_id)


def react(db: Db, ctx: RequestContext, post_id: int, kind: str | None) -> Row:
    return shape_post(repo.react(db, ctx.company_id, ctx.user_id, post_id, kind), ctx.company_id)


def list_reactions(db: Db, ctx: RequestContext, post_id: int, kind: str | None, page: int,
                   page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_reactions(db, ctx.company_id, ctx.user_id, post_id, kind, page, page_size)
    return total, [{**r, "photo_url": file_url(r.pop("photo_file_id", None), ctx.company_id)} for r in rows]


# --------------------------------------------------------------------------- comments

def list_comments(db: Db, ctx: RequestContext, post_id: int, page: int, page_size: int) -> tuple[int, Rows]:
    total, top, replies = repo.list_comments(db, ctx.company_id, ctx.user_id, post_id, page, page_size)
    by_parent: dict[Any, Rows] = defaultdict(list)
    for r in replies:
        by_parent[r["parent_id"]].append(shape_comment(r, ctx.company_id))
    return total, [{**shape_comment(t, ctx.company_id), "replies": by_parent.get(t["id"], [])} for t in top]


def add_comment(db: Db, ctx: RequestContext, post_id: int, body: CommentIn) -> Row:
    row = repo.save_comment(db, ctx.company_id, ctx.user_id, None, post_id, body.parent_id, body.body,
                            json.dumps(body.mention_ids), None)
    return shape_comment(row, ctx.company_id)


def edit_comment(db: Db, ctx: RequestContext, comment_id: int, body: CommentEditIn, row_version: bytes) -> Row:
    row = repo.save_comment(db, ctx.company_id, ctx.user_id, comment_id, None, None, body.body,
                            json.dumps(body.mention_ids), row_version)
    return shape_comment(row, ctx.company_id)


def delete_comment(db: Db, ctx: RequestContext, comment_id: int, row_version: bytes) -> None:
    repo.delete_comment(db, ctx.company_id, ctx.user_id, comment_id, row_version)


def like_comment(db: Db, ctx: RequestContext, comment_id: int, liked: bool) -> Row:
    return shape_comment(repo.like_comment(db, ctx.company_id, ctx.user_id, comment_id, liked), ctx.company_id)


# --------------------------------------------------------------------------- settings

def get_settings(db: Db, ctx: RequestContext) -> Row:
    return repo.get_settings(db, ctx.company_id)


def save_settings(db: Db, ctx: RequestContext, body: SettingsIn, row_version: bytes | None) -> Row:
    return repo.save_settings(db, ctx.company_id, ctx.user_id, body.who_may_post, body.allow_comments,
                              body.max_media_per_post, row_version)


# --------------------------------------------------------------------------- surveys

def shape_survey(row: Row) -> Row:
    out = dict(row)
    if "questions_json" in out:
        out["questions"] = _loads(out.pop("questions_json")) or []
    if "audience_json" in out:
        out["audience"] = _loads(out.pop("audience_json")) or []
    return out


def list_surveys(db: Db, ctx: RequestContext, search: str | None, status: str | None, page: int,
                 page_size: int) -> tuple[int, Rows]:
    return repo.list_surveys(db, ctx.company_id, search, status, page, page_size)


def get_survey(db: Db, ctx: RequestContext, survey_id: int) -> Row:
    return shape_survey(repo.get_survey(db, ctx.company_id, survey_id))


def save_survey(db: Db, ctx: RequestContext, survey_id: int | None, body: SurveyIn, row_version: bytes | None) -> Row:
    questions = json.dumps([q.model_dump(by_alias=False) for q in body.questions])
    audience = json.dumps([a.model_dump(by_alias=False) for a in body.audience])
    return shape_survey(repo.save_survey(db, ctx.company_id, ctx.user_id, survey_id, body.title, body.description,
                                         body.is_anonymous, body.opens_on, body.closes_on, questions, audience,
                                         row_version))


def delete_survey(db: Db, ctx: RequestContext, survey_id: int, row_version: bytes) -> None:
    repo.delete_survey(db, ctx.company_id, ctx.user_id, survey_id, row_version)


def publish_survey(db: Db, ctx: RequestContext, survey_id: int, row_version: bytes) -> Row:
    return shape_survey(repo.survey_action(db, "publish", ctx.company_id, ctx.user_id, survey_id, row_version))


def close_survey(db: Db, ctx: RequestContext, survey_id: int, row_version: bytes) -> Row:
    return shape_survey(repo.survey_action(db, "close", ctx.company_id, ctx.user_id, survey_id, row_version))


def move_closing_date(db: Db, ctx: RequestContext, survey_id: int, closes_on: date | None, row_version: bytes) -> Row:
    return shape_survey(repo.survey_action(db, "closing_date", ctx.company_id, ctx.user_id, survey_id, row_version,
                                           closes_on=closes_on))


def _percent(part: int, whole: int) -> Decimal:
    if not whole:
        return Decimal("0.00")
    return (Decimal(part) * 100 / Decimal(whole)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def survey_results(db: Db, ctx: RequestContext, survey_id: int) -> Row:
    summary, questions, options, ratings, texts = repo.survey_results(db, ctx.company_id, survey_id)
    s = summary[0]
    opts, rates, txts = defaultdict(list), defaultdict(list), defaultdict(list)
    for o in options:
        opts[o["question_id"]].append(o)
    for r in ratings:
        rates[r["question_id"]].append({"value": r["rating_value"], "count": r["answer_count"]})
    for t in texts:
        txts[t["question_id"]].append(t["answer_text"])
    out_questions = []
    for q in questions:
        answered = q["answer_count"]
        out_questions.append({
            "question_id": q["id"], "sort_order": q["sort_order"], "question_type": q["question_type"],
            "question_text": q["question_text"], "is_required": q["is_required"], "answer_count": answered,
            "scale_min": q["scale_min"], "scale_max": q["scale_max"], "scale_min_label": q["scale_min_label"],
            "scale_max_label": q["scale_max_label"], "average_rating": q["average_rating"],
            # Shares of the people who answered the question (several options each for check boxes).
            "options": [{"option_id": o["option_id"], "option_text": o["option_text"], "count": o["answer_count"],
                         "percent": _percent(o["answer_count"], answered)} for o in opts[q["id"]]],
            "ratings": rates[q["id"]], "text_answers": txts[q["id"]],
        })
    return {"survey_id": s["id"], "title": s["title"], "is_anonymous": s["is_anonymous"], "status": s["status"],
            "opens_on": s["opens_on"], "closes_on": s["closes_on"], "audience_count": s["audience_count"],
            "response_count": s["response_count"], "skipped_count": s["skipped_count"],
            "response_rate": _percent(s["response_count"], s["audience_count"]), "questions": out_questions}


def _shape_response(row: Row) -> Row:
    out = dict(row)
    out["answers"] = _loads(out.pop("answers_json", None)) or []
    return out


def list_responses(db: Db, ctx: RequestContext, survey_id: int, page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_responses(db, ctx.company_id, ctx.user_id, survey_id, "engagement.survey_responses.view",
                                      False, page, page_size)
    return total, [_shape_response(r) for r in rows]


def export_responses(db: Db, ctx: RequestContext, survey_id: int) -> tuple[str, str]:
    """All answers as CSV, one row per response and one column per question (names for named surveys only)."""
    survey = get_survey(db, ctx, survey_id)
    _, rows = repo.list_responses(db, ctx.company_id, ctx.user_id, survey_id, "engagement.surveys.export", True, 1,
                                  EXPORT_ROWS)
    questions = survey["questions"]
    header = ["Submitted"] + ([] if survey["is_anonymous"] else ["Employee code", "Employee", "Department"])
    header += [q["question_text"] for q in questions]
    lines = []
    for r in rows:
        answers: dict[str, list[str]] = defaultdict(list)
        for a in _loads(r["answers_json"]) or []:
            value = a.get("option_text") or a.get("answer_text")
            if value is None and a.get("rating_value") is not None:
                value = str(a["rating_value"])
            if value is not None:
                answers[a["question_id"]].append(value)
        submitted = r["submitted_at"].date() if survey["is_anonymous"] else r["submitted_at"]
        line = [submitted]
        if not survey["is_anonymous"]:
            line += [r["employee_code"], r["employee_name"], r["department_name"]]
        line += ["; ".join(answers.get(q["id"], [])) for q in questions]
        lines.append(line)
    return f"survey-{survey_id}-responses.csv", _csv(header, lines)


def _csv(header: list[str], rows: list[list[Any]]) -> str:
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\r\n")
    w.writerow(header)
    for r in rows:
        w.writerow(["" if v is None else (v.isoformat() if isinstance(v, (date, datetime)) else v) for v in r])
    return "﻿" + out.getvalue()


# --------------------------------------------------------------------------- answering

def list_my_surveys(db: Db, ctx: RequestContext, filter_: str, page: int, page_size: int) -> tuple[int, Rows]:
    return repo.list_my_surveys(db, ctx.company_id, ctx.user_id, filter_, page, page_size)


def get_my_survey(db: Db, ctx: RequestContext, survey_id: int) -> Row:
    return shape_survey(repo.get_my_survey(db, ctx.company_id, ctx.user_id, survey_id))


def respond(db: Db, ctx: RequestContext, survey_id: int, body: ResponseIn) -> Row:
    answers = json.dumps([{"question_id": a.question_id, "option_ids": a.option_ids, "text": a.text,
                           "rating": a.rating} for a in body.answers])
    return shape_survey(repo.respond(db, ctx.company_id, ctx.user_id, survey_id, answers))


def skip(db: Db, ctx: RequestContext, survey_id: int) -> Row:
    return shape_survey(repo.skip(db, ctx.company_id, ctx.user_id, survey_id))
