"""Warning data access (procedures in the att schema). The only layer that knows procedure names."""
from datetime import date
from typing import Any

from app.core.db import Db


def _page(db: Db, proc: str, **params: Any) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets(proc, **params)
    return total[0]["total"], rows


def list_policies(db: Db, company_id: int, search: str | None, applies_to: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "att.usp_warning_policy_list", company_id=company_id, search=search, applies_to=applies_to,
                 page=page, page_size=page_size)


def get_policy(db: Db, company_id: int, policy_id: int) -> dict[str, Any]:
    return db.call_one("att.usp_warning_policy_get", company_id=company_id, id=policy_id)


def save_policy(db: Db, company_id: int, actor_user_id: int, policy_id: int | None, title: str, applies_to: str,
                period: str, grace_minutes: int | None, week_start_day: str | None, week_end_day: str | None,
                is_active: bool, rules: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("att.usp_warning_policy_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=policy_id, title=title, applies_to=applies_to, period=period, grace_minutes=grace_minutes,
                       week_start_day=week_start_day, week_end_day=week_end_day, is_active=is_active, rules=rules,
                       row_version=row_version)


def delete_policy(db: Db, company_id: int, actor_user_id: int, policy_id: int, row_version: bytes) -> None:
    db.call("att.usp_warning_policy_delete", company_id=company_id, actor_user_id=actor_user_id, id=policy_id,
            row_version=row_version)


def save_penalties(db: Db, company_id: int, actor_user_id: int, policy_id: int, penalties: str,
                   row_version: bytes) -> dict[str, Any]:
    return db.call_one("att.usp_warning_penalty_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=policy_id, penalties=penalties, row_version=row_version)


def list_penalties(db: Db, company_id: int, policy_id: int | None, page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "att.usp_warning_penalty_list", company_id=company_id, policy_id=policy_id, page=page,
                 page_size=page_size)


def list_warnings(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int | None,
                  policy_id: int | None, applies_to: str | None, from_date: date | None, to_date: date | None,
                  search: str | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "att.usp_warning_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, employee_id=employee_id, warning_policy_id=policy_id,
                 applies_to=applies_to, from_date=from_date, to_date=to_date, search=search, page=page,
                 page_size=page_size)


def raise_warnings(db: Db, company_id: int, actor_user_id: int, permission_code: str, from_date: date,
                   to_date: date, employee_id: int | None, policy_id: int | None) -> dict[str, Any]:
    return db.call_one("att.usp_warning_raise", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, from_date=from_date, to_date=to_date,
                       employee_id=employee_id, warning_policy_id=policy_id)


def list_history(db: Db, company_id: int, policy_id: int | None, page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "att.usp_warning_history_list", company_id=company_id, policy_id=policy_id, page=page,
                 page_size=page_size)
