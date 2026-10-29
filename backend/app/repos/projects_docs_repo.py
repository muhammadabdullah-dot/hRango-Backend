"""Project management Docs data access."""
from typing import Any

from app.core.db import Db

Rows = list[dict[str, Any]]
# usp_doc_list and every doc write answer: total, docs, contributors, linked tasks.
DocSets = tuple[int, Rows, Rows, Rows]


def _sets(sets: list[Rows]) -> DocSets:
    total, docs, contributors, links = sets
    return total[0]["total"], docs, contributors, links


def list_docs(db: Db, company_id: int, actor_user_id: int, workspace_id: int | None, folder_id: int | None,
              task_list_id: int | None, search: str | None, include_archived: bool, page: int,
              page_size: int) -> DocSets:
    return _sets(db.call_sets("pm.usp_doc_list", company_id=company_id, actor_user_id=actor_user_id,
                              workspace_id=workspace_id, folder_id=folder_id, task_list_id=task_list_id, search=search,
                              include_archived=include_archived, page=page, page_size=page_size))


def get_doc(db: Db, company_id: int, actor_user_id: int, doc_id: int) -> DocSets:
    return _sets(db.call_sets("pm.usp_doc_list", company_id=company_id, actor_user_id=actor_user_id, id=doc_id))


def save_doc(db: Db, company_id: int, actor_user_id: int, doc_id: int | None, workspace_id: int | None,
             values: dict[str, Any], row_version: bytes | None) -> DocSets:
    return _sets(db.call_sets("pm.usp_doc_save", company_id=company_id, actor_user_id=actor_user_id, id=doc_id,
                              workspace_id=workspace_id, **values, row_version=row_version))


def delete_doc(db: Db, company_id: int, actor_user_id: int, doc_id: int, row_version: bytes) -> None:
    db.call("pm.usp_doc_delete", company_id=company_id, actor_user_id=actor_user_id, id=doc_id,
            row_version=row_version)


def archive_doc(db: Db, company_id: int, actor_user_id: int, doc_id: int, archived: bool,
                row_version: bytes) -> DocSets:
    return _sets(db.call_sets("pm.usp_doc_archive", company_id=company_id, actor_user_id=actor_user_id, id=doc_id,
                              archived=archived, row_version=row_version))


def duplicate_doc(db: Db, company_id: int, actor_user_id: int, doc_id: int, title: str | None) -> DocSets:
    return _sets(db.call_sets("pm.usp_doc_duplicate", company_id=company_id, actor_user_id=actor_user_id, id=doc_id,
                              title=title))


def set_doc_tasks(db: Db, company_id: int, actor_user_id: int, doc_id: int, task_ids: str) -> DocSets:
    return _sets(db.call_sets("pm.usp_doc_tasks_set", company_id=company_id, actor_user_id=actor_user_id, id=doc_id,
                              task_ids=task_ids))


def list_comments(db: Db, company_id: int, actor_user_id: int, doc_id: int) -> Rows:
    return db.call("pm.usp_doc_comment_list", company_id=company_id, actor_user_id=actor_user_id, doc_id=doc_id)


def add_comment(db: Db, company_id: int, actor_user_id: int, doc_id: int, body: str,
                parent_id: int | None) -> dict[str, Any]:
    return db.call_one("pm.usp_doc_comment_add", company_id=company_id, actor_user_id=actor_user_id, doc_id=doc_id,
                       body=body, parent_id=parent_id)
