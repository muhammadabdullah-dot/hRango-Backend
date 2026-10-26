"""Organisation data access. The only layer that knows procedure names and parameters."""
from decimal import Decimal
from typing import Any

from app.core.db import Db

# The simple Control Panel masters: URL segment -> table (procedures org.usp_<table>_list/get/save/delete).
MASTER_TABLES = {"divisions": "division", "cost-centers": "cost_center", "designations": "designation",
                 "grades": "grade", "job-levels": "job_level", "employee-groups": "employee_group",
                 "employment-types": "employment_type"}
_MASTER_EXTRAS = {"cost_center": ("code",), "grade": ("sort_order",), "job_level": ("sort_order",)}


def _page(sets: list[list[dict[str, Any]]]) -> tuple[int, list[dict[str, Any]]]:
    return sets[0][0]["total"], sets[1]


# ---------------------------------------------------------------- departments (the worked example)

def list_departments(db: Db, company_id: int, search: str | None, parent_id: int | None,
                     page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("org.usp_department_list", company_id=company_id, search=search,
                               parent_id=parent_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_department(db: Db, company_id: int, department_id: int) -> dict[str, Any]:
    return db.call_one("org.usp_department_get", company_id=company_id, id=department_id)


def save_department(db: Db, company_id: int, actor_user_id: int | None, department_id: int | None,
                    name: str, parent_id: int | None, head_id: int | None,
                    row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("org.usp_department_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=department_id, name=name, parent_id=parent_id, head_id=head_id,
                       row_version=row_version)


def delete_department(db: Db, company_id: int, actor_user_id: int | None, department_id: int,
                      row_version: bytes) -> None:
    db.call("org.usp_department_delete", company_id=company_id, actor_user_id=actor_user_id,
            id=department_id, row_version=row_version)


# ---------------------------------------------------------------- companies

def get_company(db: Db, company_id: int, actor_user_id: int, target_id: int) -> dict[str, Any]:
    return db.call_one("org.usp_company_get", company_id=company_id, actor_user_id=actor_user_id, id=target_id)


def list_companies(db: Db, company_id: int, actor_user_id: int, search: str | None, page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("org.usp_company_list", company_id=company_id, actor_user_id=actor_user_id,
                              search=search, page=page, page_size=page_size))


def save_company(db: Db, company_id: int, actor_user_id: int, target_id: int | None, f: dict[str, Any],
                 row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("org.usp_company_save", company_id=company_id, actor_user_id=actor_user_id, id=target_id,
                       name=f["organization_name"], legal_name=f.get("legal_name"), email=f.get("email"),
                       phone=f.get("phone"), website=f.get("website"), address=f.get("address"),
                       country_id=f.get("country_id"), currency=f["currency"], timezone=f["timezone"],
                       date_format=f["date_format"], week_start_day=f["week_starts_on"],
                       fiscal_year_start_month=f["fiscal_year_start_month"], row_version=row_version)


def apply_default_roles(db: Db, company_id: int, roles_json: str) -> None:
    db.call("auth.usp_role_defaults_apply", company_id=company_id, roles=roles_json)


def grant_company_creator(db: Db, company_id: int, user_id: int) -> None:
    db.call("auth.usp_access_company_creator_grant", company_id=company_id, user_id=user_id)


# ---------------------------------------------------------------- locations, areas, branches, job titles

def list_locations(db: Db, company_id: int, search: str | None, page: int, page_size: int):
    return _page(db.call_sets("org.usp_location_list", company_id=company_id, search=search, page=page,
                              page_size=page_size))


def get_location(db: Db, company_id: int, location_id: int) -> dict[str, Any]:
    return db.call_one("org.usp_location_get", company_id=company_id, id=location_id)


def save_location(db: Db, company_id: int, actor_user_id: int, location_id: int | None, name: str,
                  employee_prefix: str | None, description: str | None, latitude: Decimal | None,
                  longitude: Decimal | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("org.usp_location_save", company_id=company_id, actor_user_id=actor_user_id, id=location_id,
                       name=name, employee_prefix=employee_prefix, description=description, latitude=latitude,
                       longitude=longitude, row_version=row_version)


def delete_location(db: Db, company_id: int, actor_user_id: int, location_id: int, row_version: bytes) -> None:
    db.call("org.usp_location_delete", company_id=company_id, actor_user_id=actor_user_id, id=location_id,
            row_version=row_version)


def list_areas(db: Db, company_id: int, search: str | None, location_id: int | None, page: int, page_size: int):
    return _page(db.call_sets("org.usp_area_list", company_id=company_id, search=search, location_id=location_id,
                              page=page, page_size=page_size))


def get_area(db: Db, company_id: int, area_id: int) -> dict[str, Any]:
    return db.call_one("org.usp_area_get", company_id=company_id, id=area_id)


def save_area(db: Db, company_id: int, actor_user_id: int, area_id: int | None, location_id: int, name: str,
              description: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("org.usp_area_save", company_id=company_id, actor_user_id=actor_user_id, id=area_id,
                       location_id=location_id, name=name, description=description, row_version=row_version)


def delete_area(db: Db, company_id: int, actor_user_id: int, area_id: int, row_version: bytes) -> None:
    db.call("org.usp_area_delete", company_id=company_id, actor_user_id=actor_user_id, id=area_id,
            row_version=row_version)


def list_branches(db: Db, company_id: int, search: str | None, location_id: int | None, area_id: int | None,
                  page: int, page_size: int):
    return _page(db.call_sets("org.usp_branch_list", company_id=company_id, search=search, location_id=location_id,
                              area_id=area_id, page=page, page_size=page_size))


def get_branch(db: Db, company_id: int, branch_id: int) -> dict[str, Any]:
    return db.call_one("org.usp_branch_get", company_id=company_id, id=branch_id)


def save_branch(db: Db, company_id: int, actor_user_id: int, branch_id: int | None, f: dict[str, Any],
                row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("org.usp_branch_save", company_id=company_id, actor_user_id=actor_user_id, id=branch_id,
                       name=f["name"], employee_prefix=f.get("employee_prefix"), location_id=f["location_id"],
                       area_id=f.get("area_id"), manager_id=f.get("manager_id"), description=f.get("description"),
                       country_id=f.get("country_id"), state_id=f.get("state_id"), city_id=f.get("city_id"),
                       latitude=f.get("latitude"), longitude=f.get("longitude"), row_version=row_version)


def delete_branch(db: Db, company_id: int, actor_user_id: int, branch_id: int, row_version: bytes) -> None:
    db.call("org.usp_branch_delete", company_id=company_id, actor_user_id=actor_user_id, id=branch_id,
            row_version=row_version)


def list_job_titles(db: Db, company_id: int, search: str | None, page: int, page_size: int):
    return _page(db.call_sets("org.usp_job_title_list", company_id=company_id, search=search, page=page,
                              page_size=page_size))


def get_job_title(db: Db, company_id: int, job_title_id: int) -> dict[str, Any]:
    return db.call_one("org.usp_job_title_get", company_id=company_id, id=job_title_id)


def save_job_title(db: Db, company_id: int, actor_user_id: int, job_title_id: int | None, name: str,
                   limit_head_count: bool, max_head_count: int | None, description: str | None,
                   row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("org.usp_job_title_save", company_id=company_id, actor_user_id=actor_user_id, id=job_title_id,
                       name=name, limit_head_count=limit_head_count, max_head_count=max_head_count,
                       description=description, row_version=row_version)


def delete_job_title(db: Db, company_id: int, actor_user_id: int, job_title_id: int, row_version: bytes) -> None:
    db.call("org.usp_job_title_delete", company_id=company_id, actor_user_id=actor_user_id, id=job_title_id,
            row_version=row_version)


# ---------------------------------------------------------------- simple masters

def list_masters(db: Db, table: str, company_id: int, search: str | None, page: int, page_size: int):
    return _page(db.call_sets(f"org.usp_{table}_list", company_id=company_id, search=search, page=page,
                              page_size=page_size))


def get_master(db: Db, table: str, company_id: int, item_id: int) -> dict[str, Any]:
    return db.call_one(f"org.usp_{table}_get", company_id=company_id, id=item_id)


def save_master(db: Db, table: str, company_id: int, actor_user_id: int, item_id: int | None, name: str,
                code: str | None, sort_order: int | None, row_version: bytes | None) -> dict[str, Any]:
    extras = {"code": code, "sort_order": sort_order}
    params = {k: extras[k] for k in _MASTER_EXTRAS.get(table, ())}
    return db.call_one(f"org.usp_{table}_save", company_id=company_id, actor_user_id=actor_user_id, id=item_id,
                       name=name, **params, row_version=row_version)


def delete_master(db: Db, table: str, company_id: int, actor_user_id: int, item_id: int, row_version: bytes) -> None:
    db.call(f"org.usp_{table}_delete", company_id=company_id, actor_user_id=actor_user_id, id=item_id,
            row_version=row_version)


# ---------------------------------------------------------------- pickers

def lookup(db: Db, company_id: int, kind: str, parent_id: int | None, search: str | None) -> list[dict[str, Any]]:
    return db.call("org.usp_lookup_list", company_id=company_id, kind=kind, parent_id=parent_id, search=search)


def countries(db: Db, search: str | None) -> list[dict[str, Any]]:
    return db.call("org.usp_geo_country_list", search=search)


def states(db: Db, country_id: int | None, country_code: str | None) -> list[dict[str, Any]]:
    return db.call("org.usp_geo_state_list", country_id=country_id, country_code=country_code)


def cities(db: Db, state_id: int | None, state_code: str | None) -> list[dict[str, Any]]:
    return db.call("org.usp_geo_city_list", state_id=state_id, state_code=state_code)


# ---------------------------------------------------------------- announcements

def list_announcements(db: Db, company_id: int, search: str | None, kind: str | None, current_only: bool,
                       page: int, page_size: int):
    return _page(db.call_sets("eng.usp_announcement_list", company_id=company_id, search=search, kind=kind,
                              current_only=current_only, page=page, page_size=page_size))


def get_announcement(db: Db, company_id: int, announcement_id: int) -> dict[str, Any]:
    return db.call_one("eng.usp_announcement_get", company_id=company_id, id=announcement_id)


def save_announcement(db: Db, company_id: int, actor_user_id: int, announcement_id: int | None, f: dict[str, Any],
                      row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("eng.usp_announcement_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=announcement_id, kind=f["kind"], title=f["title"], body=f.get("body"),
                       event_date=f.get("event_date"), publish_from=f.get("publish_from"),
                       publish_to=f.get("publish_to"), row_version=row_version)


def delete_announcement(db: Db, company_id: int, actor_user_id: int, announcement_id: int, row_version: bytes) -> None:
    db.call("eng.usp_announcement_delete", company_id=company_id, actor_user_id=actor_user_id, id=announcement_id,
            row_version=row_version)


def set_company_logo(db: Db, company_id: int, actor_user_id: int, file_id: int | None) -> dict[str, Any]:
    return db.call_one("org.usp_company_logo_set", company_id=company_id, actor_user_id=actor_user_id, file_id=file_id)
