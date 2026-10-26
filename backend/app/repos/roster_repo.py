"""Roster data access. The only layer that knows procedure names and parameters."""
import json
from datetime import date
from typing import Any

from app.core.db import Db


def list_groups(db: Db, company_id: int, search: str | None, is_active: bool | None,
                page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sch.usp_roster_group_list", company_id=company_id, search=search,
                               is_active=is_active, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_group(db: Db, company_id: int, group_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    group, days = db.call_sets("sch.usp_roster_group_get", company_id=company_id, id=group_id)
    return group[0], days


def save_group(db: Db, company_id: int, actor_user_id: int, group_id: int | None, title: str, from_date: date,
               to_date: date | None, description: str | None, is_active: bool, days: list[dict[str, Any]],
               row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    group, rows = db.call_sets("sch.usp_roster_group_save", company_id=company_id, actor_user_id=actor_user_id,
                               id=group_id, title=title, from_date=from_date, to_date=to_date,
                               description=description, is_active=is_active, days=json.dumps(days),
                               row_version=row_version)
    return group[0], rows


def delete_group(db: Db, company_id: int, actor_user_id: int, group_id: int, row_version: bytes) -> None:
    db.call("sch.usp_roster_group_delete", company_id=company_id, actor_user_id=actor_user_id, id=group_id,
            row_version=row_version)


def list_enrolments(db: Db, company_id: int, actor_user_id: int, permission_code: str, group_id: int,
                    status: str | None, search: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sch.usp_roster_member_list", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, roster_group_id=group_id, status=status,
                               search=search, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_enrolment(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                  enrolment_id: int) -> dict[str, Any]:
    return db.call_one("sch.usp_roster_member_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=enrolment_id)


def enrol(db: Db, company_id: int, actor_user_id: int, permission_code: str, group_id: int,
          employee_ids: list[int], start_date: date, end_date: date | None) -> list[dict[str, Any]]:
    return db.call("sch.usp_roster_member_enroll", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=permission_code, roster_group_id=group_id,
                   employee_ids=json.dumps(employee_ids), start_date=start_date, end_date=end_date)


def save_enrolment(db: Db, company_id: int, actor_user_id: int, permission_code: str, enrolment_id: int,
                   start_date: date, end_date: date | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("sch.usp_roster_member_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=enrolment_id, start_date=start_date,
                       end_date=end_date, row_version=row_version)


def delete_enrolment(db: Db, company_id: int, actor_user_id: int, permission_code: str, enrolment_id: int,
                     row_version: bytes) -> None:
    db.call("sch.usp_roster_member_delete", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, id=enrolment_id, row_version=row_version)
