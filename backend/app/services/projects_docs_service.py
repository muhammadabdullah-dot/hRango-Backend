"""Project management Docs rules. Who may read, write, archive and delete a doc is decided in the pm
procedures (workspace role, owner, private docs). Here: word and character counts and reading time from
the HTML, JSON columns, and gathering contributors and linked tasks onto each doc."""
import html
import json
import math
import re
from collections import defaultdict
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import projects_docs_repo
from app.repos.projects_docs_repo import DocSets
from app.schemas.projects_docs import DocIn
from app.services.projects_service import dumps

Rows = list[dict[str, Any]]
WORDS_PER_MINUTE = 200
_TAG = re.compile(r"<[^>]+>")


def text_of(content_html: str | None) -> str:
    """The visible text of the doc's HTML, whitespace collapsed."""
    if not content_html:
        return ""
    return " ".join(html.unescape(_TAG.sub(" ", content_html)).split())


def counts(content_html: str | None) -> tuple[int, int]:
    """(words, characters) of the visible text."""
    text = text_of(content_html)
    return len(text.split()), len(text)


def _loads(text: str | None) -> Any:
    return json.loads(text) if text else None


def _shape(sets: DocSets) -> tuple[int, Rows]:
    total, docs, contributors, links = sets
    people: dict[int, Rows] = defaultdict(list)
    for c in contributors:
        people[c["doc_id"]].append({"id": c["id"], "name": c["name"]})
    linked: dict[int, list[int]] = defaultdict(list)
    for x in links:
        linked[x["doc_id"]].append(x["task_id"])
    out = []
    for d in docs:
        row = dict(d)
        row["content"] = _loads(row.get("content"))
        row["settings"] = _loads(row.get("settings"))
        row["contributors"] = people[d["id"]]
        row["linked_task_ids"] = linked[d["id"]]
        words = row.get("word_count") or 0
        row["reading_minutes"] = math.ceil(words / WORDS_PER_MINUTE) if words else 0
        out.append(row)
    return total, out


def _one(sets: DocSets) -> dict[str, Any]:
    return _shape(sets)[1][0]


def list_docs(db: Db, ctx: RequestContext, workspace_id: int, folder_id: int | None, list_id: int | None,
              q: str | None, include_archived: bool, page: int, page_size: int) -> tuple[int, Rows]:
    return _shape(projects_docs_repo.list_docs(db, ctx.company_id, ctx.user_id, workspace_id, folder_id, list_id, q,
                                               include_archived, page, page_size))


def get_doc(db: Db, ctx: RequestContext, doc_id: int) -> dict[str, Any]:
    return _one(projects_docs_repo.get_doc(db, ctx.company_id, ctx.user_id, doc_id))


def _values(body: DocIn) -> dict[str, Any]:
    words, characters = counts(body.content_html)
    return {"title": body.title, "content": dumps(body.content), "content_html": body.content_html,
            "visibility": body.visibility, "folder_id": body.folder_id, "task_list_id": body.list_id,
            "cover_file_id": body.cover_file_id,
            "settings": dumps(body.settings) if body.settings is not None else None,
            "word_count": words, "character_count": characters}


def create_doc(db: Db, ctx: RequestContext, workspace_id: int, body: DocIn) -> dict[str, Any]:
    return _one(projects_docs_repo.save_doc(db, ctx.company_id, ctx.user_id, None, workspace_id, _values(body), None))


def update_doc(db: Db, ctx: RequestContext, doc_id: int, body: DocIn, row_version: bytes) -> dict[str, Any]:
    return _one(projects_docs_repo.save_doc(db, ctx.company_id, ctx.user_id, doc_id, None, _values(body),
                                            row_version))


def delete_doc(db: Db, ctx: RequestContext, doc_id: int, row_version: bytes) -> None:
    projects_docs_repo.delete_doc(db, ctx.company_id, ctx.user_id, doc_id, row_version)


def archive_doc(db: Db, ctx: RequestContext, doc_id: int, archived: bool, row_version: bytes) -> dict[str, Any]:
    return _one(projects_docs_repo.archive_doc(db, ctx.company_id, ctx.user_id, doc_id, archived, row_version))


def duplicate_doc(db: Db, ctx: RequestContext, doc_id: int, title: str | None) -> dict[str, Any]:
    return _one(projects_docs_repo.duplicate_doc(db, ctx.company_id, ctx.user_id, doc_id, title))


def set_doc_tasks(db: Db, ctx: RequestContext, doc_id: int, task_ids: list[int]) -> dict[str, Any]:
    return _one(projects_docs_repo.set_doc_tasks(db, ctx.company_id, ctx.user_id, doc_id, dumps(task_ids)))


def export_doc(db: Db, ctx: RequestContext, doc_id: int, fmt: str) -> None:
    """TODO(pm): render contentHtml to PDF / DOCX (a converter is not chosen yet)."""
    get_doc(db, ctx, doc_id)  # 404 when the caller cannot open it
    raise AppError(501, "EXPORT_NOT_AVAILABLE", f"Exporting a doc as {fmt.upper()} is not available yet.")


def list_comments(db: Db, ctx: RequestContext, doc_id: int) -> Rows:
    return projects_docs_repo.list_comments(db, ctx.company_id, ctx.user_id, doc_id)


def add_comment(db: Db, ctx: RequestContext, doc_id: int, body: str, parent_id: int | None) -> dict[str, Any]:
    return projects_docs_repo.add_comment(db, ctx.company_id, ctx.user_id, doc_id, body, parent_id)
