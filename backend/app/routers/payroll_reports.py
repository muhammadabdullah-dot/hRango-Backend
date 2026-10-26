"""Payroll Reports and the Payroll Dashboard."""
from datetime import date

from fastapi import APIRouter, Depends, Query

from app.controllers import payroll_reports_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.payroll_reports import (DailyWagesRowOut, DashboardOut, EmployeeAccountReportOut, EmployeeWiseRowOut,
                                         PayrollSummaryOut)

router = APIRouter()


@router.get("/reports/employee-accounts", response_model=Paginated[EmployeeAccountReportOut])
def employee_account_report(from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                            q: str | None = None, department_id: int | None = Query(None, alias="departmentId"),
                            paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("payroll.reports.view"))):
    return c.employee_accounts(db, ctx, from_date, to_date, q, department_id, paging)


@router.get("/reports/payroll-summary/{payroll_id}", response_model=Item[PayrollSummaryOut])
def payroll_summary(payroll_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.reports.view"))):
    return c.payroll_summary(db, ctx, payroll_id)


@router.get("/reports/employee-wise", response_model=Paginated[EmployeeWiseRowOut])
def employee_wise_report(from_month: date | None = Query(None, alias="from"), to_month: date | None = Query(None, alias="to"),
                         employee_id: int | None = Query(None, alias="employeeId"),
                         department_id: int | None = Query(None, alias="departmentId"), q: str | None = None,
                         paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.reports.view"))):
    return c.employee_wise(db, ctx, from_month, to_month, employee_id, department_id, q, paging)


@router.get("/reports/daily-wages", response_model=Paginated[DailyWagesRowOut])
def daily_wages_report(from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                       paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("payroll.reports.view"))):
    return c.daily_wages(db, ctx, from_date, to_date, paging)


@router.get("/dashboard", response_model=Item[DashboardOut])
def dashboard(year: int | None = Query(None, ge=2000, le=2100), month: date | None = None, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("payroll.dashboard.view"))):
    return c.dashboard(db, ctx, year, month)
