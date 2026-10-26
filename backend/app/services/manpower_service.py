"""Manpower planning rules. Checks that need the data (plan years, bands, locks, approvals, scope) live in
the mp procedures; this layer checks what it can without the database and shapes the JSON the
procedures read. `code` is the permission the endpoint required; scoped procedures filter with it."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, invalid
from app.middlewares.auth import RequestContext
from app.repos import manpower_repo
from app.schemas.manpower import BudgetIn, PlanIn, PositionImportRow, PositionIn


def _dates(start: date | None, end: date | None, field: str = "endDate") -> None:
    if start and end and end < start:
        raise invalid("The end date cannot be before the start date.", field)


def _json(value: Any) -> str:
    return json.dumps(value, default=str)


# ---------------------------------------------------------------- budget durations

def list_durations(db: Db, ctx: RequestContext, search: str | None, is_current: bool | None, page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return manpower_repo.list_durations(db, ctx.company_id, search, is_current, page, page_size)


def get_duration(db: Db, ctx: RequestContext, duration_id: int) -> dict[str, Any]:
    return manpower_repo.get_duration(db, ctx.company_id, duration_id)


def save_duration(db: Db, ctx: RequestContext, duration_id: int | None, name: str, start_date: date, end_date: date,
                  is_current: bool, row_version: bytes | None) -> dict[str, Any]:
    _dates(start_date, end_date)
    return manpower_repo.save_duration(db, ctx.company_id, ctx.user_id, duration_id, name, start_date, end_date,
                                       is_current, row_version)


def delete_duration(db: Db, ctx: RequestContext, duration_id: int, row_version: bytes) -> None:
    manpower_repo.delete_duration(db, ctx.company_id, ctx.user_id, duration_id, row_version)


# ---------------------------------------------------------------- position titles and positions

def list_position_titles(db: Db, ctx: RequestContext, search: str | None, page: int,
                         page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return manpower_repo.list_position_titles(db, ctx.company_id, search, page, page_size)


def list_positions(db: Db, ctx: RequestContext, filters: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return manpower_repo.list_positions(db, ctx.company_id, filters, page, page_size)


def get_position(db: Db, ctx: RequestContext, position_id: int) -> dict[str, Any]:
    return manpower_repo.get_position(db, ctx.company_id, position_id)


def save_position(db: Db, ctx: RequestContext, position_id: int | None, body: PositionIn,
                  row_version: bytes | None) -> dict[str, Any]:
    if body.max_salary < body.min_salary:
        raise invalid("Max salary cannot be below the min salary.", "maxSalary")
    if position_id is not None and body.reports_to_id == position_id:
        raise invalid("A position cannot report to itself.", "reportsToId")
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return manpower_repo.save_position(db, ctx.company_id, ctx.user_id, position_id, fields, row_version)


def delete_position(db: Db, ctx: RequestContext, position_id: int, row_version: bytes) -> None:
    manpower_repo.delete_position(db, ctx.company_id, ctx.user_id, position_id, row_version)


def import_positions(db: Db, ctx: RequestContext, rows: list[PositionImportRow]) -> tuple[int, list[dict[str, Any]]]:
    payload = [r.model_dump(by_alias=True) for r in rows]
    return manpower_repo.import_positions(db, ctx.company_id, ctx.user_id, _json(payload))


def list_salary_ranges(db: Db, ctx: RequestContext, position_id: int) -> list[dict[str, Any]]:
    return manpower_repo.list_salary_ranges(db, ctx.company_id, position_id)


def save_salary_range(db: Db, ctx: RequestContext, position_id: int, effective_date: date, min_salary, max_salary
                      ) -> list[dict[str, Any]]:
    if max_salary < min_salary:
        raise invalid("Max salary cannot be below the min salary.", "maxSalary")
    return manpower_repo.save_salary_range(db, ctx.company_id, ctx.user_id, position_id, effective_date, min_salary,
                                           max_salary)


# ---------------------------------------------------------------- plans

def list_plans(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return manpower_repo.list_plans(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_plan(db: Db, ctx: RequestContext, code: str, plan_id: int) -> list[list[dict[str, Any]]]:
    return manpower_repo.get_plan(db, ctx.company_id, ctx.user_id, code, plan_id)


def save_plan(db: Db, ctx: RequestContext, code: str, plan_id: int | None, body: PlanIn,
              row_version: bytes | None) -> list[list[dict[str, Any]]]:
    if not body.lines:
        raise AppError(422, "VALIDATION_FAILED", "Add at least one new or existing position.",
                       {"lines": "Add at least one new or existing position."})
    for i, line in enumerate(body.lines):
        if line.start_date and line.end_date and line.end_date < line.start_date:
            raise invalid("The end cannot be before the start.", f"lines[{i}].endDate")
    fields = body.model_dump(by_alias=False, exclude={"lines", "file_ids", "row_version"})
    fields["file_ids"] = _json(body.file_ids) if body.file_ids is not None else None
    lines = [line.model_dump(by_alias=True, exclude_none=True) for line in body.lines]
    return manpower_repo.save_plan(db, ctx.company_id, ctx.user_id, code, plan_id, fields, _json(lines), row_version)


def delete_plan(db: Db, ctx: RequestContext, code: str, plan_id: int, row_version: bytes) -> None:
    manpower_repo.delete_plan(db, ctx.company_id, ctx.user_id, code, plan_id, row_version)


# ---------------------------------------------------------------- e-budgets

def list_budgets(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return manpower_repo.list_budgets(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_budget(db: Db, ctx: RequestContext, code: str, budget_id: int) -> dict[str, Any]:
    return manpower_repo.get_budget(db, ctx.company_id, ctx.user_id, code, budget_id)


def save_budget(db: Db, ctx: RequestContext, code: str, budget_id: int | None, body: BudgetIn,
                row_version: bytes | None) -> dict[str, Any]:
    _dates(body.start_date, body.end_date)
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return manpower_repo.save_budget(db, ctx.company_id, ctx.user_id, code, budget_id, fields, row_version)


def delete_budget(db: Db, ctx: RequestContext, code: str, budget_id: int, row_version: bytes) -> None:
    manpower_repo.delete_budget(db, ctx.company_id, ctx.user_id, code, budget_id, row_version)


def decide_budget(db: Db, ctx: RequestContext, code: str, budget_id: int, decision: str, remarks: str | None,
                  row_version: bytes) -> dict[str, Any]:
    return manpower_repo.decide_budget(db, ctx.company_id, ctx.user_id, code, budget_id, decision, remarks,
                                       row_version)


# ---------------------------------------------------------------- open positions

def list_open_positions(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                        page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return manpower_repo.list_open_positions(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_open_position(db: Db, ctx: RequestContext, code: str, open_id: int) -> dict[str, Any]:
    return manpower_repo.get_open_position(db, ctx.company_id, ctx.user_id, code, open_id)


def save_open_position(db: Db, ctx: RequestContext, code: str, open_id: int, total_positions: int,
                       end_date: date | None, jd_file_id: int | None, row_version: bytes) -> dict[str, Any]:
    return manpower_repo.save_open_position(db, ctx.company_id, ctx.user_id, code, open_id, total_positions, end_date,
                                            jd_file_id, row_version)


def set_open_position_status(db: Db, ctx: RequestContext, code: str, open_id: int, status: str,
                             row_version: bytes) -> dict[str, Any]:
    return manpower_repo.set_open_position_status(db, ctx.company_id, ctx.user_id, code, open_id, status, row_version)


def open_position_jd(db: Db, ctx: RequestContext, code: str, open_id: int) -> dict[str, Any]:
    return manpower_repo.open_position_jd(db, ctx.company_id, ctx.user_id, code, open_id)
