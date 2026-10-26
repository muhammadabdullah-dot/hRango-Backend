"""HTTP shape for organisation screens: envelopes, row versions as text, rows to response models."""
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.organisation import (AnnouncementIn, AnnouncementOut, AreaIn, AreaOut, BranchIn, BranchOut, CityOut,
                                      CompanyIn, CompanyOut, CompanyRef, CountryOut, DepartmentIn, DepartmentOut,
                                      JobTitleIn, JobTitleOut, LocationIn, LocationOut, LookupItem, MasterIn,
                                      MasterOut, StateOut)
from app.services import organisation_service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _department(row: dict[str, Any]) -> DepartmentOut:
    return DepartmentOut(**_rv(row))


def _company(row: dict[str, Any]) -> CompanyOut:
    return CompanyOut(**{**_rv(row), "organization_name": row["name"], "week_starts_on": row["week_start_day"],
                         "logo_url": file_url(row.get("logo_file_id"), row["id"])})


def set_logo(db: Db, ctx: RequestContext, file_id: int | None) -> dict:
    return {"data": _company(organisation_service.set_company_logo(db, ctx, file_id))}


def _rv_in(text: str | None, editing: bool) -> bytes | None:
    return row_version_in(text) if editing else None


# ---------------------------------------------------------------- departments (the worked example)

def list_departments(db: Db, ctx: RequestContext, q: str | None, parent_id: int | None, paging: PageParams) -> dict:
    total, rows = organisation_service.list_departments(db, ctx, q, parent_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _department)


def get_department(db: Db, ctx: RequestContext, department_id: int) -> dict:
    return {"data": _department(organisation_service.get_department(db, ctx, department_id))}


def create_department(db: Db, ctx: RequestContext, body: DepartmentIn) -> dict:
    row = organisation_service.save_department(db, ctx, None, body.name, body.parent_id, body.head_id, None)
    return {"data": _department(row)}


def update_department(db: Db, ctx: RequestContext, department_id: int, body: DepartmentIn) -> dict:
    row = organisation_service.save_department(db, ctx, department_id, body.name, body.parent_id, body.head_id,
                                               row_version_in(body.row_version))
    return {"data": _department(row)}


def delete_department(db: Db, ctx: RequestContext, department_id: int, row_version: str | None) -> None:
    organisation_service.delete_department(db, ctx, department_id, row_version_in(row_version))


# ---------------------------------------------------------------- companies and general settings

def get_general(db: Db, ctx: RequestContext) -> dict:
    return {"data": _company(organisation_service.get_company(db, ctx, ctx.company_id))}


def update_general(db: Db, ctx: RequestContext, body: CompanyIn) -> dict:
    return update_company(db, ctx, ctx.company_id, body)


