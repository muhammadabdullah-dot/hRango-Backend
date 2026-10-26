"""Benefits data access. The only layer that knows the ben procedure names and parameters. Procedures for
employee-owned records (elections, health benefits, perks) take the permission code the endpoint required."""
from typing import Any

from app.core.db import Db


def _page(sets: list[list[dict[str, Any]]]) -> tuple[int, list[dict[str, Any]]]:
    return sets[0][0]["total"], sets[1]


def summary(db: Db, company_id: int, actor_user_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_benefit_summary", company_id=company_id, actor_user_id=actor_user_id)


# ---------------------------------------------------------------- plan years

def list_plan_years(db: Db, company_id: int, actor_user_id: int, search: str | None, status: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("ben.usp_plan_year_list", company_id=company_id, actor_user_id=actor_user_id,
                              search=search, status=status, page=page, page_size=page_size))


def get_plan_year(db: Db, company_id: int, actor_user_id: int, year_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_plan_year_get", company_id=company_id, actor_user_id=actor_user_id, id=year_id)


def save_plan_year(db: Db, company_id: int, actor_user_id: int, year_id: int | None, fields: dict[str, Any],
                   plan_ids_json: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("ben.usp_plan_year_save", company_id=company_id, actor_user_id=actor_user_id, id=year_id,
                       plan_ids=plan_ids_json, row_version=row_version, **fields)


def delete_plan_year(db: Db, company_id: int, actor_user_id: int, year_id: int, row_version: bytes) -> None:
    db.call("ben.usp_plan_year_delete", company_id=company_id, actor_user_id=actor_user_id, id=year_id,
            row_version=row_version)


# ---------------------------------------------------------------- benefit plans

def list_plans(db: Db, company_id: int, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("ben.usp_benefit_plan_list", company_id=company_id, page=page, page_size=page_size,
                              **filters))


def get_plan(db: Db, company_id: int, plan_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_benefit_plan_get", company_id=company_id, id=plan_id)


def save_plan(db: Db, company_id: int, actor_user_id: int, plan_id: int | None, fields: dict[str, Any],
              row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("ben.usp_benefit_plan_save", company_id=company_id, actor_user_id=actor_user_id, id=plan_id,
                       row_version=row_version, **fields)


def duplicate_plan(db: Db, company_id: int, actor_user_id: int, plan_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_benefit_plan_duplicate", company_id=company_id, actor_user_id=actor_user_id,
                       id=plan_id)


def delete_plan(db: Db, company_id: int, actor_user_id: int, plan_id: int, row_version: bytes) -> None:
    db.call("ben.usp_benefit_plan_delete", company_id=company_id, actor_user_id=actor_user_id, id=plan_id,
            row_version=row_version)


# ---------------------------------------------------------------- enrollment windows

def list_windows(db: Db, company_id: int, filters: dict[str, Any], page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("ben.usp_enrollment_window_list", company_id=company_id, page=page,
                              page_size=page_size, **filters))


def get_window(db: Db, company_id: int, window_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_enrollment_window_get", company_id=company_id, id=window_id)


def save_window(db: Db, company_id: int, actor_user_id: int, window_id: int | None, fields: dict[str, Any],
                plan_ids_json: str, employee_ids_json: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("ben.usp_enrollment_window_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=window_id, plan_ids=plan_ids_json, employee_ids=employee_ids_json,
                       row_version=row_version, **fields)


def delete_window(db: Db, company_id: int, actor_user_id: int, window_id: int, row_version: bytes) -> None:
    db.call("ben.usp_enrollment_window_delete", company_id=company_id, actor_user_id=actor_user_id, id=window_id,
            row_version=row_version)


# ---------------------------------------------------------------- elections and employees

def list_elections(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("ben.usp_election_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_election(db: Db, company_id: int, actor_user_id: int, code: str, election_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_election_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=election_id)


def save_election(db: Db, company_id: int, actor_user_id: int, code: str, election_id: int | None,
                  fields: dict[str, Any], plan_ids_json: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("ben.usp_election_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=election_id, plan_ids=plan_ids_json, row_version=row_version,
                       **fields)


def decide_election(db: Db, company_id: int, actor_user_id: int, code: str, election_id: int, decision: str,
                    remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("ben.usp_election_decide", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=election_id, decision=decision, remarks=remarks,
                       row_version=row_version)


def list_employees(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("ben.usp_benefit_employee_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


# ---------------------------------------------------------------- files

def list_files(db: Db, company_id: int, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("ben.usp_benefit_file_list", company_id=company_id, page=page, page_size=page_size,
                              **filters))


def add_file(db: Db, company_id: int, actor_user_id: int, plan_id: int, file_id: int) -> dict[str, Any]:
    return db.call_one("ben.usp_benefit_file_add", company_id=company_id, actor_user_id=actor_user_id,
                       plan_id=plan_id, file_id=file_id)


def delete_file(db: Db, company_id: int, actor_user_id: int, attachment_id: int, row_version: bytes) -> None:
    db.call("ben.usp_benefit_file_delete", company_id=company_id, actor_user_id=actor_user_id, id=attachment_id,
            row_version=row_version)


# ---------------------------------------------------------------- health benefits and perks (same shape)
# what: health_benefit or perk -> ben.usp_<what>_list / _get / _save / _delete.
OWNED = ("health_benefit", "perk")


def _owned(what: str) -> str:
    if what not in OWNED:
        raise ValueError(f"unknown benefits record {what!r}")
    return what


def list_owned(db: Db, what: str, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets(f"ben.usp_{_owned(what)}_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_owned(db: Db, what: str, company_id: int, actor_user_id: int, code: str, record_id: int) -> dict[str, Any]:
    return db.call_one(f"ben.usp_{_owned(what)}_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=record_id)


def save_owned(db: Db, what: str, company_id: int, actor_user_id: int, code: str, record_id: int | None,
               fields: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    return db.call_one(f"ben.usp_{_owned(what)}_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=record_id, row_version=row_version, **fields)


def delete_owned(db: Db, what: str, company_id: int, actor_user_id: int, code: str, record_id: int,
                 row_version: bytes) -> None:
    db.call(f"ben.usp_{_owned(what)}_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=record_id, row_version=row_version)
