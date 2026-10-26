"""Performance rules. Checks that need the data (scope, stages, locks, duplicates, row versions) live in the
procedures; rules between fields (weights making 100, goal progress from actual / target, what an increment
needs) live here, and so does what a person may see of their own appraisal while it is under way.

Applying an increment spans two modules in one transaction: payroll's salary revision procedure writes the
new salary, then the proposal records which revision it became.
"""
import json
from datetime import date
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import performance_repo as repo
from app.schemas.performance import (AppraisalFormIn, CheckInIn, CycleIn, FinaliseIn, GoalIn, KpiIn, RatingScaleIn,
                                     ReviewIn)

# The permission each scoped procedure filters employees by: the code the endpoint required.
OVERVIEW_VIEW = "performance.overview.view"
GOALS_VIEW = "performance.goals.view"
GOALS_CREATE = "performance.goals.create"
GOALS_EDIT = "performance.goals.edit"
GOALS_DELETE = "performance.goals.delete"
APPRAISALS_VIEW = "performance.appraisals.view"
APPRAISALS_EDIT = "performance.appraisals.edit"
APPRAISALS_DELETE = "performance.appraisals.delete"
APPRAISALS_APPROVE = "performance.appraisals.approve"
REVIEWS_VIEW = "performance.reviews.view"
REVIEWS_SUBMIT = "performance.reviews.submit"
REVIEWS_EVALUATE = "performance.reviews.evaluate"
INCREMENTS_VIEW = "performance.increments.view"
INCREMENTS_PROCESS = "performance.increments.process"
INCREMENTS_REJECT = "performance.increments.reject"

HUNDRED = Decimal(100)


def _invalid(errors: dict[str, str]) -> AppError:
    return AppError(422, "VALIDATION_FAILED", "Some fields need your attention.", errors)


# --- Rating scales -------------------------------------------------------------------------------

