"""HTTP shape for vouchers, final settlement, balances, salary revision and leave encashment."""
from app.controllers.payroll_runs_controller import _detail
from app.controllers.payroll_settings_controller import out
from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.payroll_records import (AccountEntryOut, CurrentSalaryOut, FinalSettlementOut, LeaveEncashmentOut,
                                         LeaveEncashmentRowOut, OpeningBalanceEmployeeOut, OpeningBalanceOut,
                                         OpeningBalanceSummaryOut, SalaryRevisionOut, StatementRowOut, VoucherOut)
from app.services import payroll_records_service as service


def _rv(body, id):
    return row_version_in(body.row_version) if id is not None else None


# --------------------------------------------------------------------------- vouchers

def list_vouchers(db: Db, ctx: RequestContext, f: dict, paging: PageParams) -> dict:
    total, rows = service.list_vouchers(db, ctx, f, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(VoucherOut, r, ctx.company_id))


def get_voucher(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(VoucherOut, service.get_voucher(db, ctx, id), ctx.company_id)}


def save_voucher(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    return {"data": out(VoucherOut, service.save_voucher(db, ctx, id, body, _rv(body, id)), ctx.company_id)}


def delete_voucher(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_voucher(db, ctx, id, row_version_in(row_version))


def decide_voucher(db: Db, ctx: RequestContext, id: int, action: str, body) -> dict:
    return {"data": out(VoucherOut, service.decide_voucher(db, ctx, id, action, body.remarks,
                                                           row_version_in(body.row_version)), ctx.company_id)}


# --------------------------------------------------------------------------- final settlement

def list_final_settlements(db: Db, ctx: RequestContext, f: dict, paging: PageParams) -> dict:
    total, rows = service.list_final_settlements(db, ctx, f, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(FinalSettlementOut, r, ctx.company_id))


def get_final_settlement(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(FinalSettlementOut, service.get_final_settlement(db, ctx, id), ctx.company_id)}


def recalculate_final_settlement(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(FinalSettlementOut, service.recalculate_final_settlement(db, ctx, id), ctx.company_id)}


def close_final_settlement(db: Db, ctx: RequestContext, id: int, body) -> dict:
    row = service.close_final_settlement(db, ctx, id, row_version_in(body.row_version), body.file_id)
    return {"data": out(FinalSettlementOut, row, ctx.company_id)}


def final_settlement_payslip(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _detail(*service.final_settlement_payslip(db, ctx, id))}


# --------------------------------------------------------------------------- opening balances

def list_opening_balances(db: Db, ctx: RequestContext, f: dict, paging: PageParams) -> dict:
    total, rows = service.list_opening_balances(db, ctx, f, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: OpeningBalanceSummaryOut(**r))


def opening_balances_of(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    head, rows = service.opening_balances_of(db, ctx, employee_id)
    return {"data": OpeningBalanceEmployeeOut(**head, entries=[out(OpeningBalanceOut, r) for r in rows])}


def get_opening_balance(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(OpeningBalanceOut, service.get_opening_balance(db, ctx, id))}


def save_opening_balance(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    return {"data": out(OpeningBalanceOut, service.save_opening_balance(db, ctx, id, body, _rv(body, id)))}


def delete_opening_balance(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_opening_balance(db, ctx, id, row_version_in(row_version))


def import_opening_balances(db: Db, ctx: RequestContext, body) -> dict:
    created, errors = service.import_opening_balances(db, ctx, body)
    return {"data": {"created": created, "errors": errors}}


# --------------------------------------------------------------------------- employee accounts

def list_account_entries(db: Db, ctx: RequestContext, f: dict, paging: PageParams) -> dict:
    total, rows = service.list_account_entries(db, ctx, f, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(AccountEntryOut, r))


def get_account_entry(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(AccountEntryOut, service.get_account_entry(db, ctx, id))}


def save_account_entry(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    return {"data": out(AccountEntryOut, service.save_account_entry(db, ctx, id, body, _rv(body, id)))}


def delete_account_entry(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_account_entry(db, ctx, id, row_version_in(row_version))


def import_account_entries(db: Db, ctx: RequestContext, body) -> dict:
    created, errors = service.import_account_entries(db, ctx, body)
    return {"data": {"created": created, "errors": errors}}


def account_statement(db: Db, ctx: RequestContext, employee_id, account_type_id, from_month, to_month,
                      paging: PageParams) -> dict:
    total, rows = service.account_statement(db, ctx, employee_id, account_type_id, from_month, to_month, paging.page,
                                            paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: StatementRowOut(**r))


# --------------------------------------------------------------------------- salary revision

def list_revisions(db: Db, ctx: RequestContext, f: dict, paging: PageParams) -> dict:
    total, rows = service.list_revisions(db, ctx, f, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(SalaryRevisionOut, r))


def get_revision(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(SalaryRevisionOut, service.get_revision(db, ctx, id))}


def current_salary(db: Db, ctx: RequestContext, employee_id: int, as_of) -> dict:
    return {"data": CurrentSalaryOut(**service.current_salary(db, ctx, employee_id, as_of))}


def save_revision(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    return {"data": out(SalaryRevisionOut, service.save_revision(db, ctx, id, body, _rv(body, id)))}


def delete_revision(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_revision(db, ctx, id, row_version_in(row_version))


def import_revisions(db: Db, ctx: RequestContext, body) -> dict:
    created, errors = service.import_revisions(db, ctx, body)
    return {"data": {"created": created, "errors": errors}}


# --------------------------------------------------------------------------- leave encashment

def _encashment(head, rows) -> LeaveEncashmentOut:
    return out(LeaveEncashmentOut, head, employees=[LeaveEncashmentRowOut(**r) for r in rows])


def list_encashments(db: Db, ctx: RequestContext, f: dict, paging: PageParams) -> dict:
    total, rows = service.list_encashments(db, ctx, f, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(LeaveEncashmentRowOut, r))


def get_encashment(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _encashment(*service.get_encashment(db, ctx, id))}


def save_encashment(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    return {"data": _encashment(*service.save_encashment(db, ctx, id, body, _rv(body, id)))}


def delete_encashment(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_encashment(db, ctx, id, row_version_in(row_version))
