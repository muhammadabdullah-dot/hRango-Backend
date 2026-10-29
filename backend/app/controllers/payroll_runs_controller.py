"""HTTP shape for payroll runs, the salary sheet and payslips."""
from typing import Any

from fastapi import Response

from app.controllers.payroll_settings_controller import out
from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.payroll_runs import (AccountBalanceOut, AccountSummaryOut, BankFileFormatOut, CloseEmailFailureOut,
                                      CloseEmailOut, CloseEmailPreviewOut, CloseEmailSummaryOut, DailyWageOut,
                                      DailyWageRowOut, EmployeeCountOut, PayrollClosedOut, PayrollEmployeeOut, PayrollOut,
                                      PayrollPayItemOut, PayslipDetailOut, PayslipHistoryOut, PayslipLineOut, PayslipOut,
                                      RunErrorOut, RunLogOut, SalarySheetOut)
from app.services import payroll_bank_file_service, payroll_mail_service
from app.services import payroll_run_service as service

Row = dict[str, Any]


def _payroll(head: Row, items: list[Row] | None = None) -> PayrollOut:
    return out(PayrollOut, head, pay_items=[PayrollPayItemOut(**i) for i in items or []])


def _daily(head: Row, items: list[Row], rows: list[Row]) -> DailyWageOut:
    return out(DailyWageOut, head, pay_items=[], rows=[DailyWageRowOut(**r) for r in rows])


# --------------------------------------------------------------------------- monthly

def list_payrolls(db: Db, ctx: RequestContext, kind: str, q, status, month, from_date, to_date, time_slot_id,
                  paging: PageParams) -> dict:
    total, rows = service.list_payrolls(db, ctx, kind, q, status, month, from_date, to_date, time_slot_id,
                                        paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _payroll)


def get_payroll(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _payroll(*service.get_payroll(db, ctx, id))}


def save_payroll(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": _payroll(*service.save_payroll(db, ctx, id, body, rv))}


def delete_payroll(db: Db, ctx: RequestContext, id: int, kind: str, row_version: str | None) -> None:
    service.delete_payroll(db, ctx, id, kind, row_version_in(row_version))


def list_employees(db: Db, ctx: RequestContext, id: int, q) -> dict:
    return {"data": [PayrollEmployeeOut(**r) for r in service.list_employees(db, ctx, id, q)]}


def set_employees(db: Db, ctx: RequestContext, id: int, kind: str, body) -> dict:
    return {"data": EmployeeCountOut(**service.set_employees(db, ctx, id, kind, body.employee_ids))}


def add_employees(db: Db, ctx: RequestContext, id: int, kind: str, body) -> dict:
    return {"data": EmployeeCountOut(**service.add_employees(db, ctx, id, kind, body))}


def hold(db: Db, ctx: RequestContext, id: int, on: bool) -> dict:
    return {"data": _payroll(*service.hold_payroll(db, ctx, id, on))}


def run(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": RunLogOut(**service.run(db, ctx, id))}


def close(db: Db, ctx: RequestContext, id: int, kind: str, body) -> dict:
    head, items, email = service.close(db, ctx, id, kind, row_version_in(body.row_version))
    return {"data": out(PayrollClosedOut, head, pay_items=[PayrollPayItemOut(**i) for i in items],
                        email=CloseEmailSummaryOut(**email) if email else None)}


def close_email_preview(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": CloseEmailPreviewOut(**payroll_mail_service.close_email_preview(db, ctx, id))}


def close_email(db: Db, ctx: RequestContext, id: int) -> dict:
    e = payroll_mail_service.close_email(db, ctx, id)
    return {"data": CloseEmailOut(**{**e, "failures": [CloseEmailFailureOut(**f) for f in e["failures"]]})}


def bank_file_formats() -> dict:
    return {"data": [BankFileFormatOut(**f) for f in payroll_bank_file_service.formats()]}


def bank_file(db: Db, ctx: RequestContext, id: int, kind: str, disbursement_bank_id: int | None, fmt: str | None) -> Response:
    content, media, name = payroll_bank_file_service.bank_file(db, ctx, id, kind, disbursement_bank_id, fmt)
    return Response(content=content, media_type=media, headers={"Content-Disposition": f'attachment; filename="{name}"'})


def history(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": [RunLogOut(**r) for r in service.history(db, ctx, id)]}


def errors(db: Db, ctx: RequestContext, id: int, run_log_id: int | None) -> dict:
    return {"data": [RunErrorOut(**r) for r in service.errors(db, ctx, id, run_log_id)]}


# --------------------------------------------------------------------------- daily wages

def create_daily_wage(db: Db, ctx: RequestContext, body) -> dict:
    id = service.create_daily_wage(db, ctx, body)
    return {"data": _daily(*service.get_daily_wage(db, ctx, id))}


def get_daily_wage(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _daily(*service.get_daily_wage(db, ctx, id))}


def edit_daily_wage(db: Db, ctx: RequestContext, id: int, body) -> dict:
    return {"data": _daily(*service.edit_daily_wage(db, ctx, id, body, row_version_in(body.row_version)))}


def process_daily_wage(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": RunLogOut(**service.process_daily_wage(db, ctx, id))}


def daily_wage_vouchers(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": {"created": service.daily_wage_vouchers(db, ctx, id)}}


# --------------------------------------------------------------------------- salary sheet and payslips

def salary_sheet(db: Db, ctx: RequestContext, payroll_id, month) -> dict:
    return {"data": SalarySheetOut(**service.salary_sheet(db, ctx, payroll_id, month))}


def _detail(head: Row, lines: list[Row], display: dict) -> PayslipDetailOut:
    return out(PayslipDetailOut, head, lines=[PayslipLineOut(**l) for l in lines], display=display)


def list_payslips(db: Db, ctx: RequestContext, filters: dict, paging: PageParams) -> dict:
    total, rows = service.list_payslips(db, ctx, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(PayslipOut, r))


def get_payslip(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _detail(*service.get_payslip(db, ctx, id))}


def edit_payslip(db: Db, ctx: RequestContext, id: int, body) -> dict:
    return {"data": _detail(*service.edit_payslip(db, ctx, id, body, row_version_in(body.row_version)))}


def payslip_action(db: Db, ctx: RequestContext, id: int, action: str) -> dict:
    if action == "recalculate":
        service.recalculate(db, ctx, [id])
    else:
        service.set_status(db, ctx, [id], action)
    return get_payslip(db, ctx, id)


def payslips_bulk(db: Db, ctx: RequestContext, ids: list[int], action: str) -> dict:
    if action == "recalculate":
        changed, problems = service.recalculate(db, ctx, ids)
        return {"data": {"changed": changed, "errors": problems}}
    return {"data": {"changed": service.set_status(db, ctx, ids, action), "errors": []}}


def payslip_history(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": [PayslipHistoryOut(**r) for r in service.history_of_payslip(db, ctx, id)]}


def account_summary(db: Db, ctx: RequestContext, employee_id: int | None) -> dict:
    head, accounts = service.account_summary(db, ctx, employee_id)
    return {"data": AccountSummaryOut(**head, accounts=[AccountBalanceOut(**a) for a in accounts])}
