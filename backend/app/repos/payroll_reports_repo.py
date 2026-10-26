"""Payroll reports and dashboard: data access."""
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def employee_accounts(db: Db, company_id: int, actor_user_id: int, code: str, from_date, to_date, search, department_id,
                      page: int, page_size: int) -> tuple[int, list[Row], list[Row]]:
    total, rows, accounts = db.call_sets("pay.usp_report_employee_accounts", company_id=company_id,
                                         actor_user_id=actor_user_id, permission_code=code, from_date=from_date,
                                         to_date=to_date, search=search, department_id=department_id, page=page,
                                         page_size=page_size)
    return total[0]["total"], rows, accounts


def payroll_summary(db: Db, company_id: int, actor_user_id: int, code: str, payroll_id: int) -> tuple[Row, list[Row]]:
    head, items = db.call_sets("pay.usp_report_payroll_summary", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=code, payroll_id=payroll_id)
    return head[0], items


def employee_wise(db: Db, company_id: int, actor_user_id: int, code: str, from_month, to_month, employee_id,
                  department_id, search, page: int, page_size: int) -> tuple[int, list[Row]]:
    total, rows = db.call_sets("pay.usp_report_employee_wise", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=code, from_month=from_month, to_month=to_month, employee_id=employee_id,
                               department_id=department_id, search=search, page=page, page_size=page_size)
    return total[0]["total"], rows


def daily_wages(db: Db, company_id: int, actor_user_id: int, code: str, from_date, to_date, page: int,
                page_size: int) -> tuple[int, list[Row]]:
    total, rows = db.call_sets("pay.usp_report_daily_wages", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=code, from_date=from_date, to_date=to_date, page=page, page_size=page_size)
    return total[0]["total"], rows


def dashboard(db: Db, company_id: int, actor_user_id: int, code: str, year: int, month) -> tuple[Row, list[Row], list[Row]]:
    tiles, months, breakup = db.call_sets("pay.usp_dashboard", company_id=company_id, actor_user_id=actor_user_id,
                                          permission_code=code, year=year, month=month)
    return tiles[0], months, breakup
