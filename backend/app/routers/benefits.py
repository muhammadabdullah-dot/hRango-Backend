"""Benefits: plan years, benefit plans, enrollment windows, employee elections (Employees tab), plan files,
health benefits and perks."""
from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import benefits_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.benefits import (BenefitEmployeeOut, BenefitFileOut, BenefitPlanIn, BenefitPlanOut, DecisionIn,
                                  ElectionIn, ElectionOut, FileIn, HealthBenefitIn, HealthBenefitOut, PerkIn, PerkOut,
                                  PlanYearIn, PlanYearOut, SummaryOut, WindowIn, WindowOut)
from app.schemas.common import Item, Paginated

router = APIRouter(prefix="/benefits", tags=["benefits"])


def _no_content() -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/summary", response_model=Item[SummaryOut])
def summary(db: Db = Depends(get_db), ctx: RequestContext = Depends(require("benefits.plan_years.view"))) -> dict:
    return c.summary(db, ctx)


# ---------------------------------------------------------------- plan years

@router.get("/plan-years", response_model=Paginated[PlanYearOut])
def list_plan_years(q: str | None = None, status_: str | None = Query(None, alias="status"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("benefits.plan_years.view"))) -> dict:
    return c.list_plan_years(db, ctx, q, status_, paging)


@router.get("/plan-years/{year_id}", response_model=Item[PlanYearOut])
def get_plan_year(year_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("benefits.plan_years.view"))) -> dict:
    return c.get_plan_year(db, ctx, year_id)


@router.post("/plan-years", response_model=Item[PlanYearOut], status_code=status.HTTP_201_CREATED)
def create_plan_year(body: PlanYearIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("benefits.plan_years.create"))) -> dict:
    return c.save_plan_year(db, ctx, None, body)


@router.put("/plan-years/{year_id}", response_model=Item[PlanYearOut])
def update_plan_year(year_id: int, body: PlanYearIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("benefits.plan_years.edit"))) -> dict:
    return c.save_plan_year(db, ctx, year_id, body)


@router.delete("/plan-years/{year_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_plan_year(year_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("benefits.plan_years.delete"))) -> Response:
    c.delete_plan_year(db, ctx, year_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- benefit plans

@router.get("/plans", response_model=Paginated[BenefitPlanOut])
def list_plans(q: str | None = None, category: str | None = None,
               plan_year_id: int | None = Query(None, alias="planYearId"),
               status_: str | None = Query(None, alias="status"), paging: PageParams = Depends(page_params),
               db: Db = Depends(get_db), ctx: RequestContext = Depends(require("benefits.plans.view"))) -> dict:
    filters = {"search": q, "category": category, "plan_year_id": plan_year_id, "status": status_}
    return c.list_plans(db, ctx, filters, paging)


@router.get("/plans/{plan_id}", response_model=Item[BenefitPlanOut])
def get_plan(plan_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("benefits.plans.view"))) -> dict:
    return c.get_plan(db, ctx, plan_id)


@router.post("/plans", response_model=Item[BenefitPlanOut], status_code=status.HTTP_201_CREATED)
def create_plan(body: BenefitPlanIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("benefits.plans.create"))) -> dict:
    return c.save_plan(db, ctx, None, body)


@router.put("/plans/{plan_id}", response_model=Item[BenefitPlanOut])
def update_plan(plan_id: int, body: BenefitPlanIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("benefits.plans.edit"))) -> dict:
    return c.save_plan(db, ctx, plan_id, body)


@router.post("/plans/{plan_id}/duplicate", response_model=Item[BenefitPlanOut], status_code=status.HTTP_201_CREATED)
def duplicate_plan(plan_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("benefits.plans.create"))) -> dict:
    return c.duplicate_plan(db, ctx, plan_id)


