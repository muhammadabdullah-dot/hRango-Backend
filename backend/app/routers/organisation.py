"""Settings -> Control Panel: general settings, companies, the organisation structure and its
masters, announcements, and picker lists any signed-in user may read."""
from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import organisation_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, get_context, require
from app.repos.organisation_repo import MASTER_TABLES
from app.schemas.common import Item, Paginated
from app.schemas.organisation import (AnnouncementIn, AnnouncementOut, AreaIn, AreaOut, BranchIn, BranchOut, CityOut,
                                      CompanyIn, CompanyLogoIn, CompanyOut, CompanyRef, CountryOut, DepartmentIn, DepartmentOut,
                                      JobTitleIn, JobTitleOut, LocationIn, LocationOut, LookupItem, MasterIn,
                                      MasterOut, StateOut)

router = APIRouter(prefix="/organisation", tags=["organisation"])
NO_CONTENT = status.HTTP_204_NO_CONTENT


def _deleted() -> Response:
    return Response(status_code=NO_CONTENT)


# ---------------------------------------------------------------- departments (the worked example)

@router.get("/departments", response_model=Paginated[DepartmentOut])
def list_departments(q: str | None = None, parent_id: int | None = Query(None, alias="parentId"),
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("organisation.departments.view"))) -> dict:
    return c.list_departments(db, ctx, q, parent_id, paging)


@router.get("/departments/{department_id}", response_model=Item[DepartmentOut])
def get_department(department_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("organisation.departments.view"))) -> dict:
    return c.get_department(db, ctx, department_id)


@router.post("/departments", response_model=Item[DepartmentOut], status_code=status.HTTP_201_CREATED)
def create_department(body: DepartmentIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("organisation.departments.create"))) -> dict:
    return c.create_department(db, ctx, body)


@router.put("/departments/{department_id}", response_model=Item[DepartmentOut])
def update_department(department_id: int, body: DepartmentIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("organisation.departments.edit"))) -> dict:
    return c.update_department(db, ctx, department_id, body)


@router.delete("/departments/{department_id}", status_code=NO_CONTENT)
def delete_department(department_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                      db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("organisation.departments.delete"))) -> Response:
    c.delete_department(db, ctx, department_id, row_version)
    return _deleted()


# ---------------------------------------------------------------- general settings and companies

@router.get("/general", response_model=Item[CompanyOut])
def get_general(db: Db = Depends(get_db), ctx: RequestContext = Depends(require("organisation.general.view"))) -> dict:
    return c.get_general(db, ctx)


@router.put("/general", response_model=Item[CompanyOut])
def update_general(body: CompanyIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("organisation.general.edit"))) -> dict:
    return c.update_general(db, ctx, body)


@router.put("/general/logo", response_model=Item[CompanyOut])
def set_logo(body: CompanyLogoIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("organisation.general.edit"))) -> dict:
    """The organisation's logo, shown in the sidebar: an uploaded image's id (module organisation), or null."""
    return c.set_logo(db, ctx, body.file_id)


@router.get("/companies", response_model=Paginated[CompanyOut])
def list_companies(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("organisation.companies.view"))) -> dict:
    return c.list_companies(db, ctx, q, paging)


@router.get("/companies/{company_id}", response_model=Item[CompanyOut])
def get_company(company_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("organisation.companies.view"))) -> dict:
    return c.get_company(db, ctx, company_id)


@router.post("/companies", response_model=Item[CompanyOut], status_code=status.HTTP_201_CREATED)
def create_company(body: CompanyIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("organisation.companies.create"))) -> dict:
    return c.create_company(db, ctx, body)


@router.put("/companies/{company_id}", response_model=Item[CompanyOut])
def update_company(company_id: int, body: CompanyIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("organisation.companies.edit"))) -> dict:
    return c.update_company(db, ctx, company_id, body)


# ---------------------------------------------------------------- pickers (any signed-in user)