def list_companies(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    total, rows = organisation_service.list_companies(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _company)


def get_company(db: Db, ctx: RequestContext, company_id: int) -> dict:
    return {"data": _company(organisation_service.get_company(db, ctx, company_id))}


def create_company(db: Db, ctx: RequestContext, body: CompanyIn) -> dict:
    row = organisation_service.save_company(db, ctx, None, body.model_dump(by_alias=False, exclude={"row_version"}), None)
    return {"data": _company(row)}


def update_company(db: Db, ctx: RequestContext, company_id: int, body: CompanyIn) -> dict:
    row = organisation_service.save_company(db, ctx, company_id, body.model_dump(by_alias=False, exclude={"row_version"}),
                                            row_version_in(body.row_version))
    return {"data": _company(row)}


def my_companies(db: Db, ctx: RequestContext) -> dict:
    rows = organisation_service.my_companies(db, ctx)
    return {"data": [CompanyRef(id=r["id"], name=r["name"], is_current=r["id"] == ctx.company_id) for r in rows]}


# ---------------------------------------------------------------- locations, areas, branches, job titles

def list_locations(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    total, rows = organisation_service.list_locations(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: LocationOut(**_rv(r)))


def get_location(db: Db, ctx: RequestContext, location_id: int) -> dict:
    return {"data": LocationOut(**_rv(organisation_service.get_location(db, ctx, location_id)))}


def save_location(db: Db, ctx: RequestContext, location_id: int | None, body: LocationIn) -> dict:
    row = organisation_service.save_location(db, ctx, location_id, body.model_dump(by_alias=False),
                                             _rv_in(body.row_version, location_id is not None))
    return {"data": LocationOut(**_rv(row))}


def delete_location(db: Db, ctx: RequestContext, location_id: int, row_version: str | None) -> None:
    organisation_service.delete_location(db, ctx, location_id, row_version_in(row_version))


def list_areas(db: Db, ctx: RequestContext, q: str | None, location_id: int | None, paging: PageParams) -> dict:
    total, rows = organisation_service.list_areas(db, ctx, q, location_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: AreaOut(**_rv(r)))


def get_area(db: Db, ctx: RequestContext, area_id: int) -> dict:
    return {"data": AreaOut(**_rv(organisation_service.get_area(db, ctx, area_id)))}


def save_area(db: Db, ctx: RequestContext, area_id: int | None, body: AreaIn) -> dict:
    row = organisation_service.save_area(db, ctx, area_id, body.model_dump(by_alias=False), _rv_in(body.row_version, area_id is not None))
    return {"data": AreaOut(**_rv(row))}


def delete_area(db: Db, ctx: RequestContext, area_id: int, row_version: str | None) -> None:
    organisation_service.delete_area(db, ctx, area_id, row_version_in(row_version))


def list_branches(db: Db, ctx: RequestContext, q: str | None, location_id: int | None, area_id: int | None,
                  paging: PageParams) -> dict:
    total, rows = organisation_service.list_branches(db, ctx, q, location_id, area_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: BranchOut(**_rv(r)))


def get_branch(db: Db, ctx: RequestContext, branch_id: int) -> dict:
    return {"data": BranchOut(**_rv(organisation_service.get_branch(db, ctx, branch_id)))}


def save_branch(db: Db, ctx: RequestContext, branch_id: int | None, body: BranchIn) -> dict:
    row = organisation_service.save_branch(db, ctx, branch_id, body.model_dump(by_alias=False),
                                           _rv_in(body.row_version, branch_id is not None))
    return {"data": BranchOut(**_rv(row))}


def delete_branch(db: Db, ctx: RequestContext, branch_id: int, row_version: str | None) -> None:
    organisation_service.delete_branch(db, ctx, branch_id, row_version_in(row_version))


def list_job_titles(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    total, rows = organisation_service.list_job_titles(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: JobTitleOut(**_rv(r)))


def get_job_title(db: Db, ctx: RequestContext, job_title_id: int) -> dict:
    return {"data": JobTitleOut(**_rv(organisation_service.get_job_title(db, ctx, job_title_id)))}


def save_job_title(db: Db, ctx: RequestContext, job_title_id: int | None, body: JobTitleIn) -> dict:
    row = organisation_service.save_job_title(db, ctx, job_title_id, body.model_dump(by_alias=False),
                                              _rv_in(body.row_version, job_title_id is not None))
    return {"data": JobTitleOut(**_rv(row))}


def delete_job_title(db: Db, ctx: RequestContext, job_title_id: int, row_version: str | None) -> None:
    organisation_service.delete_job_title(db, ctx, job_title_id, row_version_in(row_version))


# ---------------------------------------------------------------- simple masters

def list_masters(db: Db, ctx: RequestContext, table: str, q: str | None, paging: PageParams) -> dict:
    total, rows = organisation_service.list_masters(db, ctx, table, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: MasterOut(**_rv(r)))


def get_master(db: Db, ctx: RequestContext, table: str, item_id: int) -> dict:
    return {"data": MasterOut(**_rv(organisation_service.get_master(db, ctx, table, item_id)))}


def save_master(db: Db, ctx: RequestContext, table: str, item_id: int | None, body: MasterIn) -> dict:
    row = organisation_service.save_master(db, ctx, table, item_id, body.name, body.code, body.sort_order,
                                           _rv_in(body.row_version, item_id is not None))
    return {"data": MasterOut(**_rv(row))}


def delete_master(db: Db, ctx: RequestContext, table: str, item_id: int, row_version: str | None) -> None:
    organisation_service.delete_master(db, ctx, table, item_id, row_version_in(row_version))


# ---------------------------------------------------------------- pickers

def lookup(db: Db, ctx: RequestContext, kind: str, parent_id: int | None, q: str | None) -> dict:
    return {"data": [LookupItem(**r) for r in organisation_service.lookup(db, ctx, kind, parent_id, q)]}


def countries(db: Db, q: str | None) -> dict:
    return {"data": [CountryOut(**r) for r in organisation_service.countries(db, q)]}


def states(db: Db, country_id: int | None, country_code: str | None) -> dict:
    return {"data": [StateOut(**r) for r in organisation_service.states(db, country_id, country_code)]}


def cities(db: Db, state_id: int | None, state_code: str | None) -> dict:
    return {"data": [CityOut(**r) for r in organisation_service.cities(db, state_id, state_code)]}


# ---------------------------------------------------------------- announcements

def list_announcements(db: Db, ctx: RequestContext, q: str | None, kind: str | None, current_only: bool,
                       paging: PageParams) -> dict:
    total, rows = organisation_service.list_announcements(db, ctx, q, kind, current_only, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: AnnouncementOut(**_rv(r)))


def get_announcement(db: Db, ctx: RequestContext, announcement_id: int) -> dict:
    return {"data": AnnouncementOut(**_rv(organisation_service.get_announcement(db, ctx, announcement_id)))}


def save_announcement(db: Db, ctx: RequestContext, announcement_id: int | None, body: AnnouncementIn) -> dict:
    row = organisation_service.save_announcement(db, ctx, announcement_id, body.model_dump(by_alias=False),
                                                 _rv_in(body.row_version, announcement_id is not None))
    return {"data": AnnouncementOut(**_rv(row))}


def delete_announcement(db: Db, ctx: RequestContext, announcement_id: int, row_version: str | None) -> None:
    organisation_service.delete_announcement(db, ctx, announcement_id, row_version_in(row_version))
