"""Payroll reports (Employee Account Report, Payroll Summary, Employee-wise, Daily Wages Summary) and the
payroll dashboard. Figures cover only the employees the caller may see through the report's permission."""
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import payroll_reports_repo as repo

Row = dict[str, Any]
REPORTS, DASHBOARD = "payroll.reports.view", "payroll.dashboard.view"


def _period(from_date: date | None, to_date: date | None) -> tuple[date, date]:
    today = date.today()
    from_date = from_date or date(today.year, 1, 1)
    to_date = to_date or date(today.year, 12, 31)
    if to_date < from_date:
        raise AppError(422, "VALIDATION_FAILED", "The end is before the start.", {"to": "The end is before the start."})
    return from_date, to_date


def employee_accounts(db: Db, ctx: RequestContext, from_date, to_date, search, department_id, page: int, page_size: int):
    f, t = _period(from_date, to_date)
    total, rows, accounts = repo.employee_accounts(db, ctx.company_id, ctx.user_id, REPORTS, f, t, search, department_id,
                                                   page, page_size)
    by_emp: dict[int, list[Row]] = {}
    for a in accounts:
        by_emp.setdefault(a["employee_id"], []).append(a)
    return total, [{**r, "accounts": by_emp.get(r["employee_id"], [])} for r in rows]


def payroll_summary(db: Db, ctx: RequestContext, payroll_id: int) -> Row:
    head, items = repo.payroll_summary(db, ctx.company_id, ctx.user_id, REPORTS, payroll_id)
    return {**head, "pay_items": items}


def employee_wise(db: Db, ctx: RequestContext, from_month, to_month, employee_id, department_id, search, page: int,
                  page_size: int):
    f, t = _period(from_month, to_month)
    return repo.employee_wise(db, ctx.company_id, ctx.user_id, REPORTS, f, t, employee_id, department_id, search, page,
                              page_size)


def daily_wages(db: Db, ctx: RequestContext, from_date, to_date, page: int, page_size: int):
    f, t = _period(from_date, to_date)
    return repo.daily_wages(db, ctx.company_id, ctx.user_id, REPORTS, f, t, page, page_size)


def dashboard(db: Db, ctx: RequestContext, year: int | None, month: date | None) -> Row:
    year = year or date.today().year
    tiles, months, breakup = repo.dashboard(db, ctx.company_id, ctx.user_id, DASHBOARD, year, month)
    tiles = {k: (v or 0) for k, v in tiles.items()}
    return {"year": year, "breakup_month": breakup[0]["month"] if breakup else None, "tiles": tiles,
            "salary_statistics": months, "salary_breakup": breakup}
