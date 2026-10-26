"""HTTP shape for benefits screens: envelopes, row versions as text, id lists, rows to response models."""
from typing import Any, TypeVar

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.benefits import (BenefitEmployeeOut, BenefitFileOut, BenefitPlanIn, BenefitPlanOut, DecisionIn,
                                  ElectionIn, ElectionOut, HealthBenefitIn, HealthBenefitOut, PerkIn, PerkOut,
                                  PlanYearIn, PlanYearOut, SummaryOut, WindowIn, WindowOut)
from app.schemas.common import ApiModel, paginated
from app.schemas.files import FileRef
from app.services import benefits_service as svc

M = TypeVar("M", bound=ApiModel)
# Columns the procedures return as "1,2,3" (STRING_AGG) and the API sends as lists.
_LISTS = ("plan_ids", "employee_ids", "plan_year_ids", "missing")


def _to(model: type[M], files: dict[str, tuple[str, str]] | None = None):
    """Row to model. `files` maps an output field to the row's (file id, file name) columns; with a company id
    the field becomes a FileRef with a signed download link."""
    def convert(row: dict[str, Any], company_id: int | None = None) -> M:
        row = dict(row)
        if "row_version" in row:
            row["row_version"] = row_version_out(row["row_version"])
        for key in _LISTS:
            if key in row:
                row[key] = [v for v in (row[key] or "").split(",") if v]
        for field, (id_key, name_key) in (files or {}).items():
            file_id = row.get(id_key)
            row[field] = None
            if file_id and company_id is not None:
                row[field] = FileRef(id=str(file_id), name=row.get(name_key), url=file_url(file_id, company_id))
        return model(**row)
    return convert


_year, _plan, _window = _to(PlanYearOut), _to(BenefitPlanOut), _to(WindowOut)
_election, _employee = _to(ElectionOut), _to(BenefitEmployeeOut)
_file = _to(BenefitFileOut, {"file": ("file_id", "file_name")})
_health = _to(HealthBenefitOut, {"document_file": ("document_file_id", "document_file_name")})
_perk = _to(PerkOut)


def _rv(record_id: int | None, text: str | None) -> bytes | None:
    return row_version_in(text) if record_id is not None else None


def _page(result: tuple[int, list[dict[str, Any]]], paging: PageParams, convert) -> dict:
    total, rows = result
    return paginated(rows, total, paging.page, paging.page_size, convert)


def summary(db: Db, ctx: RequestContext) -> dict:
    return {"data": SummaryOut(**svc.summary(db, ctx))}


# ---------------------------------------------------------------- plan years

def list_plan_years(db: Db, ctx: RequestContext, q: str | None, status: str | None, paging: PageParams) -> dict:
    return _page(svc.list_plan_years(db, ctx, q, status, paging.page, paging.page_size), paging, _year)


def get_plan_year(db: Db, ctx: RequestContext, year_id: int) -> dict:
    return {"data": _year(svc.get_plan_year(db, ctx, year_id))}


def save_plan_year(db: Db, ctx: RequestContext, year_id: int | None, body: PlanYearIn) -> dict:
    return {"data": _year(svc.save_plan_year(db, ctx, year_id, body, _rv(year_id, body.row_version)))}


def delete_plan_year(db: Db, ctx: RequestContext, year_id: int, row_version: str | None) -> None:
    svc.delete_plan_year(db, ctx, year_id, row_version_in(row_version))


# ---------------------------------------------------------------- benefit plans