@router.delete("/plans/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_plan(plan_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("benefits.plans.delete"))) -> Response:
    c.delete_plan(db, ctx, plan_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- plan files

@router.get("/files", response_model=Paginated[BenefitFileOut])
def list_files(q: str | None = None, plan_id: int | None = Query(None, alias="planId"),
               plan_year_id: int | None = Query(None, alias="planYearId"), paging: PageParams = Depends(page_params),
               db: Db = Depends(get_db), ctx: RequestContext = Depends(require("benefits.files.view"))) -> dict:
    return c.list_files(db, ctx, {"search": q, "plan_id": plan_id, "plan_year_id": plan_year_id}, paging)


@router.post("/plans/{plan_id}/files", response_model=Item[BenefitFileOut], status_code=status.HTTP_201_CREATED)
def add_file(plan_id: int, body: FileIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("benefits.files.create"))) -> dict:
    return c.add_file(db, ctx, plan_id, body.file_id)


@router.delete("/files/{attachment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_file(attachment_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                db: Db = Depends(get_db), ctx: RequestContext = Depends(require("benefits.files.delete"))) -> Response:
    c.delete_file(db, ctx, attachment_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- enrollment windows

@router.get("/enrollment-windows", response_model=Paginated[WindowOut])
def list_windows(q: str | None = None, plan_year_id: int | None = Query(None, alias="planYearId"),
                 kind: str | None = None, status_: str | None = Query(None, alias="status"),
                 paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("benefits.enrollment_windows.view"))) -> dict:
    filters = {"search": q, "plan_year_id": plan_year_id, "kind": kind, "status": status_}
    return c.list_windows(db, ctx, filters, paging)


@router.get("/enrollment-windows/{window_id}", response_model=Item[WindowOut])
def get_window(window_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("benefits.enrollment_windows.view"))) -> dict:
    return c.get_window(db, ctx, window_id)


@router.post("/enrollment-windows", response_model=Item[WindowOut], status_code=status.HTTP_201_CREATED)
def create_window(body: WindowIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("benefits.enrollment_windows.create"))) -> dict:
    return c.save_window(db, ctx, None, body)


@router.put("/enrollment-windows/{window_id}", response_model=Item[WindowOut])
def update_window(window_id: int, body: WindowIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("benefits.enrollment_windows.edit"))) -> dict:
    return c.save_window(db, ctx, window_id, body)


@router.delete("/enrollment-windows/{window_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_window(window_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("benefits.enrollment_windows.delete"))) -> Response:
    c.delete_window(db, ctx, window_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- Employees tab and elections

@router.get("/employees", response_model=Paginated[BenefitEmployeeOut])
def list_employees(q: str | None = None, plan_year_id: int | None = Query(None, alias="planYearId"),
                   missing_only: bool = Query(False, alias="missingOnly"), paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(require("benefits.elections.view"))) -> dict:
    filters = {"search": q, "plan_year_id": plan_year_id, "missing_only": missing_only}
    return c.list_employees(db, ctx, "benefits.elections.view", filters, paging)


@router.get("/elections", response_model=Paginated[ElectionOut])
def list_elections(q: str | None = None, plan_year_id: int | None = Query(None, alias="planYearId"),
                   employee_id: int | None = Query(None, alias="employeeId"),
                   status_: str | None = Query(None, alias="status"), paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(require("benefits.elections.view"))) -> dict:
    filters = {"search": q, "plan_year_id": plan_year_id, "employee_id": employee_id, "status": status_}
    return c.list_elections(db, ctx, "benefits.elections.view", filters, paging)


@router.get("/elections/{election_id}", response_model=Item[ElectionOut])
def get_election(election_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("benefits.elections.view"))) -> dict:
    return c.get_election(db, ctx, "benefits.elections.view", election_id)


@router.post("/elections", response_model=Item[ElectionOut], status_code=status.HTTP_201_CREATED)
def create_election(body: ElectionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("benefits.elections.create"))) -> dict:
    return c.save_election(db, ctx, "benefits.elections.create", None, body)


