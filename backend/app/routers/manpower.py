"""Manpower Planning: Planning, E-Budgeting, Budget Approvals, Open Positions and E-Budget Settings
(budget durations, position titles, employee positions and their salary ranges)."""

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import manpower_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.common import Item, Paginated
from app.schemas.manpower import (BudgetDurationIn, BudgetDurationOut, BudgetIn, BudgetOut, DecisionIn, FileOut,
                                  ImportResultOut, OpenPositionIn, OpenPositionOut, PlanDetailOut, PlanIn, PlanOut,
                                  PositionImportIn, PositionIn, PositionOut, PositionTitleOut, RowVersionIn,
                                  SalaryRangeIn, SalaryRangeOut)

router = APIRouter(prefix="/manpower", tags=["manpower"])

def _no_content() -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# Plan forms need the durations and positions, so planners may read them without the settings screens.
DURATIONS_READ = require_any("manpower.settings.budget_durations.view", "manpower.planning.view",
                             "manpower.e_budgeting.view")
POSITIONS_READ = require_any("manpower.settings.positions.view", "manpower.planning.view")
TITLES_READ = require_any("manpower.settings.position_titles.view", "manpower.settings.positions.view",
                          "manpower.planning.view", "manpower.e_budgeting.view")


# ---------------------------------------------------------------- E-Budget Settings: budget durations

@router.get("/budget-durations", response_model=Paginated[BudgetDurationOut])
def list_durations(q: str | None = None, is_current: bool | None = Query(None, alias="isCurrent"),
                   paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(DURATIONS_READ)) -> dict:
    return c.list_durations(db, ctx, q, is_current, paging)


@router.get("/budget-durations/{duration_id}", response_model=Item[BudgetDurationOut])
def get_duration(duration_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(DURATIONS_READ)) -> dict:
    return c.get_duration(db, ctx, duration_id)


@router.post("/budget-durations", response_model=Item[BudgetDurationOut], status_code=status.HTTP_201_CREATED)
def create_duration(body: BudgetDurationIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("manpower.settings.budget_durations.create"))) -> dict:
    return c.save_duration(db, ctx, None, body)


@router.put("/budget-durations/{duration_id}", response_model=Item[BudgetDurationOut])
def update_duration(duration_id: int, body: BudgetDurationIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("manpower.settings.budget_durations.edit"))) -> dict:
    return c.save_duration(db, ctx, duration_id, body)


@router.delete("/budget-durations/{duration_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_duration(duration_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("manpower.settings.budget_durations.delete"))) -> Response:
    c.delete_duration(db, ctx, duration_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- E-Budget Settings: position titles

@router.get("/position-titles", response_model=Paginated[PositionTitleOut])
def list_position_titles(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(TITLES_READ)) -> dict:
    return c.list_position_titles(db, ctx, q, paging)


# ---------------------------------------------------------------- E-Budget Settings: employee positions

@router.get("/positions", response_model=Paginated[PositionOut])
def list_positions(q: str | None = None, job_title_id: int | None = Query(None, alias="jobTitleId"),
                   branch_id: int | None = Query(None, alias="branchId"),
                   division_id: int | None = Query(None, alias="divisionId"),
                   department_id: int | None = Query(None, alias="departmentId"),
                   employee_group_id: int | None = Query(None, alias="employeeGroupId"),
                   status_: str | None = Query(None, alias="status"),
                   paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(POSITIONS_READ)) -> dict:
    filters = {"search": q, "job_title_id": job_title_id, "branch_id": branch_id, "division_id": division_id,
               "department_id": department_id, "employee_group_id": employee_group_id, "status": status_}
    return c.list_positions(db, ctx, filters, paging)


@router.post("/positions/import", response_model=Item[ImportResultOut])
def import_positions(body: PositionImportIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("manpower.settings.positions.import"))) -> dict:
    return c.import_positions(db, ctx, body)


@router.get("/positions/{position_id}", response_model=Item[PositionOut])
def get_position(position_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(POSITIONS_READ)) -> dict:
    return c.get_position(db, ctx, position_id)


@router.post("/positions", response_model=Item[PositionOut], status_code=status.HTTP_201_CREATED)
def create_position(body: PositionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("manpower.settings.positions.create"))) -> dict:
    return c.save_position(db, ctx, None, body)


