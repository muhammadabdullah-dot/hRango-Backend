"""Vouchers, Final Settlement, Balances (Opening Balance, Employee Accounts, Statement), Salary Revision and
Leave Encashment."""
from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import payroll_records_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.common import Item, Paginated
from app.schemas.payroll_records import (AccountEntryIn, AccountEntryOut, AccountImportIn, CurrentSalaryOut,
                                         FinalSettlementCloseIn, FinalSettlementOut, ImportResultOut, LeaveEncashmentIn,
                                         LeaveEncashmentOut, LeaveEncashmentPreviewIn, LeaveEncashmentPreviewOut,
                                         LeaveEncashmentRowOut, OpeningBalanceEmployeeOut, OpeningBalanceImportIn,
                                         OpeningBalanceIn, OpeningBalanceOut, OpeningBalanceSummaryOut, SalaryImportIn,
                                         SalaryRevisionEmailOut, SalaryRevisionEmailPreviewOut, SalaryRevisionIn,
                                         SalaryRevisionOut, StatementRowOut, VoucherDecisionIn, VoucherIn, VoucherOut)
from app.schemas.payroll_runs import PayslipDetailOut, RowVersionIn

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED
RV = Query(None, alias="rowVersion")


def gone() -> Response:
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- vouchers

@router.get("/vouchers", response_model=Paginated[VoucherOut])
def list_vouchers(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                  department_id: int | None = Query(None, alias="departmentId"),
                  designation_id: int | None = Query(None, alias="designationId"),
                  voucher_type: str | None = Query(None, alias="type"), status_: str | None = Query(None, alias="status"),
                  voucher_no: str | None = Query(None, alias="voucherCode"),
                  payroll_id: int | None = Query(None, alias="payrollId"),
                  from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                  amount_from: float | None = Query(None, alias="amountFrom"),
                  amount_to: float | None = Query(None, alias="amountTo"),
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.vouchers.view"))):
    f = dict(search=q, employee_id=employee_id, department_id=department_id, designation_id=designation_id,
             voucher_type=voucher_type, status=status_, voucher_no=voucher_no, payroll_id=payroll_id,
             from_date=from_date, to_date=to_date, amount_from=amount_from, amount_to=amount_to)
    return c.list_vouchers(db, ctx, f, paging)


@router.get("/vouchers/{id}", response_model=Item[VoucherOut])
def get_voucher(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.vouchers.view"))):
    return c.get_voucher(db, ctx, id)


@router.post("/vouchers", response_model=Item[VoucherOut], status_code=CREATED)
def create_voucher(body: VoucherIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.vouchers.create"))):
    return c.save_voucher(db, ctx, None, body)


@router.put("/vouchers/{id}", response_model=Item[VoucherOut])
def update_voucher(id: int, body: VoucherIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.vouchers.edit"))):
    return c.save_voucher(db, ctx, id, body)


@router.delete("/vouchers/{id}", status_code=NO_CONTENT)
def delete_voucher(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.vouchers.delete"))):
    c.delete_voucher(db, ctx, id, row_version)
    return gone()


@router.post("/vouchers/{id}/approve", response_model=Item[VoucherOut])
def approve_voucher(id: int, body: VoucherDecisionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.vouchers.approve"))):
    return c.decide_voucher(db, ctx, id, "approve", body)


@router.post("/vouchers/{id}/reject", response_model=Item[VoucherOut])
def reject_voucher(id: int, body: VoucherDecisionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.vouchers.reject"))):
    return c.decide_voucher(db, ctx, id, "reject", body)


@router.post("/vouchers/{id}/verify", response_model=Item[VoucherOut])
def verify_voucher(id: int, body: VoucherDecisionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.vouchers.verify"))):
    return c.decide_voucher(db, ctx, id, "verify", body)


# --------------------------------------------------------------------------- final settlement

@router.get("/final-settlements", response_model=Paginated[FinalSettlementOut])
def list_final_settlements(q: str | None = None, status_: str | None = Query(None, alias="status"),
                           month: date | None = None, branch_id: int | None = Query(None, alias="branchId"),
                           department_id: int | None = Query(None, alias="departmentId"),
                           location_id: int | None = Query(None, alias="locationId"),
                           employee_status: str | None = Query(None, alias="employmentStatus"),
                           paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.final_settlement.view"))):
    f = dict(search=q, status=status_, month=month, branch_id=branch_id, department_id=department_id,
             location_id=location_id, employee_status=employee_status)
    return c.list_final_settlements(db, ctx, f, paging)


@router.get("/final-settlements/{id}", response_model=Item[FinalSettlementOut])
def get_final_settlement(id: int, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.final_settlement.view"))):
    return c.get_final_settlement(db, ctx, id)


@router.get("/final-settlements/{id}/payslip", response_model=Item[PayslipDetailOut])
def final_settlement_payslip(id: int, db: Db = Depends(get_db),
                             ctx: RequestContext = Depends(require("payroll.final_settlement.view"))):
    return c.final_settlement_payslip(db, ctx, id)


@router.post("/final-settlements/{id}/recalculate", response_model=Item[FinalSettlementOut])
def recalculate_final_settlement(id: int, db: Db = Depends(get_db),
                                 ctx: RequestContext = Depends(require("payroll.final_settlement.process"))):
    return c.recalculate_final_settlement(db, ctx, id)


@router.post("/final-settlements/{id}/close", response_model=Item[FinalSettlementOut])
def close_final_settlement(id: int, body: FinalSettlementCloseIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.final_settlement.close"))):
    return c.close_final_settlement(db, ctx, id, body)


# --------------------------------------------------------------------------- opening balances

@router.get("/opening-balances", response_model=Paginated[OpeningBalanceSummaryOut])
def list_opening_balances(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                          department_id: int | None = Query(None, alias="departmentId"), month: date | None = None,
                          net_from: float | None = Query(None, alias="netFrom"),
                          net_to: float | None = Query(None, alias="netTo"),
                          paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("payroll.opening_balances.view"))):
    f = dict(search=q, employee_id=employee_id, department_id=department_id, month=month, net_from=net_from,
             net_to=net_to)
    return c.list_opening_balances(db, ctx, f, paging)


@router.get("/opening-balances/employees/{employee_id}", response_model=Item[OpeningBalanceEmployeeOut])
def opening_balances_of(employee_id: int, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.opening_balances.view"))):
    return c.opening_balances_of(db, ctx, employee_id)


@router.post("/opening-balances/import", response_model=Item[ImportResultOut])
def import_opening_balances(body: OpeningBalanceImportIn, db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("payroll.opening_balances.import"))):
    return c.import_opening_balances(db, ctx, body)


@router.get("/opening-balances/{id}", response_model=Item[OpeningBalanceOut])
def get_opening_balance(id: int, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.opening_balances.view"))):
    return c.get_opening_balance(db, ctx, id)


@router.post("/opening-balances", response_model=Item[OpeningBalanceOut], status_code=CREATED)
def create_opening_balance(body: OpeningBalanceIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.opening_balances.create"))):
    return c.save_opening_balance(db, ctx, None, body)


@router.put("/opening-balances/{id}", response_model=Item[OpeningBalanceOut])
def update_opening_balance(id: int, body: OpeningBalanceIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.opening_balances.edit"))):
    return c.save_opening_balance(db, ctx, id, body)


@router.delete("/opening-balances/{id}", status_code=NO_CONTENT)
def delete_opening_balance(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.opening_balances.delete"))):
    c.delete_opening_balance(db, ctx, id, row_version)
    return gone()


# --------------------------------------------------------------------------- employee accounts

@router.get("/employee-accounts", response_model=Paginated[AccountEntryOut])
def list_account_entries(scope: str = "all", q: str | None = None,
                         employee_id: int | None = Query(None, alias="employeeId"),
                         account_type_id: int | None = Query(None, alias="accountTypeId"), month: date | None = None,
                         paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.employee_accounts.view"))):
    f = dict(scope=scope, search=q, employee_id=employee_id, account_type_id=account_type_id, month=month)
    return c.list_account_entries(db, ctx, f, paging)


@router.post("/employee-accounts/import", response_model=Item[ImportResultOut])
def import_account_entries(body: AccountImportIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.employee_accounts.import"))):
    return c.import_account_entries(db, ctx, body)


@router.get("/employee-accounts/{id}", response_model=Item[AccountEntryOut])
def get_account_entry(id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.employee_accounts.view"))):
    return c.get_account_entry(db, ctx, id)


@router.post("/employee-accounts", response_model=Item[AccountEntryOut], status_code=CREATED)
def create_account_entry(body: AccountEntryIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.employee_accounts.create"))):
    return c.save_account_entry(db, ctx, None, body)


@router.put("/employee-accounts/{id}", response_model=Item[AccountEntryOut])
def update_account_entry(id: int, body: AccountEntryIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.employee_accounts.edit"))):
    return c.save_account_entry(db, ctx, id, body)


@router.delete("/employee-accounts/{id}", status_code=NO_CONTENT)
def delete_account_entry(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.employee_accounts.delete"))):
    c.delete_account_entry(db, ctx, id, row_version)
    return gone()


@router.get("/account-statement", response_model=Paginated[StatementRowOut])
def account_statement(employee_id: int | None = Query(None, alias="employeeId"),
                      account_type_id: int | None = Query(None, alias="accountTypeId"),
                      from_month: date | None = Query(None, alias="from"), to_month: date | None = Query(None, alias="to"),
                      paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.employee_accounts.view"))):
    return c.account_statement(db, ctx, employee_id, account_type_id, from_month, to_month, paging)


# --------------------------------------------------------------------------- salary revision

@router.get("/salary-revisions", response_model=Paginated[SalaryRevisionOut])
def list_revisions(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                   from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                   salary_from: float | None = Query(None, alias="salaryFrom"),
                   salary_to: float | None = Query(None, alias="salaryTo"),
                   paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.salary_revision.view"))):
    f = dict(search=q, employee_id=employee_id, from_date=from_date, to_date=to_date, salary_from=salary_from,
             salary_to=salary_to)
    return c.list_revisions(db, ctx, f, paging)


@router.get("/salary-revisions/current/{employee_id}", response_model=Item[CurrentSalaryOut])
def current_salary(employee_id: int, as_of: date | None = Query(None, alias="date"), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.salary_revision.view"))):
    return c.current_salary(db, ctx, employee_id, as_of)


@router.post("/salary-revisions/import", response_model=Item[ImportResultOut])
def import_revisions(body: SalaryImportIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.salary_revision.import"))):
    return c.import_revisions(db, ctx, body)


@router.get("/salary-revisions/{id}/email/preview", response_model=Item[SalaryRevisionEmailPreviewOut])
def revision_email_preview(id: int, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.salary_revision.view"))):
    """The salary revision letter: subject, body and the address it goes to."""
    return c.revision_email_preview(db, ctx, id)


@router.post("/salary-revisions/{id}/email", response_model=Item[SalaryRevisionEmailOut])
def send_revision_email(id: int, body: RowVersionIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.salary_revision.send"))):
    """E-mails the letter to the person. While mail is not set up the answer is status 'disabled' (nothing sent)."""
    return c.send_revision_email(db, ctx, id, body)


@router.get("/salary-revisions/{id}", response_model=Item[SalaryRevisionOut])
def get_revision(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.salary_revision.view"))):
    return c.get_revision(db, ctx, id)


@router.post("/salary-revisions", response_model=Item[SalaryRevisionOut], status_code=CREATED)
def create_revision(body: SalaryRevisionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.salary_revision.create"))):
    return c.save_revision(db, ctx, None, body)


@router.put("/salary-revisions/{id}", response_model=Item[SalaryRevisionOut])
def update_revision(id: int, body: SalaryRevisionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.salary_revision.edit"))):
    return c.save_revision(db, ctx, id, body)


@router.delete("/salary-revisions/{id}", status_code=NO_CONTENT)
def delete_revision(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.salary_revision.delete"))):
    c.delete_revision(db, ctx, id, row_version)
    return gone()


# --------------------------------------------------------------------------- leave encashment

@router.get("/leave-encashments", response_model=Paginated[LeaveEncashmentRowOut])
def list_encashments(q: str | None = None, leave_type_id: int | None = Query(None, alias="leaveTypeId"),
                     year: int | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.leave_encashment.view"))):
    f = dict(search=q, leave_type_id=leave_type_id, fiscal_year=year, employee_id=employee_id)
    return c.list_encashments(db, ctx, f, paging)


@router.post("/leave-encashments/preview", response_model=Item[list[LeaveEncashmentPreviewOut]])
def preview_encashment(body: LeaveEncashmentPreviewIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require_any("payroll.leave_encashment.create",
                                                                 "payroll.leave_encashment.edit"))):
    """What saving would encash, per person: days available, days encashed (0 below the type's minimum, the
    maximum above it, `cappedBy` says which) and the amount. Nothing is written."""
    return c.preview_encashment(db, ctx, body)


@router.get("/leave-encashments/{id}", response_model=Item[LeaveEncashmentOut])
def get_encashment(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.leave_encashment.view"))):
    return c.get_encashment(db, ctx, id)


@router.post("/leave-encashments", response_model=Item[LeaveEncashmentOut], status_code=CREATED)
def create_encashment(body: LeaveEncashmentIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.leave_encashment.create"))):
    return c.save_encashment(db, ctx, None, body)


@router.put("/leave-encashments/{id}", response_model=Item[LeaveEncashmentOut])
def update_encashment(id: int, body: LeaveEncashmentIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.leave_encashment.edit"))):
    return c.save_encashment(db, ctx, id, body)


@router.delete("/leave-encashments/{id}", status_code=NO_CONTENT)
def delete_encashment(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.leave_encashment.delete"))):
    c.delete_encashment(db, ctx, id, row_version)
    return gone()
