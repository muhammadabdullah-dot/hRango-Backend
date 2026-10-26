"""Payroll runs, salary sheet and payslips: data access. The only layer that knows these procedure names."""
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def list_payrolls(db: Db, company_id: int, kind: str, search, status, month, from_date, to_date, time_slot_id,
                  page: int, page_size: int) -> tuple[int, list[Row]]:
    total, rows = db.call_sets("pay.usp_payroll_list", company_id=company_id, kind=kind, search=search, status=status,
                               month=month, from_date=from_date, to_date=to_date, time_slot_id=time_slot_id, page=page,
                               page_size=page_size)
    return total[0]["total"], rows


def get_payroll(db: Db, company_id: int, id: int, kind: str | None = None) -> tuple[Row, list[Row]]:
    head, items = db.call_sets("pay.usp_payroll_get", company_id=company_id, id=id, kind=kind)
    return head[0], items


def save_payroll(db: Db, company_id: int, actor_user_id: int, id: int | None, body, pay_items_json: str | None,
                 row_version: bytes | None) -> tuple[Row, list[Row]]:
    sets = db.call_sets("pay.usp_payroll_save", company_id=company_id, actor_user_id=actor_user_id, id=id,
                        name=body.name, payroll_month=body.payroll_month, currency=body.currency,
                        tax_structure_id=body.tax_structure_id, tax_applicable=body.tax_applicable,
                        processing_mode=body.processing_mode, processing_date=body.processing_date,
                        applicable_days=body.applicable_days, fixed_days=body.fixed_days,
                        disbursement_bank_id=body.disbursement_bank_id, description=body.description,
                        pay_items=pay_items_json, row_version=row_version)
    return sets[-2][0], sets[-1]


def delete_payroll(db: Db, company_id: int, actor_user_id: int, id: int, kind: str, row_version: bytes) -> None:
    db.call("pay.usp_payroll_delete", company_id=company_id, actor_user_id=actor_user_id, id=id, kind=kind,
            row_version=row_version)


def list_payroll_employees(db: Db, company_id: int, id: int, search: str | None) -> list[Row]:
    return db.call("pay.usp_payroll_employee_list", company_id=company_id, id=id, search=search)


def set_payroll_employees(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int,
                          employee_ids_json: str, mode: str) -> Row:
    return db.call_one("pay.usp_payroll_employee_set", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=id, employee_ids=employee_ids_json, mode=mode)


def add_payroll_employees_filtered(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int,
                                   f) -> Row:
    return db.call_one("pay.usp_payroll_employee_add_filtered", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=id, branch_id=f.branch_id, department_id=f.department_id,
                       designation_id=f.designation_id, grade_id=f.grade_id, location_id=f.location_id,
                       employee_group_id=f.employee_group_id, employment_type_id=f.employment_type_id,
                       employee_status=f.employee_status, joined_from=f.joined_from, joined_to=f.joined_to)


def hold_payroll(db: Db, company_id: int, actor_user_id: int, id: int, hold: bool) -> tuple[Row, list[Row]]:
    head, items = db.call_sets("pay.usp_payroll_hold", company_id=company_id, actor_user_id=actor_user_id, id=id,
                               hold=hold)
    return head[0], items


def payroll_history(db: Db, company_id: int, id: int) -> list[Row]:
    return db.call("pay.usp_payroll_history", company_id=company_id, id=id)


def payroll_errors(db: Db, company_id: int, id: int, run_log_id: int | None) -> list[Row]:
    return db.call("pay.usp_payroll_errors", company_id=company_id, id=id, run_log_id=run_log_id)


def run_inputs(db: Db, company_id: int, id: int, employee_ids_json: str | None) -> list[list[Row]]:
    return db.call_sets("pay.usp_payroll_run_inputs", company_id=company_id, id=id, employee_ids=employee_ids_json)


def run_save(db: Db, company_id: int, actor_user_id: int, id: int, run_kind: str, started_at, payslips_json: str,
             errors_json: str) -> Row:
    return db.call_one("pay.usp_payroll_run_save", company_id=company_id, actor_user_id=actor_user_id, id=id,
                       run_kind=run_kind, started_at=started_at, payslips=payslips_json, errors=errors_json)


