"""Project management task data access (pm task procedures)."""
from typing import Any

from app.core.db import Db

Rows = list[dict[str, Any]]


def list_tasks(db: Db, company_id: int, actor_user_id: int, workspace_id: int, filters: dict[str, Any],
               page: int, page_size: int) -> tuple[int, Rows, Rows, Rows]:
    total, rows, groups, levels = db.call_sets("pm.usp_task_list", company_id=company_id, actor_user_id=actor_user_id,
                                               workspace_id=workspace_id, **filters, page=page, page_size=page_size)
    return total[0]["total"], rows, groups, levels


def get_task(db: Db, company_id: int, actor_user_id: int, task_id: int) -> list[Rows]:
    return db.call_sets("pm.usp_task_get", company_id=company_id, actor_user_id=actor_user_id, id=task_id)


def save_task(db: Db, company_id: int, actor_user_id: int, task_id: int | None, values: dict[str, Any],
              row_version: bytes | None) -> list[Rows]:
    return db.call_sets("pm.usp_task_save", company_id=company_id, actor_user_id=actor_user_id, id=task_id, **values,
                        row_version=row_version)


def set_status(db: Db, company_id: int, actor_user_id: int, task_id: int, status_id: int,
               row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_task_status_set", company_id=company_id, actor_user_id=actor_user_id, id=task_id,
                        status_id=status_id, row_version=row_version)


def set_cover(db: Db, company_id: int, actor_user_id: int, task_id: int, file_id: int | None,
              row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_task_cover_set", company_id=company_id, actor_user_id=actor_user_id, id=task_id,
                        file_id=file_id, row_version=row_version)


def save_assignees(db: Db, company_id: int, actor_user_id: int, task_id: int, assignees: str) -> list[Rows]:
    return db.call_sets("pm.usp_task_assignees_save", company_id=company_id, actor_user_id=actor_user_id, id=task_id,
                        assignees=assignees)


def save_tags(db: Db, company_id: int, actor_user_id: int, task_id: int, tag_ids: str) -> list[Rows]:
    return db.call_sets("pm.usp_task_tags_save", company_id=company_id, actor_user_id=actor_user_id, id=task_id,
                        tag_ids=tag_ids)


def move_task(db: Db, company_id: int, actor_user_id: int, task_id: int, workspace_id: int | None,
              task_list_id: int | None, parent_task_id: int | None, sort_order: int | None,
              row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_task_move", company_id=company_id, actor_user_id=actor_user_id, id=task_id,
                        workspace_id=workspace_id, task_list_id=task_list_id, parent_task_id=parent_task_id,
                        sort_order=sort_order, row_version=row_version)


def convert_to_list(db: Db, company_id: int, actor_user_id: int, task_id: int, row_version: bytes) -> dict[str, Any]:
    return db.call_one("pm.usp_task_convert_to_list", company_id=company_id, actor_user_id=actor_user_id, id=task_id,
                       row_version=row_version)


def delete_task(db: Db, company_id: int, actor_user_id: int, task_id: int, row_version: bytes) -> None:
    db.call("pm.usp_task_delete", company_id=company_id, actor_user_id=actor_user_id, id=task_id, row_version=row_version)


def save_field_value(db: Db, company_id: int, actor_user_id: int, task_id: int, field_id: int,
                     value: str | None) -> list[Rows]:
    return db.call_sets("pm.usp_task_field_value_save", company_id=company_id, actor_user_id=actor_user_id,
                        task_id=task_id, custom_field_id=field_id, field_value=value)


def add_dependency(db: Db, company_id: int, actor_user_id: int, task_id: int, other_task_id: int,
                   kind: str) -> list[Rows]:
    return db.call_sets("pm.usp_task_dependency_add", company_id=company_id, actor_user_id=actor_user_id,
                        task_id=task_id, other_task_id=other_task_id, kind=kind)


def delete_dependency(db: Db, company_id: int, actor_user_id: int, dependency_id: int) -> None:
    db.call("pm.usp_task_dependency_delete", company_id=company_id, actor_user_id=actor_user_id, id=dependency_id)


def save_checklist_item(db: Db, company_id: int, actor_user_id: int, item_id: int | None, task_id: int | None,
                        item_text: str, is_done: bool, sort_order: int | None,
                        row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_checklist_item_save", company_id=company_id, actor_user_id=actor_user_id, id=item_id,
                       task_id=task_id, item_text=item_text, is_done=is_done, sort_order=sort_order,
                       row_version=row_version)


def delete_checklist_item(db: Db, company_id: int, actor_user_id: int, item_id: int) -> None:
    db.call("pm.usp_checklist_item_delete", company_id=company_id, actor_user_id=actor_user_id, id=item_id)


def task_activity(db: Db, company_id: int, actor_user_id: int, task_id: int, page: int,
                  page_size: int) -> tuple[int, Rows]:
    total, rows = db.call_sets("pm.usp_task_activity", company_id=company_id, actor_user_id=actor_user_id,
                               task_id=task_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def request_extension(db: Db, company_id: int, actor_user_id: int, task_id: int, new_due_date, reason: str) -> list[Rows]:
    return db.call_sets("pm.usp_task_extension_request", company_id=company_id, actor_user_id=actor_user_id,
                        task_id=task_id, new_due_date=new_due_date, reason=reason)


def decide_extension(db: Db, company_id: int, actor_user_id: int, extension_id: int, is_approved: bool,
                     remarks: str | None, row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_task_extension_decide", company_id=company_id, actor_user_id=actor_user_id,
                        id=extension_id, is_approved=is_approved, remarks=remarks, row_version=row_version)
