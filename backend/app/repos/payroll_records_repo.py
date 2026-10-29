"""Vouchers, final settlement, balances, salary revision, leave encashment: data access."""
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def _page(db: Db, proc: str, **params) -> tuple[int, list[Row]]:
    total, rows = db.call_sets(proc, **params)
    return total[0]["total"], rows


def _import(db: Db, proc: str, **params) -> tuple[int, list[Row]]:
    created, errors = db.call_sets(proc, **params)
    return created[0]["created"], errors


# --------------------------------------------------------------------------- vouchers

def list_vouchers(db: Db, company_id: int, actor_user_id: int, code: str, f: dict, page: int, page_size: int):
    return _page(db, "pay.usp_voucher_list", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
                 **f, page=page, page_size=page_size)


def get_voucher(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> Row:
    return db.call_one("pay.usp_voucher_get", company_id=company_id, actor_user_id=actor_user_id, permission_code=code, id=id)


def save_voucher(db: Db, company_id: int, actor_user_id: int, code: str, id: int | None, body,
                 row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_voucher_save", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
                       id=id, employee_id=body.employee_id, voucher_no=body.voucher_no, voucher_type=body.voucher_type,
                       voucher_date=body.voucher_date, currency=body.currency, amount=body.amount,
                       payment_method=body.payment_method, purpose=body.purpose, notes=body.notes, file_id=body.file_id,
                       requested_by_id=body.requested_by_id, row_version=row_version)


def delete_voucher(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes) -> None:
    db.call("pay.usp_voucher_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code, id=id,
            row_version=row_version)


def decide_voucher(db: Db, company_id: int, actor_user_id: int, code: str, id: int, action: str, remarks,
                   row_version: bytes) -> Row:
    return db.call_one("pay.usp_voucher_decide", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id, action=action, remarks=remarks, row_version=row_version)


# --------------------------------------------------------------------------- final settlement

def list_final_settlements(db: Db, company_id: int, actor_user_id: int, code: str, f: dict, page: int, page_size: int):
    return _page(db, "pay.usp_final_settlement_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=code, **f, page=page, page_size=page_size)


def get_final_settlement(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> Row:
    return db.call_one("pay.usp_final_settlement_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id)


def close_final_settlement(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes,
                           file_id: int | None = None) -> Row:
    return db.call_one("pay.usp_final_settlement_close", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id, row_version=row_version, file_id=file_id)


# --------------------------------------------------------------------------- opening balances

def list_opening_balances(db: Db, company_id: int, actor_user_id: int, code: str, f: dict, page: int, page_size: int):
    return _page(db, "pay.usp_opening_balance_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=code, **f, page=page, page_size=page_size)


def opening_balances_of(db: Db, company_id: int, actor_user_id: int, code: str, employee_id: int) -> tuple[Row, list[Row]]:
    head, rows = db.call_sets("pay.usp_opening_balance_employee", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, employee_id=employee_id)
    return head[0], rows


def get_opening_balance(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> Row:
    return db.call_one("pay.usp_opening_balance_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id)


def save_opening_balance(db: Db, company_id: int, actor_user_id: int, code: str, id: int | None, body,
                         row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_opening_balance_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id, employee_id=body.employee_id, balance_month=body.balance_month,
                       pay_item_id=body.pay_item_id, amount=body.amount, is_taxable=body.is_taxable, kind=body.kind,
                       description=body.description, row_version=row_version)


def delete_opening_balance(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes) -> None:
    db.call("pay.usp_opening_balance_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=id, row_version=row_version)


def import_opening_balances(db: Db, company_id: int, actor_user_id: int, code: str, rows_json: str):
    return _import(db, "pay.usp_opening_balance_import", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=code, rows=rows_json)


# --------------------------------------------------------------------------- employee accounts

def list_account_entries(db: Db, company_id: int, actor_user_id: int, code: str, f: dict, page: int, page_size: int):
    return _page(db, "pay.usp_employee_account_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=code, **f, page=page, page_size=page_size)


def get_account_entry(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> Row:
    return db.call_one("pay.usp_employee_account_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id)


def save_account_entry(db: Db, company_id: int, actor_user_id: int, code: str, id: int | None, body, credit, debit,
                       row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_employee_account_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id, employee_id=body.employee_id, account_type_id=body.account_type_id,
                       entry_month=body.entry_month, credit=credit, debit=debit, is_processed=body.is_processed,
                       description=body.description, row_version=row_version)


def delete_account_entry(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes) -> None:
    db.call("pay.usp_employee_account_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=id, row_version=row_version)


def import_account_entries(db: Db, company_id: int, actor_user_id: int, code: str, rows_json: str):
    return _import(db, "pay.usp_employee_account_import", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=code, rows=rows_json)


def account_statement(db: Db, company_id: int, actor_user_id: int, code: str, employee_id, account_type_id, from_month,
                      to_month, page: int, page_size: int):
    return _page(db, "pay.usp_account_statement", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=code, employee_id=employee_id, account_type_id=account_type_id, from_month=from_month,
                 to_month=to_month, page=page, page_size=page_size)


# --------------------------------------------------------------------------- salary revision

def list_revisions(db: Db, company_id: int, actor_user_id: int, code: str, f: dict, page: int, page_size: int):
    return _page(db, "pay.usp_salary_revision_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=code, **f, page=page, page_size=page_size)


def get_revision(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> Row:
    return db.call_one("pay.usp_salary_revision_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id)


def current_salary(db: Db, company_id: int, actor_user_id: int, code: str, employee_id: int, as_of) -> Row:
    return db.call_one("pay.usp_salary_current", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, employee_id=employee_id, as_of=as_of)


def save_revision(db: Db, company_id: int, actor_user_id: int, code: str, id: int | None, body,
                  row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_salary_revision_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id, employee_id=body.employee_id, effective_date=body.effective_date,
                       change_type=body.change_type, change_value=body.change_value, source="revision",
                       row_version=row_version)


def delete_revision(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes) -> None:
    db.call("pay.usp_salary_revision_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=id, row_version=row_version)


def import_revisions(db: Db, company_id: int, actor_user_id: int, code: str, rows_json: str):
    return _import(db, "pay.usp_salary_revision_import", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=code, rows=rows_json)


def revision_email_get(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> Row:
    return db.call_one("pay.usp_salary_revision_email_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id)


def revision_email_send(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes,
                        mail_enabled: bool, subject: str) -> Row:
    return db.call_one("pay.usp_salary_revision_email_send", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=id, row_version=row_version, mail_enabled=mail_enabled, subject=subject)


# --------------------------------------------------------------------------- leave encashment

def preview_encashment(db: Db, company_id: int, actor_user_id: int, code: str, body, employee_ids_json: str) -> list[Row]:
    return db.call("pay.usp_leave_encashment_preview", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=code, id=body.id, leave_type_id=body.leave_type_id, fiscal_year=body.fiscal_year,
                   all_employees=body.all_employees, employee_ids=employee_ids_json, basis=body.basis,
                   amount_per_leave=body.amount_per_leave)


def list_encashments(db: Db, company_id: int, actor_user_id: int, code: str, f: dict, page: int, page_size: int):
    return _page(db, "pay.usp_leave_encashment_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=code, **f, page=page, page_size=page_size)


def get_encashment(db: Db, company_id: int, actor_user_id: int, code: str, id: int) -> tuple[Row, list[Row]]:
    head, rows = db.call_sets("pay.usp_leave_encashment_get", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, id=id)
    return head[0], rows


def save_encashment(db: Db, company_id: int, actor_user_id: int, code: str, id: int | None, body, employee_ids_json: str,
                    row_version: bytes | None) -> tuple[Row, list[Row]]:
    head, rows = db.call_sets("pay.usp_leave_encashment_save", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, id=id, leave_type_id=body.leave_type_id,
                              fiscal_year=body.fiscal_year, all_employees=body.all_employees,
                              employee_ids=employee_ids_json, mode=body.mode, basis=body.basis,
                              amount_per_leave=body.amount_per_leave, row_version=row_version)
    return head[0], rows


def delete_encashment(db: Db, company_id: int, actor_user_id: int, code: str, id: int, row_version: bytes) -> None:
    db.call("pay.usp_leave_encashment_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=id, row_version=row_version)