@router.put("/elections/{election_id}", response_model=Item[ElectionOut])
def update_election(election_id: int, body: ElectionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("benefits.elections.edit"))) -> dict:
    return c.save_election(db, ctx, "benefits.elections.edit", election_id, body)


@router.post("/elections/{election_id}/approve", response_model=Item[ElectionOut])
def approve_election(election_id: int, body: DecisionIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("benefits.elections.approve"))) -> dict:
    return c.decide_election(db, ctx, "benefits.elections.approve", election_id, "approve", body)


@router.post("/elections/{election_id}/reject", response_model=Item[ElectionOut])
def reject_election(election_id: int, body: DecisionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("benefits.elections.reject"))) -> dict:
    return c.decide_election(db, ctx, "benefits.elections.reject", election_id, "reject", body)


# ---------------------------------------------------------------- health benefits

@router.get("/health-benefits", response_model=Paginated[HealthBenefitOut])
def list_health_benefits(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                         status_: str | None = Query(None, alias="status"), paging: PageParams = Depends(page_params),
                         db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("benefits.health.view"))) -> dict:
    filters = {"search": q, "employee_id": employee_id, "status": status_}
    return c.list_owned(db, ctx, "health_benefit", "benefits.health.view", filters, paging)


@router.get("/health-benefits/{record_id}", response_model=Item[HealthBenefitOut])
def get_health_benefit(record_id: int, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("benefits.health.view"))) -> dict:
    return c.get_owned(db, ctx, "health_benefit", "benefits.health.view", record_id)


@router.post("/health-benefits", response_model=Item[HealthBenefitOut], status_code=status.HTTP_201_CREATED)
def create_health_benefit(body: HealthBenefitIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("benefits.health.create"))) -> dict:
    return c.save_health_benefit(db, ctx, "benefits.health.create", None, body)


@router.put("/health-benefits/{record_id}", response_model=Item[HealthBenefitOut])
def update_health_benefit(record_id: int, body: HealthBenefitIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("benefits.health.edit"))) -> dict:
    return c.save_health_benefit(db, ctx, "benefits.health.edit", record_id, body)


@router.delete("/health-benefits/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_health_benefit(record_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                          db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("benefits.health.delete"))) -> Response:
    c.delete_owned(db, ctx, "health_benefit", "benefits.health.delete", record_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- perks

@router.get("/perks", response_model=Paginated[PerkOut])
def list_perks(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
               occasion: str | None = None, status_: str | None = Query(None, alias="status"),
               from_date: date | None = Query(None, alias="fromDate"), to_date: date | None = Query(None, alias="toDate"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("benefits.perks.view"))) -> dict:
    filters = {"search": q, "employee_id": employee_id, "occasion": occasion, "status": status_,
               "from_date": from_date, "to_date": to_date}
    return c.list_owned(db, ctx, "perk", "benefits.perks.view", filters, paging)


@router.get("/perks/{record_id}", response_model=Item[PerkOut])
def get_perk(record_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("benefits.perks.view"))) -> dict:
    return c.get_owned(db, ctx, "perk", "benefits.perks.view", record_id)


@router.post("/perks", response_model=Item[PerkOut], status_code=status.HTTP_201_CREATED)
def create_perk(body: PerkIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("benefits.perks.create"))) -> dict:
    return c.save_perk(db, ctx, "benefits.perks.create", None, body)


@router.put("/perks/{record_id}", response_model=Item[PerkOut])
def update_perk(record_id: int, body: PerkIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("benefits.perks.edit"))) -> dict:
    return c.save_perk(db, ctx, "benefits.perks.edit", record_id, body)


@router.delete("/perks/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_perk(record_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("benefits.perks.delete"))) -> Response:
    c.delete_owned(db, ctx, "perk", "benefits.perks.delete", record_id, row_version)
    return _no_content()