@router.put("/positions/{position_id}", response_model=Item[PositionOut])
def update_position(position_id: int, body: PositionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("manpower.settings.positions.edit"))) -> dict:
    return c.save_position(db, ctx, position_id, body)


@router.delete("/positions/{position_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_position(position_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("manpower.settings.positions.delete"))) -> Response:
    c.delete_position(db, ctx, position_id, row_version)
    return _no_content()


@router.get("/positions/{position_id}/salary-ranges", response_model=Item[list[SalaryRangeOut]])
def list_salary_ranges(position_id: int, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(POSITIONS_READ)) -> dict:
    return c.list_salary_ranges(db, ctx, position_id)


@router.post("/positions/{position_id}/salary-ranges", response_model=Item[list[SalaryRangeOut]],
             status_code=status.HTTP_201_CREATED)
def save_salary_range(position_id: int, body: SalaryRangeIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("manpower.settings.positions.edit"))) -> dict:
    return c.save_salary_range(db, ctx, position_id, body)


# ---------------------------------------------------------------- Planning

@router.get("/plans", response_model=Paginated[PlanOut])
def list_plans(q: str | None = None, budget_duration_id: int | None = Query(None, alias="budgetDurationId"),
               mode: str | None = Query(None, pattern="^(new|existing)$"),
               status_: str | None = Query(None, alias="status"),
               is_current: bool | None = Query(None, alias="isCurrent"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("manpower.planning.view"))) -> dict:
    filters = {"search": q, "budget_duration_id": budget_duration_id, "mode": mode, "status": status_,
               "is_current": is_current}
    return c.list_plans(db, ctx, "manpower.planning.view", filters, paging)


@router.get("/plans/{plan_id}", response_model=Item[PlanDetailOut])
def get_plan(plan_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("manpower.planning.view"))) -> dict:
    return c.get_plan(db, ctx, "manpower.planning.view", plan_id)


@router.post("/plans", response_model=Item[PlanDetailOut], status_code=status.HTTP_201_CREATED)
def create_plan(body: PlanIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("manpower.planning.create"))) -> dict:
    return c.save_plan(db, ctx, "manpower.planning.create", None, body)


@router.put("/plans/{plan_id}", response_model=Item[PlanDetailOut])
def update_plan(plan_id: int, body: PlanIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("manpower.planning.edit"))) -> dict:
    return c.save_plan(db, ctx, "manpower.planning.edit", plan_id, body)


@router.delete("/plans/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_plan(plan_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("manpower.planning.delete"))) -> Response:
    c.delete_plan(db, ctx, "manpower.planning.delete", plan_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- E-Budgeting

def _budget_filters(q, budget_duration_id, plan_id, department_id, status_) -> dict:
    return {"search": q, "budget_duration_id": budget_duration_id, "manpower_plan_id": plan_id,
            "department_id": department_id, "status": status_}


@router.get("/budgets", response_model=Paginated[BudgetOut])
def list_budgets(q: str | None = None, budget_duration_id: int | None = Query(None, alias="budgetDurationId"),
                 plan_id: int | None = Query(None, alias="planId"),
                 department_id: int | None = Query(None, alias="departmentId"),
                 status_: str | None = Query(None, alias="status"),
                 paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("manpower.e_budgeting.view"))) -> dict:
    filters = _budget_filters(q, budget_duration_id, plan_id, department_id, status_)
    return c.list_budgets(db, ctx, "manpower.e_budgeting.view", filters, paging)


@router.get("/budgets/{budget_id}", response_model=Item[BudgetOut])
def get_budget(budget_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("manpower.e_budgeting.view"))) -> dict:
    return c.get_budget(db, ctx, "manpower.e_budgeting.view", budget_id)


