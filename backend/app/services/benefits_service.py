"""Benefits rules. Plan years, plans, enrollment windows and plan files are company-wide records:
changing them needs the permission held with company scope (a code granted with own scope, as the
Employee role's *.create is, does not reach them). Elections, health benefits and perks belong to
employees and are filtered in the procedures by the code the endpoint required."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import forbidden, invalid
from app.middlewares.auth import RequestContext
from app.repos import benefits_repo
from app.schemas.benefits import BenefitPlanIn, ElectionIn, HealthBenefitIn, PerkIn, PlanYearIn, WindowIn


def _company_wide(ctx: RequestContext) -> None:
    if not ctx.sees_company:
        raise forbidden("Benefit plan years, plans, windows and files are changed only with company-wide access.")


def _dates(start: date | None, end: date | None, field: str = "endDate") -> None:
    if start and end and end < start:
        raise invalid("The end date cannot be before the start date.", field)


def _ids(values: list[int]) -> str:
    return json.dumps(sorted(set(values)))


def summary(db: Db, ctx: RequestContext) -> dict[str, Any]:
    return benefits_repo.summary(db, ctx.company_id, ctx.user_id)


# ---------------------------------------------------------------- plan years

def list_plan_years(db: Db, ctx: RequestContext, search: str | None, status: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_plan_years(db, ctx.company_id, ctx.user_id, search, status, page, page_size)


def get_plan_year(db: Db, ctx: RequestContext, year_id: int) -> dict[str, Any]:
    return benefits_repo.get_plan_year(db, ctx.company_id, ctx.user_id, year_id)


def save_plan_year(db: Db, ctx: RequestContext, year_id: int | None, body: PlanYearIn,
                   row_version: bytes | None) -> dict[str, Any]:
    _company_wide(ctx)
    if body.end_date <= body.start_date:
        raise invalid("The end date must be after the start date.", "endDate")
    if body.new_hire_start == "waiting_period" and not body.waiting_period_days:
        raise invalid("Enter the waiting period in days.", "waitingPeriodDays")
    fields = body.model_dump(by_alias=False, exclude={"plan_ids", "row_version"})
    return benefits_repo.save_plan_year(db, ctx.company_id, ctx.user_id, year_id, fields, _ids(body.plan_ids),
                                        row_version)


def delete_plan_year(db: Db, ctx: RequestContext, year_id: int, row_version: bytes) -> None:
    _company_wide(ctx)
    benefits_repo.delete_plan_year(db, ctx.company_id, ctx.user_id, year_id, row_version)


# ---------------------------------------------------------------- benefit plans

def list_plans(db: Db, ctx: RequestContext, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_plans(db, ctx.company_id, filters, page, page_size)


def get_plan(db: Db, ctx: RequestContext, plan_id: int) -> dict[str, Any]:
    return benefits_repo.get_plan(db, ctx.company_id, plan_id)


def save_plan(db: Db, ctx: RequestContext, plan_id: int | None, body: BenefitPlanIn,
              row_version: bytes | None) -> dict[str, Any]:
    _company_wide(ctx)
    _dates(body.start_date, body.end_date)
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return benefits_repo.save_plan(db, ctx.company_id, ctx.user_id, plan_id, fields, row_version)


def duplicate_plan(db: Db, ctx: RequestContext, plan_id: int) -> dict[str, Any]:
    _company_wide(ctx)
    return benefits_repo.duplicate_plan(db, ctx.company_id, ctx.user_id, plan_id)


def delete_plan(db: Db, ctx: RequestContext, plan_id: int, row_version: bytes) -> None:
    _company_wide(ctx)
    benefits_repo.delete_plan(db, ctx.company_id, ctx.user_id, plan_id, row_version)


# ---------------------------------------------------------------- enrollment windows

def list_windows(db: Db, ctx: RequestContext, filters: dict[str, Any], page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_windows(db, ctx.company_id, filters, page, page_size)


def get_window(db: Db, ctx: RequestContext, window_id: int) -> dict[str, Any]:
    return benefits_repo.get_window(db, ctx.company_id, window_id)


def save_window(db: Db, ctx: RequestContext, window_id: int | None, body: WindowIn,
                row_version: bytes | None) -> dict[str, Any]:
    _company_wide(ctx)
    fields = body.model_dump(by_alias=False, exclude={"plan_ids", "employee_ids", "row_version"})
    return benefits_repo.save_window(db, ctx.company_id, ctx.user_id, window_id, fields, _ids(body.plan_ids),
                                     _ids(body.employee_ids), row_version)


def delete_window(db: Db, ctx: RequestContext, window_id: int, row_version: bytes) -> None:
    _company_wide(ctx)
    benefits_repo.delete_window(db, ctx.company_id, ctx.user_id, window_id, row_version)


# ---------------------------------------------------------------- elections and employees

def list_elections(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_elections(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_election(db: Db, ctx: RequestContext, code: str, election_id: int) -> dict[str, Any]:
    return benefits_repo.get_election(db, ctx.company_id, ctx.user_id, code, election_id)


def save_election(db: Db, ctx: RequestContext, code: str, election_id: int | None, body: ElectionIn,
                  row_version: bytes | None) -> dict[str, Any]:
    if body.waive and body.plan_ids:
        raise invalid("A waived election has no plans.", "planIds")
    fields = body.model_dump(by_alias=False, exclude={"plan_ids", "row_version"})
    return benefits_repo.save_election(db, ctx.company_id, ctx.user_id, code, election_id, fields,
                                       _ids(body.plan_ids), row_version)


def decide_election(db: Db, ctx: RequestContext, code: str, election_id: int, decision: str, remarks: str | None,
                    row_version: bytes) -> dict[str, Any]:
    return benefits_repo.decide_election(db, ctx.company_id, ctx.user_id, code, election_id, decision, remarks,
                                         row_version)


def list_employees(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_employees(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


# ---------------------------------------------------------------- files

def list_files(db: Db, ctx: RequestContext, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_files(db, ctx.company_id, filters, page, page_size)


def add_file(db: Db, ctx: RequestContext, plan_id: int, file_id: int) -> dict[str, Any]:
    _company_wide(ctx)
    return benefits_repo.add_file(db, ctx.company_id, ctx.user_id, plan_id, file_id)


def delete_file(db: Db, ctx: RequestContext, attachment_id: int, row_version: bytes) -> None:
    _company_wide(ctx)
    benefits_repo.delete_file(db, ctx.company_id, ctx.user_id, attachment_id, row_version)


# ---------------------------------------------------------------- health benefits and perks

def list_owned(db: Db, ctx: RequestContext, what: str, code: str, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return benefits_repo.list_owned(db, what, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_owned(db: Db, ctx: RequestContext, what: str, code: str, record_id: int) -> dict[str, Any]:
    return benefits_repo.get_owned(db, what, ctx.company_id, ctx.user_id, code, record_id)


def save_health_benefit(db: Db, ctx: RequestContext, code: str, record_id: int | None, body: HealthBenefitIn,
                        row_version: bytes | None) -> dict[str, Any]:
    _dates(body.start_date, body.end_date)
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return benefits_repo.save_owned(db, "health_benefit", ctx.company_id, ctx.user_id, code, record_id, fields,
                                    row_version)


def save_perk(db: Db, ctx: RequestContext, code: str, record_id: int | None, body: PerkIn,
              row_version: bytes | None) -> dict[str, Any]:
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return benefits_repo.save_owned(db, "perk", ctx.company_id, ctx.user_id, code, record_id, fields, row_version)


def delete_owned(db: Db, ctx: RequestContext, what: str, code: str, record_id: int, row_version: bytes) -> None:
    benefits_repo.delete_owned(db, what, ctx.company_id, ctx.user_id, code, record_id, row_version)
