"""Payroll runs: creating them, choosing people, running (inputs -> engine -> save), closing, daily wages,
the salary sheet and payslips."""
import json
from datetime import datetime, timezone
from decimal import ROUND_CEILING, ROUND_FLOOR, ROUND_HALF_UP, Decimal
from typing import Any

from app.core import mail
from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import payroll_runs_repo as repo
from app.schemas.payroll_runs import DailyWageEditIn, DailyWageIn, EmployeeFilterIn, PayrollIn, PayslipEditIn
from app.services import payroll_engine, payroll_mail_service, payroll_settings_service

Row = dict[str, Any]
CODES = {
    "monthly": {"edit": "payroll.payrolls.edit", "process": "payroll.payrolls.process"},
    "daily_wage": {"create": "payroll.daily_wages.create", "edit": "payroll.daily_wages.edit"},
    "payslip_view": "payroll.payslips.view", "payslip_edit": "payroll.payslips.edit",
    "payslip_process": "payroll.payslips.process", "sheet": "payroll.salary_sheet.view",
}


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def _not_mine(ctx: RequestContext, employee_id: int | None) -> None:
    """Nobody changes their own pay: payroll writes on one's own record are refused whatever the role."""
    if ctx.employee_id is not None and employee_id is not None and int(employee_id) == ctx.employee_id:
        raise AppError(403, "OWN_PAY_RECORD", "You cannot change your own pay records.")


def run_settings(db: Db, company_id: int) -> payroll_engine.RunSettings:
    s = payroll_settings_service.load(db, company_id)
    return payroll_engine.RunSettings(tax_rounding=s.tax_rounding, proration_rounding=s.proration_rounding,
                                      use_shift_hours=s.use_shift_hours,
                                      disable_tax_distribution_on_final_settlement=s.disable_tax_distribution_on_final_settlement)


# --------------------------------------------------------------------------- monthly payrolls

def list_payrolls(db: Db, ctx: RequestContext, kind: str, search, status, month, from_date, to_date, time_slot_id,
                  page: int, page_size: int):
    return repo.list_payrolls(db, ctx.company_id, kind, search, status, month, from_date, to_date, time_slot_id, page,
                              page_size)


def get_payroll(db: Db, ctx: RequestContext, id: int, kind: str = "monthly"):
    return repo.get_payroll(db, ctx.company_id, id, kind)


def save_payroll(db: Db, ctx: RequestContext, id: int | None, body: PayrollIn, row_version: bytes | None):
    if body.applicable_days == "fixed" and not body.fixed_days:
        raise AppError(422, "VALIDATION_FAILED", "Give the number of fixed days.", {"fixedDays": "Give the number of fixed days."})
    items_json = None
    if body.pay_items is not None:
        items_json = json.dumps([i.model_dump(by_alias=True) for i in body.pay_items])
    return repo.save_payroll(db, ctx.company_id, ctx.user_id, id, body, items_json, row_version)


def delete_payroll(db: Db, ctx: RequestContext, id: int, kind: str, row_version: bytes) -> None:
    repo.delete_payroll(db, ctx.company_id, ctx.user_id, id, kind, row_version)


def list_employees(db: Db, ctx: RequestContext, id: int, search) -> list[Row]:
    return repo.list_payroll_employees(db, ctx.company_id, id, search)


def set_employees(db: Db, ctx: RequestContext, id: int, kind: str, employee_ids: list[int]) -> Row:
    if kind == "daily_wage":
        for e in employee_ids:
            _not_mine(ctx, e)
    code = CODES[kind]["edit"]
    return repo.set_payroll_employees(db, ctx.company_id, ctx.user_id, code, id, json.dumps(employee_ids), "replace")


def add_employees(db: Db, ctx: RequestContext, id: int, kind: str, f: EmployeeFilterIn) -> Row:
    return repo.add_payroll_employees_filtered(db, ctx.company_id, ctx.user_id, CODES[kind]["edit"], id, f)


def hold_payroll(db: Db, ctx: RequestContext, id: int, hold: bool):
    return repo.hold_payroll(db, ctx.company_id, ctx.user_id, id, hold)


def history(db: Db, ctx: RequestContext, id: int) -> list[Row]:
    return repo.payroll_history(db, ctx.company_id, id)


def errors(db: Db, ctx: RequestContext, id: int, run_log_id: int | None) -> list[Row]:
    return repo.payroll_errors(db, ctx.company_id, id, run_log_id)


def run(db: Db, ctx: RequestContext, id: int, employee_ids: list[int] | None = None) -> Row:
    """Runs a monthly payroll for everyone in it, or recalculates the given people."""
    started = _now()
    sets = repo.run_inputs(db, ctx.company_id, id, json.dumps(employee_ids) if employee_ids is not None else None)
    result = payroll_engine.compute(sets, run_settings(db, ctx.company_id))
    return repo.run_save(db, ctx.company_id, ctx.user_id, id, "run" if employee_ids is None else "recalculate", started,
                         json.dumps(result.payslips), json.dumps(result.errors))


