"""HTTP shape for payroll reports and the dashboard."""
from app.core.db import Db
from app.core.paging import PageParams
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.payroll_reports import (DailyWagesRowOut, DashboardOut, EmployeeAccountReportOut, EmployeeWiseRowOut,
                                         PayrollSummaryOut)
from app.services import payroll_reports_service as service


def employee_accounts(db: Db, ctx: RequestContext, from_date, to_date, q, department_id, paging: PageParams) -> dict:
    total, rows = service.employee_accounts(db, ctx, from_date, to_date, q, department_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: EmployeeAccountReportOut(**r))


def payroll_summary(db: Db, ctx: RequestContext, payroll_id: int) -> dict:
    return {"data": PayrollSummaryOut(**service.payroll_summary(db, ctx, payroll_id))}


def employee_wise(db: Db, ctx: RequestContext, from_month, to_month, employee_id, department_id, q,
                  paging: PageParams) -> dict:
    total, rows = service.employee_wise(db, ctx, from_month, to_month, employee_id, department_id, q, paging.page,
                                        paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: EmployeeWiseRowOut(**r))


def daily_wages(db: Db, ctx: RequestContext, from_date, to_date, paging: PageParams) -> dict:
    total, rows = service.daily_wages(db, ctx, from_date, to_date, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: DailyWagesRowOut(**r))


def dashboard(db: Db, ctx: RequestContext, year: int | None, month) -> dict:
    return {"data": DashboardOut(**service.dashboard(db, ctx, year, month))}