def close_payroll(db: Db, company_id: int, actor_user_id: int, id: int, kind: str,
                  row_version: bytes) -> tuple[Row, list[Row]]:
    head, items = db.call_sets("pay.usp_payroll_close", company_id=company_id, actor_user_id=actor_user_id, id=id,
                               kind=kind, row_version=row_version)
    return head[0], items


# --------------------------------------------------------------------------- daily wages

def save_daily_wage(db: Db, company_id: int, actor_user_id: int, permission_code: str, body) -> int:
    sets = db.call_sets("pay.usp_daily_wage_save", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, id=None, name=body.name, work_date=body.work_date,
                        time_slot_id=body.time_slot_id,
                        employee_ids="[" + ",".join(str(i) for i in body.employee_ids) + "]" if body.employee_ids else None)
    return sets[-1][0]["id"]


def get_daily_wage(db: Db, company_id: int, id: int) -> tuple[Row, list[Row], list[Row]]:
    head, items, rows = db.call_sets("pay.usp_daily_wage_get", company_id=company_id, id=id)
    return head[0], items, rows


def save_daily_wage_rows(db: Db, company_id: int, actor_user_id: int, id: int, name: str, rows_json: str,
                         row_version: bytes) -> tuple[Row, list[Row], list[Row]]:
    head, items, rows = db.call_sets("pay.usp_daily_wage_rows_save", company_id=company_id, actor_user_id=actor_user_id,
                                     id=id, name=name, rows=rows_json, row_version=row_version)
    return head[0], items, rows


def process_daily_wage(db: Db, company_id: int, actor_user_id: int, id: int) -> Row:
    return db.call_one("pay.usp_daily_wage_process", company_id=company_id, actor_user_id=actor_user_id, id=id)


def daily_wage_vouchers(db: Db, company_id: int, actor_user_id: int, id: int) -> Row:
    return db.call_one("pay.usp_daily_wage_vouchers", company_id=company_id, actor_user_id=actor_user_id, id=id)


# --------------------------------------------------------------------------- salary sheet and payslips

def salary_sheet(db: Db, company_id: int, actor_user_id: int, permission_code: str, payroll_id, month):
    rows, lines = db.call_sets("pay.usp_salary_sheet", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, payroll_id=payroll_id, month=month)
    return rows, lines


def list_payslips(db: Db, company_id: int, actor_user_id: int, permission_code: str, hide_unreleased: bool,
                  f: dict, page: int, page_size: int) -> tuple[int, list[Row]]:
    total, rows = db.call_sets("pay.usp_payslip_list", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, hide_unreleased=hide_unreleased, **f, page=page,
                               page_size=page_size)
    return total[0]["total"], rows


def get_payslip(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int,
                hide_unreleased: bool = False) -> tuple[Row, list[Row]]:
    head, lines = db.call_sets("pay.usp_payslip_get", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, id=id, hide_unreleased=hide_unreleased)
    return head[0], lines


def save_payslip_lines(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int, lines_json: str,
                       row_version: bytes) -> tuple[Row, list[Row]]:
    head, lines = db.call_sets("pay.usp_payslip_lines_save", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, id=id, lines=lines_json, row_version=row_version)
    return head[0], lines


def set_payslip_status(db: Db, company_id: int, actor_user_id: int, permission_code: str, ids_json: str,
                       action: str) -> int:
    return db.call_one("pay.usp_payslip_status_set", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, ids=ids_json, action=action)["changed"]


def payslip_history(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int) -> list[Row]:
    return db.call("pay.usp_payslip_history", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=permission_code, id=id)


def account_summary(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                    employee_id: int | None) -> tuple[Row, list[Row]]:
    head, accounts = db.call_sets("pay.usp_employee_account_summary", company_id=company_id,
                                  actor_user_id=actor_user_id, permission_code=permission_code, employee_id=employee_id)
    return head[0], accounts


# --------------------------------------------------------------------------- final settlement

def final_settlement_inputs(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int):
    sets = db.call_sets("pay.usp_final_settlement_inputs", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, id=id)
    return sets


def final_settlement_save(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int,
                          payslip_json: str) -> Row:
    return db.call_sets("pay.usp_final_settlement_save", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, id=id, payslip=payslip_json)[-1][0]