@router.post("/budgets", response_model=Item[BudgetOut], status_code=status.HTTP_201_CREATED)
def create_budget(body: BudgetIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("manpower.e_budgeting.create"))) -> dict:
    return c.save_budget(db, ctx, "manpower.e_budgeting.create", None, body)


@router.put("/budgets/{budget_id}", response_model=Item[BudgetOut])
def update_budget(budget_id: int, body: BudgetIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("manpower.e_budgeting.edit"))) -> dict:
    return c.save_budget(db, ctx, "manpower.e_budgeting.edit", budget_id, body)


@router.delete("/budgets/{budget_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_budget(budget_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("manpower.e_budgeting.delete"))) -> Response:
    c.delete_budget(db, ctx, "manpower.e_budgeting.delete", budget_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- Budget Approvals

@router.get("/budget-approvals", response_model=Paginated[BudgetOut])
def list_budget_approvals(q: str | None = None,
                          budget_duration_id: int | None = Query(None, alias="budgetDurationId"),
                          department_id: int | None = Query(None, alias="departmentId"),
                          status_: str | None = Query("pending", alias="status"),
                          paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("manpower.budget_approvals.view"))) -> dict:
    filters = _budget_filters(q, budget_duration_id, None, department_id, status_ or None)
    return c.list_budgets(db, ctx, "manpower.budget_approvals.view", filters, paging)


@router.post("/budgets/{budget_id}/approve", response_model=Item[BudgetOut])
def approve_budget(budget_id: int, body: DecisionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("manpower.budget_approvals.approve"))) -> dict:
    return c.decide_budget(db, ctx, "manpower.budget_approvals.approve", budget_id, "approve", body)


@router.post("/budgets/{budget_id}/reject", response_model=Item[BudgetOut])
def reject_budget(budget_id: int, body: DecisionIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("manpower.budget_approvals.reject"))) -> dict:
    return c.decide_budget(db, ctx, "manpower.budget_approvals.reject", budget_id, "reject", body)


# ---------------------------------------------------------------- Open Positions

@router.get("/open-positions", response_model=Paginated[OpenPositionOut])
def list_open_positions(q: str | None = None, job_title_id: int | None = Query(None, alias="jobTitleId"),
                        department_id: int | None = Query(None, alias="departmentId"),
                        status_: str | None = Query(None, alias="status"),
                        paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("manpower.open_positions.view"))) -> dict:
    filters = {"search": q, "job_title_id": job_title_id, "department_id": department_id, "status": status_}
    return c.list_open_positions(db, ctx, "manpower.open_positions.view", filters, paging)


@router.get("/open-positions/{open_id}", response_model=Item[OpenPositionOut])
def get_open_position(open_id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("manpower.open_positions.view"))) -> dict:
    return c.get_open_position(db, ctx, "manpower.open_positions.view", open_id)


@router.put("/open-positions/{open_id}", response_model=Item[OpenPositionOut])
def update_open_position(open_id: int, body: OpenPositionIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("manpower.open_positions.edit"))) -> dict:
    return c.save_open_position(db, ctx, "manpower.open_positions.edit", open_id, body)


@router.post("/open-positions/{open_id}/close", response_model=Item[OpenPositionOut])
def close_open_position(open_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("manpower.open_positions.close"))) -> dict:
    return c.set_open_position_status(db, ctx, "manpower.open_positions.close", open_id, "closed", body)


@router.post("/open-positions/{open_id}/reopen", response_model=Item[OpenPositionOut])
def reopen_open_position(open_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("manpower.open_positions.reopen"))) -> dict:
    return c.set_open_position_status(db, ctx, "manpower.open_positions.reopen", open_id, "active", body)


@router.get("/open-positions/{open_id}/jd", response_model=Item[FileOut])
def open_position_jd(open_id: int, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("manpower.open_positions.download"))) -> dict:
    return c.open_position_jd(db, ctx, "manpower.open_positions.download", open_id)


