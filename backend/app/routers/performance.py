"""Performance: My Performance overview, goals and their check-ins, the KPI library, appraisal cycles and their
participants, self and manager reviews, finalising appraisals, increments proposed for payroll, and the
settings (rating scales, appraisal forms).

Appraisals have two lists over the same records: /reviews (staff and managers: My / Team / All, reviews.view)
and /appraisals (HR running the cycles, appraisals.view)."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import performance_controller as controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.performance import (AppraisalDetailOut, AppraisalFormIn, AppraisalFormOut, AppraisalOut, CheckInIn,
                                     CycleIn, CycleOut, DecisionIn, FinaliseIn, GoalDetailOut, GoalIn, GoalOut,
                                     IncrementOut, KpiIn, KpiOut, OverviewOut, ParticipantsIn, ParticipantsOut,
                                     RatingScaleIn, RatingScaleOut, ReviewIn, RowVersionIn)
from app.services.performance_service import APPRAISALS_VIEW, REVIEWS_VIEW

router = APIRouter(prefix="/performance", tags=["performance"])

Tab = Literal["my", "team", "all"]
GoalStatus = Literal["not_started", "in_progress", "completed", "cancelled"]
AppraisalStatus = Literal["draft", "self_review", "manager_review", "reviewed", "finalised"]
CycleStatus = Literal["draft", "active", "closed"]
IncrementStatus = Literal["proposed", "applied", "rejected"]
NO_CONTENT = status.HTTP_204_NO_CONTENT


# --- My Performance overview ---------------------------------------------------------------------

@router.get("/overview", response_model=Item[OverviewOut])
def overview(employee_id: int | None = Query(None, alias="employeeId"), db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("performance.overview.view"))) -> dict:
    return controller.overview(db, ctx, employee_id)


# --- Goals ---------------------------------------------------------------------------------------

@router.get("/goals", response_model=Paginated[GoalOut])
def list_goals(tab: Tab = "all", employee_id: int | None = Query(None, alias="employeeId"),
               goal_status: GoalStatus | None = Query(None, alias="status"),
               cycle_id: int | None = Query(None, alias="cycleId"), overdue: bool | None = None,
               due_from: date | None = Query(None, alias="dueFrom"), due_to: date | None = Query(None, alias="dueTo"),
               q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("performance.goals.view"))) -> dict:
    return controller.list_goals(db, ctx, tab, employee_id, goal_status, cycle_id, overdue, due_from, due_to, q, paging)


@router.get("/goals/{goal_id}", response_model=Item[GoalDetailOut])
def get_goal(goal_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("performance.goals.view"))) -> dict:
    return controller.get_goal(db, ctx, goal_id)


@router.post("/goals", response_model=Item[GoalDetailOut], status_code=status.HTTP_201_CREATED)
def create_goal(body: GoalIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.goals.create"))) -> dict:
    return controller.create_goal(db, ctx, body)


@router.put("/goals/{goal_id}", response_model=Item[GoalDetailOut])
def update_goal(goal_id: int, body: GoalIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.goals.edit"))) -> dict:
    return controller.update_goal(db, ctx, goal_id, body)


@router.post("/goals/{goal_id}/check-ins", response_model=Item[GoalDetailOut])
def check_in(goal_id: int, body: CheckInIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("performance.goals.edit"))) -> dict:
    return controller.check_in(db, ctx, goal_id, body)


@router.delete("/goals/{goal_id}", status_code=NO_CONTENT)
def delete_goal(goal_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.goals.delete"))) -> Response:
    controller.delete_goal(db, ctx, goal_id, row_version)
    return Response(status_code=NO_CONTENT)


# --- KPIs ----------------------------------------------------------------------------------------

@router.get("/kpis", response_model=Paginated[KpiOut])
def list_kpis(q: str | None = None, key_result_area: str | None = Query(None, alias="keyResultArea"),
              department_id: int | None = Query(None, alias="departmentId"),
              is_active: bool | None = Query(None, alias="isActive"), paging: PageParams = Depends(page_params),
              db: Db = Depends(get_db), ctx: RequestContext = Depends(require("performance.kpis.view"))) -> dict:
    return controller.list_kpis(db, ctx, q, key_result_area, department_id, is_active, paging)


@router.get("/kpis/{kpi_id}", response_model=Item[KpiOut])
def get_kpi(kpi_id: int, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("performance.kpis.view"))) -> dict:
    return controller.get_kpi(db, ctx, kpi_id)


@router.post("/kpis", response_model=Item[KpiOut], status_code=status.HTTP_201_CREATED)
def create_kpi(body: KpiIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("performance.kpis.create"))) -> dict:
    return controller.create_kpi(db, ctx, body)


@router.put("/kpis/{kpi_id}", response_model=Item[KpiOut])
def update_kpi(kpi_id: int, body: KpiIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("performance.kpis.edit"))) -> dict:
    return controller.update_kpi(db, ctx, kpi_id, body)


@router.delete("/kpis/{kpi_id}", status_code=NO_CONTENT)
def delete_kpi(kpi_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("performance.kpis.delete"))) -> Response:
    controller.delete_kpi(db, ctx, kpi_id, row_version)
    return Response(status_code=NO_CONTENT)


# --- Appraisal cycles ----------------------------------------------------------------------------

@router.get("/cycles", response_model=Paginated[CycleOut])
def list_cycles(cycle_status: CycleStatus | None = Query(None, alias="status"), q: str | None = None,
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.appraisals.view"))) -> dict:
    return controller.list_cycles(db, ctx, cycle_status, q, paging)


@router.get("/cycles/{cycle_id}", response_model=Item[CycleOut])
def get_cycle(cycle_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("performance.appraisals.view"))) -> dict:
    return controller.get_cycle(db, ctx, cycle_id)


@router.post("/cycles", response_model=Item[CycleOut], status_code=status.HTTP_201_CREATED)
def create_cycle(body: CycleIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.appraisals.create"))) -> dict:
    return controller.create_cycle(db, ctx, body)


@router.put("/cycles/{cycle_id}", response_model=Item[CycleOut])
def update_cycle(cycle_id: int, body: CycleIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.appraisals.edit"))) -> dict:
    return controller.update_cycle(db, ctx, cycle_id, body)


@router.delete("/cycles/{cycle_id}", status_code=NO_CONTENT)
def delete_cycle(cycle_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.appraisals.delete"))) -> Response:
    controller.delete_cycle(db, ctx, cycle_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.post("/cycles/{cycle_id}/participants", response_model=Item[ParticipantsOut])
def add_participants(cycle_id: int, body: ParticipantsIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("performance.appraisals.edit"))) -> dict:
    return controller.add_participants(db, ctx, cycle_id, body)


@router.post("/cycles/{cycle_id}/launch", response_model=Item[CycleOut])
def launch_cycle(cycle_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.appraisals.process"))) -> dict:
    return controller.launch_cycle(db, ctx, cycle_id, body.row_version)


@router.post("/cycles/{cycle_id}/close", response_model=Item[CycleOut])
def close_cycle(cycle_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.appraisals.close"))) -> dict:
    return controller.close_cycle(db, ctx, cycle_id, body.row_version)


# --- Appraisals (HR) -----------------------------------------------------------------------------

@router.get("/appraisals", response_model=Paginated[AppraisalOut])
def list_appraisals(tab: Tab = "all", cycle_id: int | None = Query(None, alias="cycleId"),
                    appraisal_status: AppraisalStatus | None = Query(None, alias="status"),
                    employee_id: int | None = Query(None, alias="employeeId"), q: str | None = None,
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require(APPRAISALS_VIEW))) -> dict:
    return controller.list_appraisals(db, ctx, APPRAISALS_VIEW, tab, cycle_id, appraisal_status, employee_id, q,
                                      paging)


@router.get("/appraisals/{appraisal_id}", response_model=Item[AppraisalDetailOut])
def get_appraisal(appraisal_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require(APPRAISALS_VIEW))) -> dict:
    return controller.get_appraisal(db, ctx, APPRAISALS_VIEW, appraisal_id)


@router.post("/appraisals/{appraisal_id}/finalise", response_model=Item[AppraisalDetailOut])
def finalise(appraisal_id: int, body: FinaliseIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("performance.appraisals.approve"))) -> dict:
    return controller.finalise(db, ctx, appraisal_id, body)


@router.delete("/appraisals/{appraisal_id}", status_code=NO_CONTENT)
def delete_appraisal(appraisal_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("performance.appraisals.delete"))) -> Response:
    controller.delete_appraisal(db, ctx, appraisal_id, row_version)
    return Response(status_code=NO_CONTENT)


# --- Reviews (staff and managers) ----------------------------------------------------------------

@router.get("/reviews", response_model=Paginated[AppraisalOut])
def list_reviews(tab: Tab = "my", cycle_id: int | None = Query(None, alias="cycleId"),
                 appraisal_status: AppraisalStatus | None = Query(None, alias="status"),
                 employee_id: int | None = Query(None, alias="employeeId"), q: str | None = None,
                 paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require(REVIEWS_VIEW))) -> dict:
    return controller.list_appraisals(db, ctx, REVIEWS_VIEW, tab, cycle_id, appraisal_status, employee_id, q, paging)


@router.get("/reviews/{appraisal_id}", response_model=Item[AppraisalDetailOut])
def get_review(appraisal_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require(REVIEWS_VIEW))) -> dict:
    return controller.get_appraisal(db, ctx, REVIEWS_VIEW, appraisal_id)


@router.put("/reviews/{appraisal_id}/self", response_model=Item[AppraisalDetailOut])
def save_self_review(appraisal_id: int, body: ReviewIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("performance.reviews.submit"))) -> dict:
    return controller.save_review(db, ctx, appraisal_id, "self", body)


@router.put("/reviews/{appraisal_id}/manager", response_model=Item[AppraisalDetailOut])
def save_manager_review(appraisal_id: int, body: ReviewIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("performance.reviews.evaluate"))) -> dict:
    return controller.save_review(db, ctx, appraisal_id, "manager", body)


# --- Increments ----------------------------------------------------------------------------------

@router.get("/increments", response_model=Paginated[IncrementOut])
def list_increments(increment_status: IncrementStatus | None = Query(None, alias="status"),
                    cycle_id: int | None = Query(None, alias="cycleId"),
                    employee_id: int | None = Query(None, alias="employeeId"), q: str | None = None,
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("performance.increments.view"))) -> dict:
    return controller.list_increments(db, ctx, increment_status, cycle_id, employee_id, q, paging)


@router.get("/increments/{increment_id}", response_model=Item[IncrementOut])
def get_increment(increment_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("performance.increments.view"))) -> dict:
    return controller.get_increment(db, ctx, increment_id)


@router.post("/increments/{increment_id}/apply", response_model=Item[IncrementOut])
def apply_increment(increment_id: int, body: DecisionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("performance.increments.process"))) -> dict:
    return controller.apply_increment(db, ctx, increment_id, body)


@router.post("/increments/{increment_id}/reject", response_model=Item[IncrementOut])
def reject_increment(increment_id: int, body: DecisionIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("performance.increments.reject"))) -> dict:
    return controller.reject_increment(db, ctx, increment_id, body)


# --- Settings: rating scales ---------------------------------------------------------------------

@router.get("/rating-scales", response_model=Paginated[RatingScaleOut])
def list_scales(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.settings.rating_scales.view"))) -> dict:
    return controller.list_scales(db, ctx, q, is_active, paging)


@router.get("/rating-scales/{scale_id}", response_model=Item[RatingScaleOut])
def get_scale(scale_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("performance.settings.rating_scales.view"))) -> dict:
    return controller.get_scale(db, ctx, scale_id)


@router.post("/rating-scales", response_model=Item[RatingScaleOut], status_code=status.HTTP_201_CREATED)
def create_scale(body: RatingScaleIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.settings.rating_scales.create"))) -> dict:
    return controller.create_scale(db, ctx, body)


@router.put("/rating-scales/{scale_id}", response_model=Item[RatingScaleOut])
def update_scale(scale_id: int, body: RatingScaleIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.settings.rating_scales.edit"))) -> dict:
    return controller.update_scale(db, ctx, scale_id, body)


@router.delete("/rating-scales/{scale_id}", status_code=NO_CONTENT)
def delete_scale(scale_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("performance.settings.rating_scales.delete"))) -> Response:
    controller.delete_scale(db, ctx, scale_id, row_version)
    return Response(status_code=NO_CONTENT)


# --- Settings: appraisal forms -------------------------------------------------------------------

@router.get("/forms", response_model=Paginated[AppraisalFormOut])
def list_forms(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("performance.settings.forms.view"))) -> dict:
    return controller.list_forms(db, ctx, q, is_active, paging)


@router.get("/forms/{form_id}", response_model=Item[AppraisalFormOut])
def get_form(form_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("performance.settings.forms.view"))) -> dict:
    return controller.get_form(db, ctx, form_id)


@router.post("/forms", response_model=Item[AppraisalFormOut], status_code=status.HTTP_201_CREATED)
def create_form(body: AppraisalFormIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.settings.forms.create"))) -> dict:
    return controller.create_form(db, ctx, body)


@router.put("/forms/{form_id}", response_model=Item[AppraisalFormOut])
def update_form(form_id: int, body: AppraisalFormIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.settings.forms.edit"))) -> dict:
    return controller.update_form(db, ctx, form_id, body)


@router.delete("/forms/{form_id}", status_code=NO_CONTENT)
def delete_form(form_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("performance.settings.forms.delete"))) -> Response:
    controller.delete_form(db, ctx, form_id, row_version)
    return Response(status_code=NO_CONTENT)
