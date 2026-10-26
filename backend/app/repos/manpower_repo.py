"""Manpower planning data access. The only layer that knows the mp procedure names and parameters.
Procedures that apply scope take the permission code the endpoint required."""
from datetime import date
from decimal import Decimal
from typing import Any

from app.core.db import Db


def _page(sets: list[list[dict[str, Any]]]) -> tuple[int, list[dict[str, Any]]]:
    return sets[0][0]["total"], sets[1]


# ---------------------------------------------------------------- budget durations

def list_durations(db: Db, company_id: int, search: str | None, is_current: bool | None,
                   page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("mp.usp_budget_duration_list", company_id=company_id, search=search,
                              is_current=is_current, page=page, page_size=page_size))


def get_duration(db: Db, company_id: int, duration_id: int) -> dict[str, Any]:
    return db.call_one("mp.usp_budget_duration_get", company_id=company_id, id=duration_id)


def save_duration(db: Db, company_id: int, actor_user_id: int, duration_id: int | None, name: str,
                  start_date: date, end_date: date, is_current: bool, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("mp.usp_budget_duration_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=duration_id, name=name, start_date=start_date, end_date=end_date, is_current=is_current,
                       row_version=row_version)


def delete_duration(db: Db, company_id: int, actor_user_id: int, duration_id: int, row_version: bytes) -> None:
    db.call("mp.usp_budget_duration_delete", company_id=company_id, actor_user_id=actor_user_id, id=duration_id,
            row_version=row_version)


# ---------------------------------------------------------------- position titles

def list_position_titles(db: Db, company_id: int, search: str | None, page: int,
                         page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("mp.usp_position_title_list", company_id=company_id, search=search, page=page,
                              page_size=page_size))


# ---------------------------------------------------------------- positions

def list_positions(db: Db, company_id: int, filters: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("mp.usp_position_list", company_id=company_id, page=page, page_size=page_size,
                              **filters))


def get_position(db: Db, company_id: int, position_id: int) -> dict[str, Any]:
    return db.call_one("mp.usp_position_get", company_id=company_id, id=position_id)


def save_position(db: Db, company_id: int, actor_user_id: int, position_id: int | None, fields: dict[str, Any],
                  row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("mp.usp_position_save", company_id=company_id, actor_user_id=actor_user_id, id=position_id,
                       row_version=row_version, **fields)


def delete_position(db: Db, company_id: int, actor_user_id: int, position_id: int, row_version: bytes) -> None:
    db.call("mp.usp_position_delete", company_id=company_id, actor_user_id=actor_user_id, id=position_id,
            row_version=row_version)


def import_positions(db: Db, company_id: int, actor_user_id: int, rows_json: str) -> tuple[int, list[dict[str, Any]]]:
    created, errors = db.call_sets("mp.usp_position_import", company_id=company_id, actor_user_id=actor_user_id,
                                   rows=rows_json)
    return created[0]["created"], errors


def list_salary_ranges(db: Db, company_id: int, position_id: int) -> list[dict[str, Any]]:
    return db.call("mp.usp_position_salary_range_list", company_id=company_id, position_id=position_id)


def save_salary_range(db: Db, company_id: int, actor_user_id: int, position_id: int, effective_date: date,
                      min_salary: Decimal, max_salary: Decimal) -> list[dict[str, Any]]:
    return db.call("mp.usp_position_salary_range_save", company_id=company_id, actor_user_id=actor_user_id,
                   position_id=position_id, effective_date=effective_date, min_salary=min_salary,
                   max_salary=max_salary)


# ---------------------------------------------------------------- plans

def list_plans(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("mp.usp_manpower_plan_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_plan(db: Db, company_id: int, actor_user_id: int, code: str, plan_id: int) -> list[list[dict[str, Any]]]:
    return db.call_sets("mp.usp_manpower_plan_get", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=plan_id)


def save_plan(db: Db, company_id: int, actor_user_id: int, code: str, plan_id: int | None, fields: dict[str, Any],
              lines_json: str, row_version: bytes | None) -> list[list[dict[str, Any]]]:
    return db.call_sets("mp.usp_manpower_plan_save", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=plan_id, lines=lines_json, row_version=row_version, **fields)


def delete_plan(db: Db, company_id: int, actor_user_id: int, code: str, plan_id: int, row_version: bytes) -> None:
    db.call("mp.usp_manpower_plan_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=plan_id, row_version=row_version)


# ---------------------------------------------------------------- e-budgets

def list_budgets(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("mp.usp_e_budget_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_budget(db: Db, company_id: int, actor_user_id: int, code: str, budget_id: int) -> dict[str, Any]:
    return db.call_one("mp.usp_e_budget_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=budget_id)


def save_budget(db: Db, company_id: int, actor_user_id: int, code: str, budget_id: int | None,
                fields: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("mp.usp_e_budget_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=budget_id, row_version=row_version, **fields)


def delete_budget(db: Db, company_id: int, actor_user_id: int, code: str, budget_id: int, row_version: bytes) -> None:
    db.call("mp.usp_e_budget_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=budget_id, row_version=row_version)


def decide_budget(db: Db, company_id: int, actor_user_id: int, code: str, budget_id: int, decision: str,
                  remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("mp.usp_e_budget_decide", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=budget_id, decision=decision, remarks=remarks,
                       row_version=row_version)


# ---------------------------------------------------------------- open positions

def list_open_positions(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                        page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("mp.usp_open_position_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_open_position(db: Db, company_id: int, actor_user_id: int, code: str, open_id: int) -> dict[str, Any]:
    return db.call_one("mp.usp_open_position_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=open_id)


def save_open_position(db: Db, company_id: int, actor_user_id: int, code: str, open_id: int, total_positions: int,
                       end_date: date | None, jd_file_id: int | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("mp.usp_open_position_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=open_id, total_positions=total_positions, end_date=end_date,
                       jd_file_id=jd_file_id, row_version=row_version)


def set_open_position_status(db: Db, company_id: int, actor_user_id: int, code: str, open_id: int, status: str,
                             row_version: bytes) -> dict[str, Any]:
    return db.call_one("mp.usp_open_position_status", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=open_id, status=status, row_version=row_version)


def open_position_jd(db: Db, company_id: int, actor_user_id: int, code: str, open_id: int) -> dict[str, Any]:
    return db.call_one("mp.usp_open_position_jd", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=open_id)
