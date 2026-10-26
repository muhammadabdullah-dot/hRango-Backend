"""Payrolls (Monthly, Daily Wages), Salary Sheet and Pay Slips."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import payroll_runs_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.payroll_runs import (AccountSummaryOut, ChangedOut, CreatedOut, DailyWageEditIn, DailyWageIn,
                                      DailyWageOut, EmployeeCountOut, EmployeeFilterIn, EmployeeIdsIn, IdsIn,
                                      PayrollEmployeeOut, PayrollIn, PayrollOut, PayslipDetailOut, PayslipEditIn,
                                      PayslipHistoryOut, PayslipOut, RowVersionIn, RunErrorOut, RunLogOut,
                                      SalarySheetOut)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED
RV = Query(None, alias="rowVersion")


# --------------------------------------------------------------------------- monthly payrolls

@router.get("/payrolls", response_model=Paginated[PayrollOut])
def list_payrolls(q: str | None = None, status_: str | None = Query(None, alias="status"), month: date | None = None,
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.payrolls.view"))):
    return c.list_payrolls(db, ctx, "monthly", q, status_, month, None, None, None, paging)


@router.get("/payrolls/{id}", response_model=Item[PayrollOut])
def get_payroll(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payrolls.view"))):
    return c.get_payroll(db, ctx, id)


@router.post("/payrolls", response_model=Item[PayrollOut], status_code=CREATED)
def create_payroll(body: PayrollIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.payrolls.create"))):
    return c.save_payroll(db, ctx, None, body)


@router.put("/payrolls/{id}", response_model=Item[PayrollOut])
def update_payroll(id: int, body: PayrollIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.payrolls.edit"))):
    return c.save_payroll(db, ctx, id, body)


@router.delete("/payrolls/{id}", status_code=NO_CONTENT)
def delete_payroll(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.payrolls.delete"))):
    c.delete_payroll(db, ctx, id, "monthly", row_version)
    return Response(status_code=NO_CONTENT)


@router.get("/payrolls/{id}/employees", response_model=Item[list[PayrollEmployeeOut]])
def list_payroll_employees(id: int, q: str | None = None, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("payroll.payrolls.view"))):
    return c.list_employees(db, ctx, id, q)


@router.put("/payrolls/{id}/employees", response_model=Item[EmployeeCountOut])
def set_payroll_employees(id: int, body: EmployeeIdsIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("payroll.payrolls.edit"))):
    return c.set_employees(db, ctx, id, "monthly", body)


@router.post("/payrolls/{id}/employees/add", response_model=Item[EmployeeCountOut])
def add_payroll_employees(id: int, body: EmployeeFilterIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("payroll.payrolls.edit"))):
    return c.add_employees(db, ctx, id, "monthly", body)


@router.post("/payrolls/{id}/run", response_model=Item[RunLogOut])
def run_payroll(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payrolls.process"))):
    return c.run(db, ctx, id)


@router.post("/payrolls/{id}/close", response_model=Item[PayrollOut])
def close_payroll(id: int, body: RowVersionIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.payrolls.close"))):
    return c.close(db, ctx, id, "monthly", body)


@router.post("/payrolls/{id}/hold", response_model=Item[PayrollOut])
def hold_payroll(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payrolls.edit"))):
    return c.hold(db, ctx, id, True)


@router.post("/payrolls/{id}/unhold", response_model=Item[PayrollOut])
def unhold_payroll(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payrolls.edit"))):
    return c.hold(db, ctx, id, False)


@router.get("/payrolls/{id}/history", response_model=Item[list[RunLogOut]])
def payroll_history(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payrolls.view"))):
    return c.history(db, ctx, id)


@router.get("/payrolls/{id}/errors", response_model=Item[list[RunErrorOut]])
def payroll_errors(id: int, run_log_id: int | None = Query(None, alias="runLogId"), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.payrolls.view"))):
    return c.errors(db, ctx, id, run_log_id)


# --------------------------------------------------------------------------- daily wages

@router.get("/daily-wages", response_model=Paginated[PayrollOut])
def list_daily_wages(q: str | None = None, status_: str | None = Query(None, alias="status"),
                     from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                     time_slot_id: int | None = Query(None, alias="timeSlotId"), paging: PageParams = Depends(page_params),
                     db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.daily_wages.view"))):
    return c.list_payrolls(db, ctx, "daily_wage", q, status_, None, from_date, to_date, time_slot_id, paging)


@router.get("/daily-wages/{id}", response_model=Item[DailyWageOut])
def get_daily_wage(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.daily_wages.view"))):
    return c.get_daily_wage(db, ctx, id)


@router.post("/daily-wages", response_model=Item[DailyWageOut], status_code=CREATED)
def create_daily_wage(body: DailyWageIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.daily_wages.create"))):
    return c.create_daily_wage(db, ctx, body)


@router.put("/daily-wages/{id}", response_model=Item[DailyWageOut])
def edit_daily_wage(id: int, body: DailyWageEditIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.daily_wages.edit"))):
    return c.edit_daily_wage(db, ctx, id, body)


@router.put("/daily-wages/{id}/employees", response_model=Item[EmployeeCountOut])
def set_daily_wage_employees(id: int, body: EmployeeIdsIn, db: Db = Depends(get_db),
                             ctx: RequestContext = Depends(require("payroll.daily_wages.edit"))):
    return c.set_employees(db, ctx, id, "daily_wage", body)


@router.delete("/daily-wages/{id}", status_code=NO_CONTENT)
def delete_daily_wage(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.daily_wages.delete"))):
    c.delete_payroll(db, ctx, id, "daily_wage", row_version)
    return Response(status_code=NO_CONTENT)


@router.post("/daily-wages/{id}/process", response_model=Item[RunLogOut])
def process_daily_wage(id: int, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("payroll.daily_wages.process"))):
    return c.process_daily_wage(db, ctx, id)


@router.post("/daily-wages/{id}/close", response_model=Item[PayrollOut])
def close_daily_wage(id: int, body: RowVersionIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.daily_wages.close"))):
    return c.close(db, ctx, id, "daily_wage", body)


@router.post("/daily-wages/{id}/vouchers", response_model=Item[CreatedOut])
def daily_wage_vouchers(id: int, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.vouchers.create"))):
    return c.daily_wage_vouchers(db, ctx, id)


@router.get("/daily-wages/{id}/errors", response_model=Item[list[RunErrorOut]])
def daily_wage_errors(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.daily_wages.view"))):
    return c.errors(db, ctx, id, None)


# --------------------------------------------------------------------------- salary sheet

@router.get("/salary-sheet", response_model=Item[SalarySheetOut])
def salary_sheet(payroll_id: int | None = Query(None, alias="payrollId"), month: date | None = None,
                 db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.salary_sheet.view"))):
    return c.salary_sheet(db, ctx, payroll_id, month)


# --------------------------------------------------------------------------- payslips

@router.get("/payslips", response_model=Paginated[PayslipOut])
def list_payslips(scope: Literal["my", "all"] = "all", q: str | None = None,
                  payroll_id: int | None = Query(None, alias="payrollId"), month: date | None = None,
                  status_: str | None = Query(None, alias="status"),
                  employee_id: int | None = Query(None, alias="employeeId"),
                  branch_id: int | None = Query(None, alias="branchId"),
                  department_id: int | None = Query(None, alias="departmentId"),
                  employee_status: str | None = Query(None, alias="employmentStatus"),
                  final_settlement: bool | None = Query(None, alias="finalSettlement"),
                  earnings_from: float | None = Query(None, alias="earningsFrom"),
                  earnings_to: float | None = Query(None, alias="earningsTo"),
                  deductions_from: float | None = Query(None, alias="deductionFrom"),
                  deductions_to: float | None = Query(None, alias="deductionTo"),
                  net_from: float | None = Query(None, alias="netFrom"), net_to: float | None = Query(None, alias="netTo"),
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.payslips.view"))):
    filters = dict(scope=scope, search=q, payroll_id=payroll_id, month=month, status=status_, employee_id=employee_id,
                   branch_id=branch_id, department_id=department_id, employee_status=employee_status,
                   final_settlement=final_settlement, earnings_from=earnings_from, earnings_to=earnings_to,
                   deductions_from=deductions_from, deductions_to=deductions_to, net_from=net_from, net_to=net_to)
    return c.list_payslips(db, ctx, filters, paging)


@router.get("/payslips/summary", response_model=Item[AccountSummaryOut])
def account_summary(employee_id: int | None = Query(None, alias="employeeId"), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.payslips.view"))):
    return c.account_summary(db, ctx, employee_id)


@router.post("/payslips/hold", response_model=Item[ChangedOut])
def hold_payslips(body: IdsIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.edit"))):
    return c.payslips_bulk(db, ctx, body.ids, "hold")


@router.post("/payslips/unhold", response_model=Item[ChangedOut])
def unhold_payslips(body: IdsIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.edit"))):
    return c.payslips_bulk(db, ctx, body.ids, "unhold")


@router.post("/payslips/pay", response_model=Item[ChangedOut])
def pay_payslips(body: IdsIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.process"))):
    return c.payslips_bulk(db, ctx, body.ids, "pay")


@router.post("/payslips/recalculate", response_model=Item[ChangedOut])
def recalculate_payslips(body: IdsIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.payslips.process"))):
    return c.payslips_bulk(db, ctx, body.ids, "recalculate")


@router.get("/payslips/{id}", response_model=Item[PayslipDetailOut])
def get_payslip(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.view"))):
    return c.get_payslip(db, ctx, id)


@router.put("/payslips/{id}", response_model=Item[PayslipDetailOut])
def edit_payslip(id: int, body: PayslipEditIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("payroll.payslips.edit"))):
    return c.edit_payslip(db, ctx, id, body)


@router.post("/payslips/{id}/hold", response_model=Item[PayslipDetailOut])
def hold_payslip(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.edit"))):
    return c.payslip_action(db, ctx, id, "hold")


@router.post("/payslips/{id}/unhold", response_model=Item[PayslipDetailOut])
def unhold_payslip(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.edit"))):
    return c.payslip_action(db, ctx, id, "unhold")


@router.post("/payslips/{id}/pay", response_model=Item[PayslipDetailOut])
def pay_payslip(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.process"))):
    return c.payslip_action(db, ctx, id, "pay")


@router.post("/payslips/{id}/recalculate", response_model=Item[PayslipDetailOut])
def recalculate_payslip(id: int, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.payslips.process"))):
    return c.payslip_action(db, ctx, id, "recalculate")


@router.get("/payslips/{id}/history", response_model=Item[list[PayslipHistoryOut]])
def payslip_history(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.payslips.view"))):
    return c.payslip_history(db, ctx, id)
