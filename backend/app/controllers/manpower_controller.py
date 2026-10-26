"""HTTP shape for manpower screens: envelopes, row versions as text, rows to response models."""
from typing import Any, TypeVar

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import ApiModel, paginated
from app.schemas.files import FileRef
from app.schemas.manpower import (BudgetDurationIn, BudgetDurationOut, BudgetIn, BudgetOut, DecisionIn, FileOut,
                                  ImportErrorOut, ImportResultOut, OpenPositionIn, OpenPositionOut, PlanDetailOut,
                                  PlanFileOut, PlanIn, PlanLineOut, PlanOut, PositionImportIn, PositionIn, PositionOut,
                                  PositionTitleOut, RowVersionIn, SalaryRangeIn, SalaryRangeOut)
from app.services import manpower_service as svc

M = TypeVar("M", bound=ApiModel)


def _to(model: type[M]):
    def convert(row: dict[str, Any]) -> M:
        if "row_version" in row:
            row = {**row, "row_version": row_version_out(row["row_version"])}
        return model(**row)
    return convert


_duration, _title, _position = _to(BudgetDurationOut), _to(PositionTitleOut), _to(PositionOut)
_range, _plan, _line = _to(SalaryRangeOut), _to(PlanOut), _to(PlanLineOut)
_budget = _to(BudgetOut)


def _open(row: dict[str, Any], company_id: int) -> OpenPositionOut:
    jd = row.get("jd_file_id")
    return OpenPositionOut(**{**row, "row_version": row_version_out(row["row_version"])},
                           jd_file=FileRef(id=str(jd), name=row.get("jd_file_name"), url=file_url(jd, company_id))
                           if jd else None)


def _plan_detail(sets: list[list[dict[str, Any]]], company_id: int) -> PlanDetailOut:
    head, lines, budgets = sets[0][0], sets[1], sets[2]
    files = sets[3] if len(sets) > 3 else []
    return PlanDetailOut(**{**head, "row_version": row_version_out(head["row_version"]),
                            "lines": [_line(r) for r in lines], "budgets": [_budget(r) for r in budgets],
                            "files": [PlanFileOut(**r, url=file_url(r["id"], company_id)) for r in files]})


# ---------------------------------------------------------------- budget durations

def list_durations(db: Db, ctx: RequestContext, q: str | None, is_current: bool | None, paging: PageParams) -> dict:
    total, rows = svc.list_durations(db, ctx, q, is_current, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _duration)


def get_duration(db: Db, ctx: RequestContext, duration_id: int) -> dict:
    return {"data": _duration(svc.get_duration(db, ctx, duration_id))}


def save_duration(db: Db, ctx: RequestContext, duration_id: int | None, body: BudgetDurationIn) -> dict:
    rv = row_version_in(body.row_version) if duration_id is not None else None
    return {"data": _duration(svc.save_duration(db, ctx, duration_id, body.name, body.start_date, body.end_date,
                                                body.is_current, rv))}


def delete_duration(db: Db, ctx: RequestContext, duration_id: int, row_version: str | None) -> None:
    svc.delete_duration(db, ctx, duration_id, row_version_in(row_version))


# ---------------------------------------------------------------- position titles and positions

def list_position_titles(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    total, rows = svc.list_position_titles(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _title)


def list_positions(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_positions(db, ctx, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _position)


def get_position(db: Db, ctx: RequestContext, position_id: int) -> dict:
    return {"data": _position(svc.get_position(db, ctx, position_id))}


def save_position(db: Db, ctx: RequestContext, position_id: int | None, body: PositionIn) -> dict:
    rv = row_version_in(body.row_version) if position_id is not None else None
    return {"data": _position(svc.save_position(db, ctx, position_id, body, rv))}


def delete_position(db: Db, ctx: RequestContext, position_id: int, row_version: str | None) -> None:
    svc.delete_position(db, ctx, position_id, row_version_in(row_version))


def import_positions(db: Db, ctx: RequestContext, body: PositionImportIn) -> dict:
    created, errors = svc.import_positions(db, ctx, body.rows)
    return {"data": ImportResultOut(created=created, errors=[ImportErrorOut(**e) for e in errors])}


def list_salary_ranges(db: Db, ctx: RequestContext, position_id: int) -> dict:
    return {"data": [_range(r) for r in svc.list_salary_ranges(db, ctx, position_id)]}


def save_salary_range(db: Db, ctx: RequestContext, position_id: int, body: SalaryRangeIn) -> dict:
    rows = svc.save_salary_range(db, ctx, position_id, body.effective_date, body.min_salary, body.max_salary)
    return {"data": [_range(r) for r in rows]}


# ---------------------------------------------------------------- plans

def list_plans(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_plans(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _plan)


def get_plan(db: Db, ctx: RequestContext, code: str, plan_id: int) -> dict:
    return {"data": _plan_detail(svc.get_plan(db, ctx, code, plan_id), ctx.company_id)}


def save_plan(db: Db, ctx: RequestContext, code: str, plan_id: int | None, body: PlanIn) -> dict:
    rv = row_version_in(body.row_version) if plan_id is not None else None
    return {"data": _plan_detail(svc.save_plan(db, ctx, code, plan_id, body, rv), ctx.company_id)}


def delete_plan(db: Db, ctx: RequestContext, code: str, plan_id: int, row_version: str | None) -> None:
    svc.delete_plan(db, ctx, code, plan_id, row_version_in(row_version))


# ---------------------------------------------------------------- e-budgets

def list_budgets(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_budgets(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _budget)


def get_budget(db: Db, ctx: RequestContext, code: str, budget_id: int) -> dict:
    return {"data": _budget(svc.get_budget(db, ctx, code, budget_id))}


def save_budget(db: Db, ctx: RequestContext, code: str, budget_id: int | None, body: BudgetIn) -> dict:
    rv = row_version_in(body.row_version) if budget_id is not None else None
    return {"data": _budget(svc.save_budget(db, ctx, code, budget_id, body, rv))}


def delete_budget(db: Db, ctx: RequestContext, code: str, budget_id: int, row_version: str | None) -> None:
    svc.delete_budget(db, ctx, code, budget_id, row_version_in(row_version))


def decide_budget(db: Db, ctx: RequestContext, code: str, budget_id: int, decision: str, body: DecisionIn) -> dict:
    row = svc.decide_budget(db, ctx, code, budget_id, decision, body.remarks, row_version_in(body.row_version))
    return {"data": _budget(row)}


# ---------------------------------------------------------------- open positions

def list_open_positions(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_open_positions(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _open(r, ctx.company_id))


def get_open_position(db: Db, ctx: RequestContext, code: str, open_id: int) -> dict:
    return {"data": _open(svc.get_open_position(db, ctx, code, open_id), ctx.company_id)}


def save_open_position(db: Db, ctx: RequestContext, code: str, open_id: int, body: OpenPositionIn) -> dict:
    row = svc.save_open_position(db, ctx, code, open_id, body.total_positions, body.end_date, body.jd_file_id,
                                 row_version_in(body.row_version))
    return {"data": _open(row, ctx.company_id)}


def set_open_position_status(db: Db, ctx: RequestContext, code: str, open_id: int, status: str,
                             body: RowVersionIn) -> dict:
    row = svc.set_open_position_status(db, ctx, code, open_id, status, row_version_in(body.row_version))
    return {"data": _open(row, ctx.company_id)}


def open_position_jd(db: Db, ctx: RequestContext, code: str, open_id: int) -> dict:
    row = svc.open_position_jd(db, ctx, code, open_id)
    return {"data": FileOut(**row, url=file_url(row["id"], ctx.company_id))}