@router.get("/lookups/companies", response_model=Item[list[CompanyRef]])
def my_companies(db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> dict:
    """Companies the user may switch to (send X-Company-Id)."""
    return c.my_companies(db, ctx)


@router.get("/lookups/{kind}", response_model=Item[list[LookupItem]])
def lookup(kind: str, parent_id: int | None = Query(None, alias="parentId"), q: str | None = None,
           db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> dict:
    """Ids and names for a picker: locations, areas, branches, departments, divisions, cost-centers,
    designations, job-titles, grades, job-levels, employee-groups, employment-types."""
    return c.lookup(db, ctx, kind, parent_id, q)


@router.get("/geo/countries", response_model=Item[list[CountryOut]])
def countries(q: str | None = None, db: Db = Depends(get_db), _: RequestContext = Depends(get_context)) -> dict:
    return c.countries(db, q)


@router.get("/geo/states", response_model=Item[list[StateOut]])
def states(country_id: int | None = Query(None, alias="countryId"), country: str | None = None,
           db: Db = Depends(get_db), _: RequestContext = Depends(get_context)) -> dict:
    return c.states(db, country_id, country)


@router.get("/geo/cities", response_model=Item[list[CityOut]])
def cities(state_id: int | None = Query(None, alias="stateId"), state: str | None = None,
           db: Db = Depends(get_db), _: RequestContext = Depends(get_context)) -> dict:
    return c.cities(db, state_id, state)


# ---------------------------------------------------------------- locations

@router.get("/locations", response_model=Paginated[LocationOut])
def list_locations(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("organisation.locations.view"))) -> dict:
    return c.list_locations(db, ctx, q, paging)


@router.get("/locations/{location_id}", response_model=Item[LocationOut])
def get_location(location_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("organisation.locations.view"))) -> dict:
    return c.get_location(db, ctx, location_id)


@router.post("/locations", response_model=Item[LocationOut], status_code=status.HTTP_201_CREATED)
def create_location(body: LocationIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("organisation.locations.create"))) -> dict:
    return c.save_location(db, ctx, None, body)


@router.put("/locations/{location_id}", response_model=Item[LocationOut])
def update_location(location_id: int, body: LocationIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("organisation.locations.edit"))) -> dict:
    return c.save_location(db, ctx, location_id, body)


@router.delete("/locations/{location_id}", status_code=NO_CONTENT)
def delete_location(location_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("organisation.locations.delete"))) -> Response:
    c.delete_location(db, ctx, location_id, row_version)
    return _deleted()


# ---------------------------------------------------------------- areas

@router.get("/areas", response_model=Paginated[AreaOut])
def list_areas(q: str | None = None, location_id: int | None = Query(None, alias="locationId"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("organisation.areas.view"))) -> dict:
    return c.list_areas(db, ctx, q, location_id, paging)


@router.get("/areas/{area_id}", response_model=Item[AreaOut])
def get_area(area_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("organisation.areas.view"))) -> dict:
    return c.get_area(db, ctx, area_id)


@router.post("/areas", response_model=Item[AreaOut], status_code=status.HTTP_201_CREATED)
def create_area(body: AreaIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("organisation.areas.create"))) -> dict:
    return c.save_area(db, ctx, None, body)


@router.put("/areas/{area_id}", response_model=Item[AreaOut])
def update_area(area_id: int, body: AreaIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("organisation.areas.edit"))) -> dict:
    return c.save_area(db, ctx, area_id, body)


@router.delete("/areas/{area_id}", status_code=NO_CONTENT)
def delete_area(area_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("organisation.areas.delete"))) -> Response:
    c.delete_area(db, ctx, area_id, row_version)
    return _deleted()


# ---------------------------------------------------------------- branches

@router.get("/branches", response_model=Paginated[BranchOut])
def list_branches(q: str | None = None, location_id: int | None = Query(None, alias="locationId"),
                  area_id: int | None = Query(None, alias="areaId"), paging: PageParams = Depends(page_params),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("organisation.branches.view"))) -> dict:
    return c.list_branches(db, ctx, q, location_id, area_id, paging)


@router.get("/branches/{branch_id}", response_model=Item[BranchOut])
def get_branch(branch_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("organisation.branches.view"))) -> dict:
    return c.get_branch(db, ctx, branch_id)


@router.post("/branches", response_model=Item[BranchOut], status_code=status.HTTP_201_CREATED)
def create_branch(body: BranchIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("organisation.branches.create"))) -> dict:
    return c.save_branch(db, ctx, None, body)


@router.put("/branches/{branch_id}", response_model=Item[BranchOut])
def update_branch(branch_id: int, body: BranchIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("organisation.branches.edit"))) -> dict:
    return c.save_branch(db, ctx, branch_id, body)


@router.delete("/branches/{branch_id}", status_code=NO_CONTENT)
def delete_branch(branch_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("organisation.branches.delete"))) -> Response:
    c.delete_branch(db, ctx, branch_id, row_version)
    return _deleted()


# ---------------------------------------------------------------- job titles