def list_plans(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    return _page(svc.list_plans(db, ctx, filters, paging.page, paging.page_size), paging, _plan)


def get_plan(db: Db, ctx: RequestContext, plan_id: int) -> dict:
    return {"data": _plan(svc.get_plan(db, ctx, plan_id))}


def save_plan(db: Db, ctx: RequestContext, plan_id: int | None, body: BenefitPlanIn) -> dict:
    return {"data": _plan(svc.save_plan(db, ctx, plan_id, body, _rv(plan_id, body.row_version)))}


def duplicate_plan(db: Db, ctx: RequestContext, plan_id: int) -> dict:
    return {"data": _plan(svc.duplicate_plan(db, ctx, plan_id))}


def delete_plan(db: Db, ctx: RequestContext, plan_id: int, row_version: str | None) -> None:
    svc.delete_plan(db, ctx, plan_id, row_version_in(row_version))


# ---------------------------------------------------------------- enrollment windows

def list_windows(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    return _page(svc.list_windows(db, ctx, filters, paging.page, paging.page_size), paging, _window)


def get_window(db: Db, ctx: RequestContext, window_id: int) -> dict:
    return {"data": _window(svc.get_window(db, ctx, window_id))}


def save_window(db: Db, ctx: RequestContext, window_id: int | None, body: WindowIn) -> dict:
    return {"data": _window(svc.save_window(db, ctx, window_id, body, _rv(window_id, body.row_version)))}


def delete_window(db: Db, ctx: RequestContext, window_id: int, row_version: str | None) -> None:
    svc.delete_window(db, ctx, window_id, row_version_in(row_version))


# ---------------------------------------------------------------- elections and employees

def list_elections(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    return _page(svc.list_elections(db, ctx, code, filters, paging.page, paging.page_size), paging, _election)


def get_election(db: Db, ctx: RequestContext, code: str, election_id: int) -> dict:
    return {"data": _election(svc.get_election(db, ctx, code, election_id))}


def save_election(db: Db, ctx: RequestContext, code: str, election_id: int | None, body: ElectionIn) -> dict:
    row = svc.save_election(db, ctx, code, election_id, body, _rv(election_id, body.row_version))
    return {"data": _election(row)}


def decide_election(db: Db, ctx: RequestContext, code: str, election_id: int, decision: str, body: DecisionIn) -> dict:
    row = svc.decide_election(db, ctx, code, election_id, decision, body.remarks, row_version_in(body.row_version))
    return {"data": _election(row)}


def list_employees(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    return _page(svc.list_employees(db, ctx, code, filters, paging.page, paging.page_size), paging, _employee)


# ---------------------------------------------------------------- files

def list_files(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    return _page(svc.list_files(db, ctx, filters, paging.page, paging.page_size), paging,
                 lambda r: _file(r, ctx.company_id))


def add_file(db: Db, ctx: RequestContext, plan_id: int, file_id: int) -> dict:
    return {"data": _file(svc.add_file(db, ctx, plan_id, file_id), ctx.company_id)}


def delete_file(db: Db, ctx: RequestContext, attachment_id: int, row_version: str | None) -> None:
    svc.delete_file(db, ctx, attachment_id, row_version_in(row_version))


# ---------------------------------------------------------------- health benefits and perks

_OUT = {"health_benefit": _health, "perk": _perk}


def list_owned(db: Db, ctx: RequestContext, what: str, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    return _page(svc.list_owned(db, ctx, what, code, filters, paging.page, paging.page_size), paging,
                 lambda r: _OUT[what](r, ctx.company_id))


def get_owned(db: Db, ctx: RequestContext, what: str, code: str, record_id: int) -> dict:
    return {"data": _OUT[what](svc.get_owned(db, ctx, what, code, record_id), ctx.company_id)}


def save_health_benefit(db: Db, ctx: RequestContext, code: str, record_id: int | None, body: HealthBenefitIn) -> dict:
    row = svc.save_health_benefit(db, ctx, code, record_id, body, _rv(record_id, body.row_version))
    return {"data": _health(row, ctx.company_id)}


def save_perk(db: Db, ctx: RequestContext, code: str, record_id: int | None, body: PerkIn) -> dict:
    return {"data": _perk(svc.save_perk(db, ctx, code, record_id, body, _rv(record_id, body.row_version)))}


def delete_owned(db: Db, ctx: RequestContext, what: str, code: str, record_id: int, row_version: str | None) -> None:
    svc.delete_owned(db, ctx, what, code, record_id, row_version_in(row_version))
