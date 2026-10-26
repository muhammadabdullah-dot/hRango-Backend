"""Warning rules. Which clock events suit what a policy watches, week days, and penalty figures are
checked here; duplicates, row versions and the raising of warnings live in the procedures."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import warning_repo
from app.schemas.warning import PenaltyRuleIn, WarningPolicyIn

WARNINGS_VIEW = "warning.warnings.view"
WARNINGS_PROCESS = "warning.warnings.process"

# The clock events each kind of policy can measure.
_EVENTS = {"late_arrival": {"clock_in"}, "early_departure": {"clock_out"}, "overtime": {"clock_in", "clock_out"},
           "half_day_leave": {"clock_in", "clock_out"}}
_SHARE = {"half_day": 50, "full_day": 100}


def _invalid(errors: dict[str, str]) -> AppError:
    return AppError(422, "VALIDATION_FAILED", "Some fields need your attention.", errors)


def list_policies(db: Db, ctx: RequestContext, search: str | None, applies_to: str | None, page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return warning_repo.list_policies(db, ctx.company_id, search, applies_to, page, page_size)


def get_policy(db: Db, ctx: RequestContext, policy_id: int) -> dict[str, Any]:
    return warning_repo.get_policy(db, ctx.company_id, policy_id)


def save_policy(db: Db, ctx: RequestContext, policy_id: int | None, body: WarningPolicyIn,
                row_version: bytes | None) -> dict[str, Any]:
    errors: dict[str, str] = {}
    events = [r.clock_event for r in body.rules]
    if len(set(events)) != len(events):
        errors["rules"] = "One rule per clock event."
    for i, r in enumerate(body.rules):
        if r.clock_event not in _EVENTS[body.applies_to]:
            errors[f"rules.{i}.clockEvent"] = "This clock event does not apply to what the policy watches."
    if body.applies_to == "half_day_leave" and len(body.rules) > 1:
        errors["rules"] = "A half-day leave policy has one rule."
    week_start, week_end = body.week_start_day, body.week_end_day
    if body.period == "week":
        week_start = week_start or "mon"
    else:
        week_start = week_end = None
    if errors:
        raise _invalid(errors)
    rules = [r.model_dump(by_alias=True, mode="json") for r in body.rules]
    return warning_repo.save_policy(db, ctx.company_id, ctx.user_id, policy_id, body.title, body.applies_to,
                                    body.period, body.grace_minutes, week_start, week_end, body.is_active,
                                    json.dumps(rules), row_version)


def delete_policy(db: Db, ctx: RequestContext, policy_id: int, row_version: bytes) -> None:
    warning_repo.delete_policy(db, ctx.company_id, ctx.user_id, policy_id, row_version)


def _penalty(i: int, p: PenaltyRuleIn, errors: dict[str, str]) -> dict[str, Any]:
    if p.penalty_type == "percentage" and p.percentage is None:
        errors[f"penalties.{i}.percentage"] = "Give the percentage of a day."
    if p.deduction in ("leave", "both") and p.leave_type_id is None:
        errors[f"penalties.{i}.leaveTypeId"] = "Choose the leave type the deduction is taken from."
    share = _SHARE.get(p.penalty_type, p.percentage)
    return {"afterCount": p.after_count, "period": p.period, "penaltyType": p.penalty_type,
            "percentage": None if share is None else float(share), "deduction": p.deduction,
            "leaveTypeId": p.leave_type_id if p.deduction in ("leave", "both") else None}


def save_penalties(db: Db, ctx: RequestContext, policy_id: int, penalties: list[PenaltyRuleIn],
                   row_version: bytes) -> dict[str, Any]:
    errors: dict[str, str] = {}
    rows = [_penalty(i, p, errors) for i, p in enumerate(penalties)]
    if len({(p.period, p.after_count) for p in penalties}) != len(penalties):
        errors["penalties"] = "Two penalties have the same count and period."
    if errors:
        raise _invalid(errors)
    return warning_repo.save_penalties(db, ctx.company_id, ctx.user_id, policy_id, json.dumps(rows), row_version)


def list_penalties(db: Db, ctx: RequestContext, policy_id: int | None, page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return warning_repo.list_penalties(db, ctx.company_id, policy_id, page, page_size)


def list_warnings(db: Db, ctx: RequestContext, employee_id: int | None, policy_id: int | None,
                  applies_to: str | None, from_date: date | None, to_date: date | None, search: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return warning_repo.list_warnings(db, ctx.company_id, ctx.user_id, WARNINGS_VIEW, employee_id, policy_id,
                                      applies_to, from_date, to_date, search, page, page_size)


def raise_warnings(db: Db, ctx: RequestContext, from_date: date, to_date: date, employee_id: int | None,
                   policy_id: int | None) -> dict[str, Any]:
    if to_date < from_date:
        raise _invalid({"toDate": "The end date must be on or after the start date."})
    return warning_repo.raise_warnings(db, ctx.company_id, ctx.user_id, WARNINGS_PROCESS, from_date, to_date,
                                       employee_id, policy_id)


def list_history(db: Db, ctx: RequestContext, policy_id: int | None, page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return warning_repo.list_history(db, ctx.company_id, policy_id, page, page_size)