@router.get("/job-titles", response_model=Paginated[JobTitleOut])
def list_job_titles(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("organisation.job_titles.view"))) -> dict:
    return c.list_job_titles(db, ctx, q, paging)


@router.get("/job-titles/{job_title_id}", response_model=Item[JobTitleOut])
def get_job_title(job_title_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("organisation.job_titles.view"))) -> dict:
    return c.get_job_title(db, ctx, job_title_id)


@router.post("/job-titles", response_model=Item[JobTitleOut], status_code=status.HTTP_201_CREATED)
def create_job_title(body: JobTitleIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("organisation.job_titles.create"))) -> dict:
    return c.save_job_title(db, ctx, None, body)


@router.put("/job-titles/{job_title_id}", response_model=Item[JobTitleOut])
def update_job_title(job_title_id: int, body: JobTitleIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("organisation.job_titles.edit"))) -> dict:
    return c.save_job_title(db, ctx, job_title_id, body)


@router.delete("/job-titles/{job_title_id}", status_code=NO_CONTENT)
def delete_job_title(job_title_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("organisation.job_titles.delete"))) -> Response:
    c.delete_job_title(db, ctx, job_title_id, row_version)
    return _deleted()


# ---------------------------------------------------------------- announcements

@router.get("/announcements", response_model=Paginated[AnnouncementOut])
def list_announcements(q: str | None = None, kind: str | None = None,
                       current_only: bool = Query(False, alias="currentOnly"),
                       paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("organisation.announcements.view"))) -> dict:
    return c.list_announcements(db, ctx, q, kind, current_only, paging)


@router.get("/announcements/{announcement_id}", response_model=Item[AnnouncementOut])
def get_announcement(announcement_id: int, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("organisation.announcements.view"))) -> dict:
    return c.get_announcement(db, ctx, announcement_id)


@router.post("/announcements", response_model=Item[AnnouncementOut], status_code=status.HTTP_201_CREATED)
def create_announcement(body: AnnouncementIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("organisation.announcements.create"))) -> dict:
    return c.save_announcement(db, ctx, None, body)


@router.put("/announcements/{announcement_id}", response_model=Item[AnnouncementOut])
def update_announcement(announcement_id: int, body: AnnouncementIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("organisation.announcements.edit"))) -> dict:
    return c.save_announcement(db, ctx, announcement_id, body)


@router.delete("/announcements/{announcement_id}", status_code=NO_CONTENT)
def delete_announcement(announcement_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                        db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("organisation.announcements.delete"))) -> Response:
    c.delete_announcement(db, ctx, announcement_id, row_version)
    return _deleted()


# ---------------------------------------------------------------- simple masters
# divisions, cost-centers, designations, grades, job-levels, employee-groups, employment-types:
# the same five endpoints each, guarded by organisation.<segment with underscores>.<action>.

def _master_routes(segment: str, table: str) -> None:
    code = "organisation." + segment.replace("-", "_")
    tag = segment.replace("-", "_")

    def list_items(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require(f"{code}.view"))) -> dict:
        return c.list_masters(db, ctx, table, q, paging)

    def get_item(item_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require(f"{code}.view"))) -> dict:
        return c.get_master(db, ctx, table, item_id)

    def create_item(body: MasterIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require(f"{code}.create"))) -> dict:
        return c.save_master(db, ctx, table, None, body)

    def update_item(item_id: int, body: MasterIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require(f"{code}.edit"))) -> dict:
        return c.save_master(db, ctx, table, item_id, body)

    def delete_item(item_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require(f"{code}.delete"))) -> Response:
        c.delete_master(db, ctx, table, item_id, row_version)
        return _deleted()

    router.add_api_route(f"/{segment}", list_items, methods=["GET"], response_model=Paginated[MasterOut],
                         name=f"list_{tag}")
    router.add_api_route(f"/{segment}/{{item_id}}", get_item, methods=["GET"], response_model=Item[MasterOut],
                         name=f"get_{tag}")
    router.add_api_route(f"/{segment}", create_item, methods=["POST"], response_model=Item[MasterOut],
                         status_code=status.HTTP_201_CREATED, name=f"create_{tag}")
    router.add_api_route(f"/{segment}/{{item_id}}", update_item, methods=["PUT"], response_model=Item[MasterOut],
                         name=f"update_{tag}")
    router.add_api_route(f"/{segment}/{{item_id}}", delete_item, methods=["DELETE"], status_code=NO_CONTENT,
                         name=f"delete_{tag}")


for _segment, _table in MASTER_TABLES.items():
    _master_routes(_segment, _table)