def list_scales(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_scales(db, ctx.company_id, search, is_active, page, page_size)


def get_scale(db: Db, ctx: RequestContext, scale_id: int) -> dict[str, Any]:
    return repo.get_scale(db, ctx.company_id, scale_id)


def save_scale(db: Db, ctx: RequestContext, scale_id: int | None, body: RatingScaleIn,
               row_version: bytes | None) -> dict[str, Any]:
    scores = [lvl.score for lvl in body.levels]
    if len(set(scores)) != len(scores):
        raise _invalid({"levels": "Two levels have the same score."})
    levels = [lvl.model_dump(by_alias=True, mode="json") for lvl in sorted(body.levels, key=lambda x: x.score)]
    return repo.save_scale(db, ctx.company_id, ctx.user_id, scale_id, body.name, body.is_default, body.is_active,
                           json.dumps(levels), row_version)


def delete_scale(db: Db, ctx: RequestContext, scale_id: int, row_version: bytes) -> None:
    repo.delete_scale(db, ctx.company_id, ctx.user_id, scale_id, row_version)


# --- Appraisal forms -----------------------------------------------------------------------------

def list_forms(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_forms(db, ctx.company_id, search, is_active, page, page_size)


def get_form(db: Db, ctx: RequestContext, form_id: int) -> dict[str, Any]:
    return repo.get_form(db, ctx.company_id, form_id)


def save_form(db: Db, ctx: RequestContext, form_id: int | None, body: AppraisalFormIn,
              row_version: bytes | None) -> dict[str, Any]:
    total = sum((c.weight for c in body.criteria), Decimal(0)) + body.goals_weight
    if total != HUNDRED:
        raise _invalid({"criteria": f"The criteria weights and the goals weight must add up to 100 (now {total:g})."})
    if not body.criteria and body.goals_weight != HUNDRED:
        raise _invalid({"criteria": "Add at least one criterion."})
    names = [c.name.strip().lower() for c in body.criteria]
    if len(set(names)) != len(names):
        raise _invalid({"criteria": "Two criteria have the same name."})
    criteria = [c.model_dump(by_alias=True, mode="json") for c in body.criteria]
    return repo.save_form(db, ctx.company_id, ctx.user_id, form_id, body.name, body.description, body.rating_scale_id,
                          body.goals_weight, body.has_self_review, body.is_active, json.dumps(criteria), row_version)


def delete_form(db: Db, ctx: RequestContext, form_id: int, row_version: bytes) -> None:
    repo.delete_form(db, ctx.company_id, ctx.user_id, form_id, row_version)


# --- KPIs ----------------------------------------------------------------------------------------

def list_kpis(db: Db, ctx: RequestContext, search: str | None, key_result_area: str | None,
              department_id: int | None, is_active: bool | None, page: int,
              page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_kpis(db, ctx.company_id, search, key_result_area, department_id, is_active, page, page_size)


def get_kpi(db: Db, ctx: RequestContext, kpi_id: int) -> dict[str, Any]:
    return repo.get_kpi(db, ctx.company_id, kpi_id)


def save_kpi(db: Db, ctx: RequestContext, kpi_id: int | None, body: KpiIn, row_version: bytes | None) -> dict[str, Any]:
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return repo.save_kpi(db, ctx.company_id, ctx.user_id, kpi_id, fields, row_version)


def delete_kpi(db: Db, ctx: RequestContext, kpi_id: int, row_version: bytes) -> None:
    repo.delete_kpi(db, ctx.company_id, ctx.user_id, kpi_id, row_version)


# --- Goals ---------------------------------------------------------------------------------------

def settle_progress(target: Decimal | None, actual: Decimal | None, progress: Decimal | None,
                    status: str | None) -> tuple[Decimal, str]:
    """Progress and status that agree: progress from actual / target when both are known; 100% completes the
    goal and a completed goal is at 100%; otherwise the status follows the progress unless it is cancelled."""
    if target and actual is not None:
        progress = max(Decimal(0), min(HUNDRED, actual / target * HUNDRED))
    progress = (progress if progress is not None else Decimal(0)).quantize(Decimal("0.01"), ROUND_HALF_UP)
    if status == "cancelled":
        return progress, status
    if status == "completed" or progress >= HUNDRED:
        return HUNDRED, "completed"
    if status is None or status == "not_started" and progress > 0:
        return progress, "in_progress" if progress > 0 else "not_started"
    return progress, status


def _goal_fields(employee_id: int, body: GoalIn | dict[str, Any], progress: Decimal, status: str,
                 comments: str | None) -> dict[str, Any]:
    src = body.model_dump(by_alias=False) if isinstance(body, GoalIn) else body
    return {"employee_id": employee_id, "appraisal_cycle_id": src.get("appraisal_cycle_id"),
            "kpi_id": src.get("kpi_id"), "title": src["title"], "description": src.get("description"),
            "start_date": src.get("start_date"), "due_date": src["due_date"], "weight": src["weight"],
            "target_value": src.get("target_value"), "actual_value": src.get("actual_value"), "progress": progress,
            "status": status, "comments": comments}


def list_goals(db: Db, ctx: RequestContext, tab: str, employee_id: int | None, status: str | None,
               appraisal_cycle_id: int | None, overdue: bool | None, due_from: date | None, due_to: date | None,
               search: str | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    if due_from and due_to and due_to < due_from:
        raise _invalid({"dueTo": "The end date must be on or after the start date."})
    return repo.list_goals(db, ctx.company_id, ctx.user_id, GOALS_VIEW, tab, employee_id, status, appraisal_cycle_id,
                           overdue, due_from, due_to, search, page, page_size)


def get_goal(db: Db, ctx: RequestContext, goal_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return repo.get_goal(db, ctx.company_id, ctx.user_id, GOALS_VIEW, goal_id)


def save_goal(db: Db, ctx: RequestContext, goal_id: int | None, body: GoalIn,
              row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    employee_id = body.employee_id or ctx.employee_id
    if employee_id is None:
        raise _invalid({"employeeId": "Choose the employee the goal is for."})
    if body.start_date and body.due_date < body.start_date:
        raise _invalid({"dueDate": "The due date must be on or after the start date."})
    progress, status = settle_progress(body.target_value, body.actual_value, body.progress, body.status)
    code = GOALS_CREATE if goal_id is None else GOALS_EDIT
    return repo.save_goal(db, ctx.company_id, ctx.user_id, code, goal_id,
                          _goal_fields(employee_id, body, progress, status, body.comments), row_version)


def check_in(db: Db, ctx: RequestContext, goal_id: int, body: CheckInIn,
             row_version: bytes) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """A progress update: the goal as it is, with new progress, actual value or status."""
    goal, _ = repo.get_goal(db, ctx.company_id, ctx.user_id, GOALS_EDIT, goal_id)
    actual = body.actual_value if body.actual_value is not None else goal["actual_value"]
    given = body.progress if body.progress is not None else goal["progress"]
    status = body.status or (None if goal["status"] in ("not_started", "in_progress") else goal["status"])
    progress, status = settle_progress(goal["target_value"], actual, given, status)
    fields = _goal_fields(int(goal["employee_id"]), {**goal, "actual_value": actual}, progress, status, body.comments)
    return repo.save_goal(db, ctx.company_id, ctx.user_id, GOALS_EDIT, goal_id, fields, row_version)


def delete_goal(db: Db, ctx: RequestContext, goal_id: int, row_version: bytes) -> None:
    repo.delete_goal(db, ctx.company_id, ctx.user_id, GOALS_DELETE, goal_id, row_version)


# --- Appraisal cycles ----------------------------------------------------------------------------

def list_cycles(db: Db, ctx: RequestContext, status: str | None, search: str | None, page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_cycles(db, ctx.company_id, status, search, page, page_size)


def get_cycle(db: Db, ctx: RequestContext, cycle_id: int) -> dict[str, Any]:
    return repo.get_cycle(db, ctx.company_id, cycle_id)


def save_cycle(db: Db, ctx: RequestContext, cycle_id: int | None, body: CycleIn,
               row_version: bytes | None) -> dict[str, Any]:
    errors: dict[str, str] = {}
    if body.end_date < body.start_date:
        errors["endDate"] = "The period must end on or after its start."
    if body.self_review_due_date and body.manager_review_due_date \
            and body.manager_review_due_date < body.self_review_due_date:
        errors["managerReviewDueDate"] = "Manager reviews are due after self reviews."
    if errors:
        raise _invalid(errors)
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return repo.save_cycle(db, ctx.company_id, ctx.user_id, cycle_id, fields, row_version)


def delete_cycle(db: Db, ctx: RequestContext, cycle_id: int, row_version: bytes) -> None:
    repo.delete_cycle(db, ctx.company_id, ctx.user_id, cycle_id, row_version)


def add_participants(db: Db, ctx: RequestContext, cycle_id: int, employee_ids: list[int],
                     department_id: int | None) -> tuple[dict[str, Any], int]:
    if not employee_ids and department_id is None:
        raise _invalid({"employeeIds": "Choose employees or a department."})
    return repo.add_participants(db, ctx.company_id, ctx.user_id, APPRAISALS_EDIT, cycle_id, json.dumps(employee_ids),
                                 department_id)


def launch_cycle(db: Db, ctx: RequestContext, cycle_id: int, row_version: bytes) -> dict[str, Any]:
    return repo.launch_cycle(db, ctx.company_id, ctx.user_id, cycle_id, row_version)


def close_cycle(db: Db, ctx: RequestContext, cycle_id: int, row_version: bytes) -> dict[str, Any]:
    return repo.close_cycle(db, ctx.company_id, ctx.user_id, cycle_id, row_version)


# --- Appraisals and reviews ----------------------------------------------------------------------

_MANAGER_FIELDS = ("manager_score", "manager_comments", "development_needs", "final_score", "final_rating_label",
                   "final_comments")
_SELF_FIELDS = ("self_score", "self_comments")


def _as_seen_by(ctx: RequestContext, row: dict[str, Any]) -> dict[str, Any]:
    """While an appraisal is under way the employee does not see the manager's ratings, and nobody else sees
    the self ratings before the self review is submitted."""
    own = ctx.employee_id is not None and str(row["employee_id"]) == str(ctx.employee_id)
    hide_manager = own and row["status"] != "finalised"
    hide_self = not own and row["status"] in ("draft", "self_review")
    out = dict(row)
    for f in (_MANAGER_FIELDS if hide_manager else ()) + (_SELF_FIELDS if hide_self else ()):
        if f in out:
            out[f] = None
    if "ratings" in out:
        out["ratings"] = [{**r, **({"manager_rating": None, "manager_comment": None} if hide_manager else {}),
                           **({"self_rating": None, "self_comment": None} if hide_self else {})}
                          for r in out["ratings"]]
    return out


def list_appraisals(db: Db, ctx: RequestContext, code: str, tab: str, appraisal_cycle_id: int | None,
                    status: str | None, employee_id: int | None, search: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = repo.list_appraisals(db, ctx.company_id, ctx.user_id, code, tab, appraisal_cycle_id, status,
                                       employee_id, search, page, page_size)
    return total, [_as_seen_by(ctx, r) for r in rows]


def get_appraisal(db: Db, ctx: RequestContext, code: str, appraisal_id: int) -> dict[str, Any]:
    return _as_seen_by(ctx, repo.get_appraisal(db, ctx.company_id, ctx.user_id, code, appraisal_id))


def save_review(db: Db, ctx: RequestContext, appraisal_id: int, stage: str, body: ReviewIn,
                row_version: bytes) -> dict[str, Any]:
    ids = [r.criterion_id for r in body.ratings]
    if len(set(ids)) != len(ids):
        raise _invalid({"ratings": "A criterion is rated twice."})
    code = REVIEWS_SUBMIT if stage == "self" else REVIEWS_EVALUATE
    ratings = [r.model_dump(by_alias=True, mode="json") for r in body.ratings]
    row = repo.save_review(db, ctx.company_id, ctx.user_id, code, appraisal_id, stage, json.dumps(ratings),
                           body.comments, body.development_needs if stage == "manager" else None, body.submit,
                           row_version)
    return _as_seen_by(ctx, row)


def finalise(db: Db, ctx: RequestContext, appraisal_id: int, body: FinaliseIn, row_version: bytes) -> dict[str, Any]:
    inc = body.increment
    if body.outcome == "increment" and inc is None:
        raise _invalid({"increment": "Give the increment: its type, value and effective date."})
    if body.outcome != "increment":
        inc = None
    elif inc.change_type == "percent" and inc.change_value > HUNDRED:
        raise _invalid({"increment.changeValue": "A percentage increment is at most 100."})
    fields = {"final_score": body.final_score, "final_comments": body.final_comments, "outcome": body.outcome,
              "change_type": inc.change_type if inc else None, "change_value": inc.change_value if inc else None,
              "effective_date": inc.effective_date if inc else None, "letter_file_id": body.letter_file_id}
    row = repo.finalise(db, ctx.company_id, ctx.user_id, APPRAISALS_APPROVE, appraisal_id, fields, row_version)
    return _as_seen_by(ctx, row)


def delete_appraisal(db: Db, ctx: RequestContext, appraisal_id: int, row_version: bytes) -> None:
    repo.delete_appraisal(db, ctx.company_id, ctx.user_id, APPRAISALS_DELETE, appraisal_id, row_version)


# --- Increments ----------------------------------------------------------------------------------

def list_increments(db: Db, ctx: RequestContext, status: str | None, appraisal_cycle_id: int | None,
                    employee_id: int | None, search: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_increments(db, ctx.company_id, ctx.user_id, INCREMENTS_VIEW, status, appraisal_cycle_id,
                                employee_id, search, page, page_size)


def get_increment(db: Db, ctx: RequestContext, increment_id: int) -> dict[str, Any]:
    return repo.get_increment(db, ctx.company_id, ctx.user_id, INCREMENTS_VIEW, increment_id)


def apply_increment(db: Db, ctx: RequestContext, increment_id: int, remarks: str | None,
                    row_version: bytes) -> dict[str, Any]:
    """Writes the increment as payroll's salary revision and records it, in one transaction."""
    with db.transaction():
        p = repo.get_increment(db, ctx.company_id, ctx.user_id, INCREMENTS_PROCESS, increment_id)
        if p["row_version"] != row_version:
            raise AppError(409, "CONFLICT", "Someone else changed this increment. Reload it and try again.")
        if p["status"] != "proposed":
            raise AppError(409, "INCREMENT_DECIDED", "This increment has already been applied or rejected.",
                           {"status": "This increment has already been applied or rejected."})
        if ctx.employee_id is not None and int(p["employee_id"]) == ctx.employee_id:
            raise AppError(403, "FORBIDDEN", "You cannot decide your own increment.")
        revision = repo.salary_revision_save(db, ctx.company_id, ctx.user_id, INCREMENTS_PROCESS,
                                             int(p["employee_id"]), p["effective_date"], p["change_type"],
                                             p["change_value"])
        return repo.decide_increment(db, ctx.company_id, ctx.user_id, INCREMENTS_PROCESS, increment_id, "applied",
                                     revision["id"], remarks, row_version)


def reject_increment(db: Db, ctx: RequestContext, increment_id: int, remarks: str | None,
                     row_version: bytes) -> dict[str, Any]:
    return repo.decide_increment(db, ctx.company_id, ctx.user_id, INCREMENTS_REJECT, increment_id, "rejected", None,
                                 remarks, row_version)


# --- Overview ------------------------------------------------------------------------------------

def overview(db: Db, ctx: RequestContext, employee_id: int | None) -> dict[str, Any]:
    person, upcoming, appraisals = repo.overview(db, ctx.company_id, ctx.user_id, OVERVIEW_VIEW, employee_id)
    return {**person, "upcoming_goals": upcoming, "appraisals": appraisals}
