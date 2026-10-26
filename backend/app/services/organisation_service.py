"""Organisation rules. Checks that need the database (duplicates, loops, links) live in the
procedures; rules that do not, and anything that spans several procedures, live here.

The Control Panel lists are company-wide settings, not employee-owned records, so the scope a
permission is held with does not narrow them: holding the permission is enough.
"""
import json
from typing import Any

from app.core.db import Db
from app.core.default_roles import expanded as default_roles
from app.core.errors import AppError, invalid
from app.middlewares.auth import RequestContext
from app.repos import organisation_repo

LOOKUP_KINDS = {"locations": "location", "areas": "area", "branches": "branch", "departments": "department",
                "divisions": "division", "cost-centers": "cost_center", "designations": "designation",
                "job-titles": "job_title", "grades": "grade", "job-levels": "job_level",
                "employee-groups": "employee_group", "employment-types": "employment_type"}


# ---------------------------------------------------------------- departments (the worked example)

def list_departments(db: Db, ctx: RequestContext, search: str | None, parent_id: int | None,
                     page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return organisation_repo.list_departments(db, ctx.company_id, search, parent_id, page, page_size)


def get_department(db: Db, ctx: RequestContext, department_id: int) -> dict[str, Any]:
    return organisation_repo.get_department(db, ctx.company_id, department_id)


def save_department(db: Db, ctx: RequestContext, department_id: int | None, name: str,
                    parent_id: int | None, head_id: int | None, row_version: bytes | None) -> dict[str, Any]:
    if department_id is not None and parent_id == department_id:
        raise AppError(422, "VALIDATION_FAILED", "A department cannot sit under itself.", {"parentId": "A department cannot sit under itself."})
    return organisation_repo.save_department(db, ctx.company_id, ctx.user_id, department_id, name,
                                             parent_id, head_id, row_version)


def delete_department(db: Db, ctx: RequestContext, department_id: int, row_version: bytes) -> None:
    organisation_repo.delete_department(db, ctx.company_id, ctx.user_id, department_id, row_version)


# ---------------------------------------------------------------- companies and general settings

def get_company(db: Db, ctx: RequestContext, company_id: int) -> dict[str, Any]:
    return organisation_repo.get_company(db, ctx.company_id, ctx.user_id, company_id)


def list_companies(db: Db, ctx: RequestContext, search: str | None, page: int, page_size: int):
    return organisation_repo.list_companies(db, ctx.company_id, ctx.user_id, search, page, page_size)


def save_company(db: Db, ctx: RequestContext, company_id: int | None, fields: dict[str, Any],
                 row_version: bytes | None) -> dict[str, Any]:
    if company_id is not None:
        return organisation_repo.save_company(db, ctx.company_id, ctx.user_id, company_id, fields, row_version)
    # A new company: the row, its default roles, and its Company Administrator role for its creator.
    with db.transaction():
        row = organisation_repo.save_company(db, ctx.company_id, ctx.user_id, None, fields, None)
        organisation_repo.apply_default_roles(db, int(row["id"]), json.dumps(default_roles()))
        organisation_repo.grant_company_creator(db, int(row["id"]), ctx.user_id)
    return row


def my_companies(db: Db, ctx: RequestContext) -> list[dict[str, Any]]:
    _, rows = organisation_repo.list_companies(db, ctx.company_id, ctx.user_id, None, 1, 100)
    return rows


# ---------------------------------------------------------------- locations, areas, branches, job titles

def list_locations(db: Db, ctx: RequestContext, search: str | None, page: int, page_size: int):
    return organisation_repo.list_locations(db, ctx.company_id, search, page, page_size)


def get_location(db: Db, ctx: RequestContext, location_id: int) -> dict[str, Any]:
    return organisation_repo.get_location(db, ctx.company_id, location_id)


def save_location(db: Db, ctx: RequestContext, location_id: int | None, f: dict[str, Any],
                  row_version: bytes | None) -> dict[str, Any]:
    _both_or_neither(f)
    return organisation_repo.save_location(db, ctx.company_id, ctx.user_id, location_id, f["name"],
                                           f.get("employee_prefix"), f.get("description"), f.get("latitude"),
                                           f.get("longitude"), row_version)


def delete_location(db: Db, ctx: RequestContext, location_id: int, row_version: bytes) -> None:
    organisation_repo.delete_location(db, ctx.company_id, ctx.user_id, location_id, row_version)


def list_areas(db: Db, ctx: RequestContext, search: str | None, location_id: int | None, page: int, page_size: int):
    return organisation_repo.list_areas(db, ctx.company_id, search, location_id, page, page_size)


def get_area(db: Db, ctx: RequestContext, area_id: int) -> dict[str, Any]:
    return organisation_repo.get_area(db, ctx.company_id, area_id)


def save_area(db: Db, ctx: RequestContext, area_id: int | None, f: dict[str, Any],
              row_version: bytes | None) -> dict[str, Any]:
    return organisation_repo.save_area(db, ctx.company_id, ctx.user_id, area_id, f["location_id"], f["name"],
                                       f.get("description"), row_version)


def delete_area(db: Db, ctx: RequestContext, area_id: int, row_version: bytes) -> None:
    organisation_repo.delete_area(db, ctx.company_id, ctx.user_id, area_id, row_version)


def list_branches(db: Db, ctx: RequestContext, search: str | None, location_id: int | None, area_id: int | None,
                  page: int, page_size: int):
    return organisation_repo.list_branches(db, ctx.company_id, search, location_id, area_id, page, page_size)


def get_branch(db: Db, ctx: RequestContext, branch_id: int) -> dict[str, Any]:
    return organisation_repo.get_branch(db, ctx.company_id, branch_id)


def save_branch(db: Db, ctx: RequestContext, branch_id: int | None, f: dict[str, Any],
                row_version: bytes | None) -> dict[str, Any]:
    _both_or_neither(f)
    if f.get("city_id") is not None and f.get("state_id") is None:
        raise invalid("Choose the state before the city.", "stateId")
    if f.get("state_id") is not None and f.get("country_id") is None:
        raise invalid("Choose the country before the state.", "countryId")
    return organisation_repo.save_branch(db, ctx.company_id, ctx.user_id, branch_id, f, row_version)


def delete_branch(db: Db, ctx: RequestContext, branch_id: int, row_version: bytes) -> None:
    organisation_repo.delete_branch(db, ctx.company_id, ctx.user_id, branch_id, row_version)


def list_job_titles(db: Db, ctx: RequestContext, search: str | None, page: int, page_size: int):
    return organisation_repo.list_job_titles(db, ctx.company_id, search, page, page_size)


def get_job_title(db: Db, ctx: RequestContext, job_title_id: int) -> dict[str, Any]:
    return organisation_repo.get_job_title(db, ctx.company_id, job_title_id)


def save_job_title(db: Db, ctx: RequestContext, job_title_id: int | None, f: dict[str, Any],
                   row_version: bytes | None) -> dict[str, Any]:
    return organisation_repo.save_job_title(db, ctx.company_id, ctx.user_id, job_title_id, f["name"],
                                            f["limit_head_count"], f.get("max_head_count"), f.get("description"),
                                            row_version)


def delete_job_title(db: Db, ctx: RequestContext, job_title_id: int, row_version: bytes) -> None:
    organisation_repo.delete_job_title(db, ctx.company_id, ctx.user_id, job_title_id, row_version)


# ---------------------------------------------------------------- simple masters

def list_masters(db: Db, ctx: RequestContext, table: str, search: str | None, page: int, page_size: int):
    return organisation_repo.list_masters(db, table, ctx.company_id, search, page, page_size)


def get_master(db: Db, ctx: RequestContext, table: str, item_id: int) -> dict[str, Any]:
    return organisation_repo.get_master(db, table, ctx.company_id, item_id)


def save_master(db: Db, ctx: RequestContext, table: str, item_id: int | None, name: str, code: str | None,
                sort_order: int | None, row_version: bytes | None) -> dict[str, Any]:
    return organisation_repo.save_master(db, table, ctx.company_id, ctx.user_id, item_id, name, code, sort_order,
                                         row_version)


def delete_master(db: Db, ctx: RequestContext, table: str, item_id: int, row_version: bytes) -> None:
    organisation_repo.delete_master(db, table, ctx.company_id, ctx.user_id, item_id, row_version)


# ---------------------------------------------------------------- pickers

def lookup(db: Db, ctx: RequestContext, kind: str, parent_id: int | None, search: str | None) -> list[dict[str, Any]]:
    if kind not in LOOKUP_KINDS:
        raise AppError(404, "NOT_FOUND", "No such list.")
    return organisation_repo.lookup(db, ctx.company_id, LOOKUP_KINDS[kind], parent_id, search)


def countries(db: Db, search: str | None) -> list[dict[str, Any]]:
    return organisation_repo.countries(db, search)


def states(db: Db, country_id: int | None, country_code: str | None) -> list[dict[str, Any]]:
    if country_id is None and not country_code:
        raise invalid("Give countryId or country.", "country")
    return organisation_repo.states(db, country_id, (country_code or "").upper() or None)


def cities(db: Db, state_id: int | None, state_code: str | None) -> list[dict[str, Any]]:
    if state_id is None and not state_code:
        raise invalid("Give stateId or state.", "state")
    return organisation_repo.cities(db, state_id, (state_code or "").upper() or None)


# ---------------------------------------------------------------- announcements

def list_announcements(db: Db, ctx: RequestContext, search: str | None, kind: str | None, current_only: bool,
                       page: int, page_size: int):
    return organisation_repo.list_announcements(db, ctx.company_id, search, kind, current_only, page, page_size)


def get_announcement(db: Db, ctx: RequestContext, announcement_id: int) -> dict[str, Any]:
    return organisation_repo.get_announcement(db, ctx.company_id, announcement_id)


def save_announcement(db: Db, ctx: RequestContext, announcement_id: int | None, f: dict[str, Any],
                      row_version: bytes | None) -> dict[str, Any]:
    return organisation_repo.save_announcement(db, ctx.company_id, ctx.user_id, announcement_id, f, row_version)


def delete_announcement(db: Db, ctx: RequestContext, announcement_id: int, row_version: bytes) -> None:
    organisation_repo.delete_announcement(db, ctx.company_id, ctx.user_id, announcement_id, row_version)


def _both_or_neither(f: dict[str, Any]) -> None:
    if (f.get("latitude") is None) != (f.get("longitude") is None):
        raise invalid("Give both latitude and longitude, or neither.", "longitude")


def set_company_logo(db: Db, ctx: RequestContext, file_id: int | None) -> dict[str, Any]:
    return organisation_repo.set_company_logo(db, ctx.company_id, ctx.user_id, file_id)