def close(db: Db, ctx: RequestContext, id: int, kind: str, row_version: bytes) -> tuple[Row, list[Row], Row | None]:
    """Closes the run. A monthly run also records its close e-mail ('disabled' while mail is not set up) and
    returns {status, sent_count, failed_count} as the third value (None for daily wages)."""
    if kind != "monthly":
        head, items = repo.close_payroll(db, ctx.company_id, ctx.user_id, id, kind, row_version)
        return head, items, None
    subject = payroll_mail_service.close_email_subject(db, ctx, id)
    head, items = repo.close_payroll(db, ctx.company_id, ctx.user_id, id, kind, row_version, mail.enabled(), subject)
    # TODO(payroll): when mail is enabled, wake the mail sender for the queued rows (see payroll_mail_service).
    email = repo.close_email_get(db, ctx.company_id, id)[0]
    return head, items, {k: email[k] for k in ("status", "sent_count", "failed_count")}


# --------------------------------------------------------------------------- daily wages

def create_daily_wage(db: Db, ctx: RequestContext, body: DailyWageIn) -> int:
    for e in body.employee_ids:
        _not_mine(ctx, e)
    return repo.save_daily_wage(db, ctx.company_id, ctx.user_id, CODES["daily_wage"]["create"], body)


def get_daily_wage(db: Db, ctx: RequestContext, id: int):
    return repo.get_daily_wage(db, ctx.company_id, id)


def edit_daily_wage(db: Db, ctx: RequestContext, id: int, body: DailyWageEditIn, row_version: bytes):
    for r in body.rows:
        _not_mine(ctx, r.employee_id)
        if r.total_deductions > r.total_earnings:
            raise AppError(422, "VALIDATION_FAILED", "Deductions cannot be more than earnings.",
                           {"rows": "Deductions cannot be more than earnings."})
    rows_json = json.dumps([{"employeeId": r.employee_id, "totalEarnings": str(r.total_earnings),
                             "totalDeductions": str(r.total_deductions)} for r in body.rows])
    return repo.save_daily_wage_rows(db, ctx.company_id, ctx.user_id, id, body.name, rows_json, row_version)


