"""HTTP shape for the Performance screens: envelopes, row versions as text, rows to response models,
signed links for appraisal letters."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.schemas.performance import (AppraisalDetailOut, AppraisalFormIn, AppraisalFormOut, AppraisalOut, CheckInIn,
                                     CycleIn, CycleOut, DecisionIn, FinaliseIn, GoalDetailOut, GoalIn, GoalOut,
                                     IncrementOut, KpiIn, KpiOut, OverviewOut, ParticipantsIn, ParticipantsOut,
                                     RatingScaleIn, RatingScaleOut, ReviewIn)
from app.services import performance_service as service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


# --- Rating scales -------------------------------------------------------------------------------

def _scale(row: dict[str, Any]) -> RatingScaleOut:
    return RatingScaleOut(**{**_rv(row), "levels": json.loads(row["levels"] or "[]")})


def list_scales(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = service.list_scales(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _scale)


def get_scale(db: Db, ctx: RequestContext, scale_id: int) -> dict:
    return {"data": _scale(service.get_scale(db, ctx, scale_id))}


def create_scale(db: Db, ctx: RequestContext, body: RatingScaleIn) -> dict:
    return {"data": _scale(service.save_scale(db, ctx, None, body, None))}


def update_scale(db: Db, ctx: RequestContext, scale_id: int, body: RatingScaleIn) -> dict:
    return {"data": _scale(service.save_scale(db, ctx, scale_id, body, row_version_in(body.row_version)))}


def delete_scale(db: Db, ctx: RequestContext, scale_id: int, row_version: str | None) -> None:
    service.delete_scale(db, ctx, scale_id, row_version_in(row_version))


# --- Appraisal forms -----------------------------------------------------------------------------

def _form(row: dict[str, Any]) -> AppraisalFormOut:
    return AppraisalFormOut(**{**_rv(row), "criteria": json.loads(row["criteria"] or "[]")})


def list_forms(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = service.list_forms(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _form)


def get_form(db: Db, ctx: RequestContext, form_id: int) -> dict:
    return {"data": _form(service.get_form(db, ctx, form_id))}


def create_form(db: Db, ctx: RequestContext, body: AppraisalFormIn) -> dict:
    return {"data": _form(service.save_form(db, ctx, None, body, None))}


def update_form(db: Db, ctx: RequestContext, form_id: int, body: AppraisalFormIn) -> dict:
    return {"data": _form(service.save_form(db, ctx, form_id, body, row_version_in(body.row_version)))}


def delete_form(db: Db, ctx: RequestContext, form_id: int, row_version: str | None) -> None:
    service.delete_form(db, ctx, form_id, row_version_in(row_version))


# --- KPIs ----------------------------------------------------------------------------------------

def _kpi(row: dict[str, Any]) -> KpiOut:
    return KpiOut(**_rv(row))


def list_kpis(db: Db, ctx: RequestContext, q: str | None, key_result_area: str | None, department_id: int | None,
              is_active: bool | None, paging: PageParams) -> dict:
    total, rows = service.list_kpis(db, ctx, q, key_result_area, department_id, is_active, paging.page,
                                    paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _kpi)


def get_kpi(db: Db, ctx: RequestContext, kpi_id: int) -> dict:
    return {"data": _kpi(service.get_kpi(db, ctx, kpi_id))}


def create_kpi(db: Db, ctx: RequestContext, body: KpiIn) -> dict:
    return {"data": _kpi(service.save_kpi(db, ctx, None, body, None))}


def update_kpi(db: Db, ctx: RequestContext, kpi_id: int, body: KpiIn) -> dict:
    return {"data": _kpi(service.save_kpi(db, ctx, kpi_id, body, row_version_in(body.row_version)))}


def delete_kpi(db: Db, ctx: RequestContext, kpi_id: int, row_version: str | None) -> None:
    service.delete_kpi(db, ctx, kpi_id, row_version_in(row_version))


# --- Goals ---------------------------------------------------------------------------------------

def _goal_detail(found: tuple[dict[str, Any], list[dict[str, Any]]]) -> dict:
    goal, check_ins = found
    return {"data": GoalDetailOut(**_rv(goal), check_ins=check_ins)}


def list_goals(db: Db, ctx: RequestContext, tab: str, employee_id: int | None, status: str | None,
               appraisal_cycle_id: int | None, overdue: bool | None, due_from: date | None, due_to: date | None,
               q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_goals(db, ctx, tab, employee_id, status, appraisal_cycle_id, overdue, due_from, due_to,
                                     q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: GoalOut(**_rv(r)))


def get_goal(db: Db, ctx: RequestContext, goal_id: int) -> dict:
    return _goal_detail(service.get_goal(db, ctx, goal_id))


def create_goal(db: Db, ctx: RequestContext, body: GoalIn) -> dict:
    return _goal_detail(service.save_goal(db, ctx, None, body, None))


def update_goal(db: Db, ctx: RequestContext, goal_id: int, body: GoalIn) -> dict:
    return _goal_detail(service.save_goal(db, ctx, goal_id, body, row_version_in(body.row_version)))


def check_in(db: Db, ctx: RequestContext, goal_id: int, body: CheckInIn) -> dict:
    return _goal_detail(service.check_in(db, ctx, goal_id, body, row_version_in(body.row_version)))


def delete_goal(db: Db, ctx: RequestContext, goal_id: int, row_version: str | None) -> None:
    service.delete_goal(db, ctx, goal_id, row_version_in(row_version))


# --- Appraisal cycles ----------------------------------------------------------------------------

def _cycle(row: dict[str, Any]) -> CycleOut:
    return CycleOut(**_rv(row))


def list_cycles(db: Db, ctx: RequestContext, status: str | None, q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_cycles(db, ctx, status, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _cycle)


def get_cycle(db: Db, ctx: RequestContext, cycle_id: int) -> dict:
    return {"data": _cycle(service.get_cycle(db, ctx, cycle_id))}


def create_cycle(db: Db, ctx: RequestContext, body: CycleIn) -> dict:
    return {"data": _cycle(service.save_cycle(db, ctx, None, body, None))}


def update_cycle(db: Db, ctx: RequestContext, cycle_id: int, body: CycleIn) -> dict:
    return {"data": _cycle(service.save_cycle(db, ctx, cycle_id, body, row_version_in(body.row_version)))}


def delete_cycle(db: Db, ctx: RequestContext, cycle_id: int, row_version: str | None) -> None:
    service.delete_cycle(db, ctx, cycle_id, row_version_in(row_version))


def add_participants(db: Db, ctx: RequestContext, cycle_id: int, body: ParticipantsIn) -> dict:
    cycle, added = service.add_participants(db, ctx, cycle_id, body.employee_ids, body.department_id)
    return {"data": ParticipantsOut(cycle=_cycle(cycle), added=added)}


def launch_cycle(db: Db, ctx: RequestContext, cycle_id: int, row_version: str) -> dict:
    return {"data": _cycle(service.launch_cycle(db, ctx, cycle_id, row_version_in(row_version)))}


def close_cycle(db: Db, ctx: RequestContext, cycle_id: int, row_version: str) -> dict:
    return {"data": _cycle(service.close_cycle(db, ctx, cycle_id, row_version_in(row_version)))}


# --- Appraisals and reviews ----------------------------------------------------------------------

def _appraisal_detail(ctx: RequestContext, row: dict[str, Any]) -> dict:
    letter = None
    if row.get("letter_file_id"):
        letter = FileRef(id=str(row["letter_file_id"]), name=row["letter_file_name"],
                         url=file_url(row["letter_file_id"], ctx.company_id))
    return {"data": AppraisalDetailOut(**{**_rv(row), "letter_file": letter})}


def list_appraisals(db: Db, ctx: RequestContext, code: str, tab: str, appraisal_cycle_id: int | None,
                    status: str | None, employee_id: int | None, q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_appraisals(db, ctx, code, tab, appraisal_cycle_id, status, employee_id, q, paging.page,
                                          paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: AppraisalOut(**_rv(r)))


def get_appraisal(db: Db, ctx: RequestContext, code: str, appraisal_id: int) -> dict:
    return _appraisal_detail(ctx, service.get_appraisal(db, ctx, code, appraisal_id))


def save_review(db: Db, ctx: RequestContext, appraisal_id: int, stage: str, body: ReviewIn) -> dict:
    row = service.save_review(db, ctx, appraisal_id, stage, body, row_version_in(body.row_version))
    return _appraisal_detail(ctx, row)


def finalise(db: Db, ctx: RequestContext, appraisal_id: int, body: FinaliseIn) -> dict:
    return _appraisal_detail(ctx, service.finalise(db, ctx, appraisal_id, body, row_version_in(body.row_version)))


def delete_appraisal(db: Db, ctx: RequestContext, appraisal_id: int, row_version: str | None) -> None:
    service.delete_appraisal(db, ctx, appraisal_id, row_version_in(row_version))


# --- Increments ----------------------------------------------------------------------------------

def _increment(row: dict[str, Any]) -> IncrementOut:
    return IncrementOut(**_rv(row))


def list_increments(db: Db, ctx: RequestContext, status: str | None, appraisal_cycle_id: int | None,
                    employee_id: int | None, q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_increments(db, ctx, status, appraisal_cycle_id, employee_id, q, paging.page,
                                          paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _increment)


def get_increment(db: Db, ctx: RequestContext, increment_id: int) -> dict:
    return {"data": _increment(service.get_increment(db, ctx, increment_id))}


def apply_increment(db: Db, ctx: RequestContext, increment_id: int, body: DecisionIn) -> dict:
    row = service.apply_increment(db, ctx, increment_id, body.remarks, row_version_in(body.row_version))
    return {"data": _increment(row)}


def reject_increment(db: Db, ctx: RequestContext, increment_id: int, body: DecisionIn) -> dict:
    row = service.reject_increment(db, ctx, increment_id, body.remarks, row_version_in(body.row_version))
    return {"data": _increment(row)}


# --- Overview ------------------------------------------------------------------------------------

def overview(db: Db, ctx: RequestContext, employee_id: int | None) -> dict:
    row = service.overview(db, ctx, employee_id)
    goals = {"total": row["goals_total"], "not_started": row["goals_not_started"] or 0,
             "in_progress": row["goals_in_progress"] or 0, "completed": row["goals_completed"] or 0,
             "cancelled": row["goals_cancelled"] or 0, "overdue": row["goals_overdue"] or 0,
             "weighted_progress": row["weighted_progress"]}
    return {"data": OverviewOut(**row, goals=goals)}