def process_daily_wage(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.process_daily_wage(db, ctx.company_id, ctx.user_id, id)


def daily_wage_vouchers(db: Db, ctx: RequestContext, id: int) -> int:
    return repo.daily_wage_vouchers(db, ctx.company_id, ctx.user_id, id)["created"]


# --------------------------------------------------------------------------- salary sheet

_ROUND = {"round_off": ROUND_HALF_UP, "ceil": ROUND_CEILING, "floor": ROUND_FLOOR}
SHEET_FIELDS = ("gross", "overtime", "tax", "leave_deduction", "short_deduction", "absent_deduction", "total_earnings",
                "total_reimbursements", "total_deductions", "net_payable")


def salary_sheet(db: Db, ctx: RequestContext, payroll_id, month) -> dict:
    settings = payroll_settings_service.load(db, ctx.company_id)
    rows, lines = repo.salary_sheet(db, ctx.company_id, ctx.user_id, CODES["sheet"], payroll_id, month)
    if not settings.show_on_hold_amounts:
        rows = [r for r in rows if r["status"] != "on_hold"]
    mode = _ROUND.get(settings.salary_report_rounding)

    def rnd(v) -> Decimal:
        v = Decimal(str(v or 0))
        return v.to_integral_value(rounding=mode) if mode else v

    by_slip: dict[int, list[Row]] = {}
    columns: dict[int, Row] = {}
    for ln in lines:
        by_slip.setdefault(ln["payslip_id"], []).append(ln)
        columns.setdefault(ln["pay_item_id"], {"pay_item_id": ln["pay_item_id"], "pay_item_name": ln["pay_item_name"],
                                               "item_type": ln["item_type"]})
    out_rows = []
    totals = {f: Decimal(0) for f in SHEET_FIELDS}
    for r in rows:
        row = {**r, **{f: rnd(r[f]) for f in SHEET_FIELDS}}
        row["items"] = [{**ln, "amount": rnd(ln["amount"])} for ln in by_slip.get(r["payslip_id"], [])]
        for f in SHEET_FIELDS:
            totals[f] += row[f]
        out_rows.append(row)
    return {"rounding": settings.salary_report_rounding, "print_signature": settings.print_signature,
            "columns": list(columns.values()), "rows": out_rows, "totals": totals}


# --------------------------------------------------------------------------- payslips

PAYSLIP_FILTERS = ("scope", "search", "payroll_id", "month", "status", "employee_id", "branch_id", "department_id",
                   "employee_status", "final_settlement", "earnings_from", "earnings_to", "deductions_from",
                   "deductions_to", "net_from", "net_to")


def list_payslips(db: Db, ctx: RequestContext, filters: dict, page: int, page_size: int):
    hide = payroll_settings_service.load(db, ctx.company_id).hide_payslip_after_run
    return repo.list_payslips(db, ctx.company_id, ctx.user_id, CODES["payslip_view"], hide,
                              {k: filters.get(k) for k in PAYSLIP_FILTERS}, page, page_size)


def get_payslip(db: Db, ctx: RequestContext, id: int):
    settings = payroll_settings_service.load(db, ctx.company_id)
    head, lines = repo.get_payslip(db, ctx.company_id, ctx.user_id, CODES["payslip_view"], id,
                                   settings.hide_payslip_after_run)
    return head, lines, display(settings)


def display(settings) -> dict:
    return {"template": settings.payslip_template, "color": settings.payslip_color,
            "show_salary_breakdown": settings.show_salary_breakdown,
            "hide_attendance_summary": settings.hide_attendance_summary,
            "show_employee_pay_items": settings.show_employee_pay_items, "tax_positive_only": settings.tax_positive_only,
            "notes_english": settings.notes_english if settings.notes_english_enabled else None,
            "notes_other_language": settings.notes_other_language}


def edit_payslip(db: Db, ctx: RequestContext, id: int, body: PayslipEditIn, row_version: bytes):
    head, _ = repo.get_payslip(db, ctx.company_id, ctx.user_id, CODES["payslip_edit"], id)
    _not_mine(ctx, head["employee_id"])
    ids = [l.pay_item_id for l in body.lines]
    if len(ids) != len(set(ids)):
        raise AppError(422, "VALIDATION_FAILED", "A pay item is listed twice.", {"lines": "A pay item is listed twice."})
    lines_json = json.dumps([{"payItemId": l.pay_item_id, "amount": str(l.amount),
                              "employerContribution": None if l.employer_contribution is None else str(l.employer_contribution)}
                             for l in body.lines])
    head, lines = repo.save_payslip_lines(db, ctx.company_id, ctx.user_id, CODES["payslip_edit"], id, lines_json, row_version)
    return head, lines, display(payroll_settings_service.load(db, ctx.company_id))


def set_status(db: Db, ctx: RequestContext, ids: list[int], action: str) -> int:
    code = CODES["payslip_process"] if action == "pay" else CODES["payslip_edit"]
    if action == "pay" and ctx.employee_id is not None:
        for id in ids:
            head, _ = repo.get_payslip(db, ctx.company_id, ctx.user_id, code, id)
            _not_mine(ctx, head["employee_id"])
    return repo.set_payslip_status(db, ctx.company_id, ctx.user_id, code, json.dumps(ids), action)


def recalculate(db: Db, ctx: RequestContext, ids: list[int]) -> tuple[int, list[str]]:
    """Works the payslips out again (lines edited by hand are kept), run by run."""
    by_run: dict[int, list[int]] = {}
    for id in ids:
        head, _ = repo.get_payslip(db, ctx.company_id, ctx.user_id, CODES["payslip_process"], id)
        if head["payroll_id"] is None:
            raise AppError(409, "PAYSLIP_FINAL_SETTLEMENT", "Recalculate a final settlement payslip from Final Settlement.")
        if head["payroll_kind"] != "monthly":
            raise AppError(409, "PAYSLIP_DAILY_WAGE", "Daily wages are processed again from the daily wages payroll.")
        if head["status"] == "released" or head["payroll_status"] == "closed":
            raise AppError(409, "PAYSLIP_LOCKED", "A released payslip or one of a closed payroll cannot be recalculated.",
                           {"status": "Released or closed."})
        by_run.setdefault(head["payroll_id"], []).append(head["employee_id"])
    changed, problems = 0, []
    for payroll_id, employees in by_run.items():
        log = run(db, ctx, payroll_id, employees)
        changed += log["processed_count"] or 0
        if log["error_count"]:
            problems += [f"{e['employee_name'] or e['employee_id']}: {e['message']}"
                         for e in repo.payroll_errors(db, ctx.company_id, payroll_id, log["id"])]
    return changed, problems


def history_of_payslip(db: Db, ctx: RequestContext, id: int) -> list[Row]:
    return repo.payslip_history(db, ctx.company_id, ctx.user_id, CODES["payslip_view"], id)


def account_summary(db: Db, ctx: RequestContext, employee_id: int | None):
    return repo.account_summary(db, ctx.company_id, ctx.user_id, CODES["payslip_view"], employee_id)


# --------------------------------------------------------------------------- final settlement (calculation)

def calculate_final_settlement(db: Db, ctx: RequestContext, id: int, permission_code: str) -> Row:
    sets = repo.final_settlement_inputs(db, ctx.company_id, ctx.user_id, permission_code, id)
    employees = sets[6]
    if employees:
        _not_mine(ctx, employees[0]["employee_id"])
    result = payroll_engine.compute(sets, run_settings(db, ctx.company_id))
    if result.errors or not result.payslips:
        message = result.errors[0]["message"] if result.errors else "Nothing to work out."
        raise AppError(422, "SETTLEMENT_NOT_CALCULATED", f"The settlement could not be worked out: {message}")
    return repo.final_settlement_save(db, ctx.company_id, ctx.user_id, permission_code, id,
                                      json.dumps(result.payslips[0]))
