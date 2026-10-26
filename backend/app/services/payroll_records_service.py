"""Vouchers, final settlement, balances, salary revision and leave encashment rules.

Nobody changes their own pay: a write that targets the caller's own employee record is refused (403
OWN_PAY_RECORD) whatever their role, so an own-scope grant can never be used to raise one's own pay."""
import csv
import io
import json
import re
from collections.abc import Callable
from datetime import date
from typing import Any

from pydantic import ValidationError

from app.core import files
from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import files_repo
from app.repos import payroll_records_repo as repo
from app.schemas.payroll_records import AccountImportRow, OpeningBalanceImportRow, SalaryImportRow
from app.services import payroll_run_service

Row = dict[str, Any]


def _codes(screen: str) -> dict[str, str]:
    return {a: f"payroll.{screen}.{a}" for a in ("view", "create", "edit", "delete", "import", "approve", "reject",
                                                 "verify", "process", "close")}


VOUCHER, FS, OPENING, ACCOUNTS, REVISION, ENCASH = (_codes("vouchers"), _codes("final_settlement"),
                                                    _codes("opening_balances"), _codes("employee_accounts"),
                                                    _codes("salary_revision"), _codes("leave_encashment"))


def _not_mine(ctx: RequestContext, employee_id) -> None:
    if ctx.employee_id is not None and employee_id is not None and int(employee_id) == ctx.employee_id:
        raise AppError(403, "OWN_PAY_RECORD", "You cannot change your own pay records.")


def _invalid(field: str, message: str) -> AppError:
    return AppError(422, "VALIDATION_FAILED", message, {field: message})


IMPORT_TYPES = ("csv", "txt")


def _header_key(header: str) -> str:
    """"Employee Code", "employee_code" and "employeeCode" all become employee_code."""
    snake = re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", header.strip().lstrip("\ufeff"))
    return re.sub(r"[^a-z0-9]+", "_", snake.lower()).strip("_")


def _rows_from_file(db: Db, ctx: RequestContext, file_id: int, model) -> tuple[list, list[int], list[tuple[int, str]]]:
    """Reads an uploaded CSV sheet (first line: column names, as in the sample import). Returns the rows that
    parse, their row numbers (the first data line is row 1, as the import procedures count) and the rows that
    do not, with why."""
    stored = files_repo.get(db, ctx.company_id, file_id)
    if stored is None:
        raise _invalid("fileId", "The file was not found. Upload it again.")
    if stored["extension"] not in IMPORT_TYPES:
        raise _invalid("fileId", "Save the sheet as CSV (comma separated values) and upload that.")
    raw = files.path_of(stored["storage_path"]).read_bytes()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
    reader = csv.DictReader(io.StringIO(text))
    rows, numbers, errors = [], [], []
    for n, record in enumerate(reader, start=1):
        data = {_header_key(k): v.strip() for k, v in record.items() if k and isinstance(v, str) and v.strip()}
        if not data:
            continue
        try:
            rows.append(model.model_validate(data))
            numbers.append(n)
        except ValidationError as exc:
            problems = "; ".join(f"{'.'.join(str(p) for p in e['loc']) or 'row'}: {e['msg']}" for e in exc.errors())
            errors.append((n, problems))
    if not rows and not errors:
        raise _invalid("fileId", "The file has no rows under its header line.")
    return rows, numbers, errors


def _import(db: Db, ctx: RequestContext, body, model,
            run: Callable[[str], tuple[int, list[Row]]]) -> tuple[int, list[str]]:
    """Rows sent in the body, or read from an uploaded CSV (body.file_id). Rows that do not resolve are reported
    and skipped; the rest are added together."""
    if body.file_id is not None:
        rows, numbers, errors = _rows_from_file(db, ctx, body.file_id, model)
    else:
        rows, numbers, errors = body.rows, list(range(1, len(body.rows) + 1)), []
    created = 0
    if rows:
        created, failed = run(json.dumps([r.model_dump(by_alias=True, mode="json") for r in rows]))
        errors += [(numbers[e["row_no"] - 1], e["error"]) for e in failed]
    return created, [f"Row {n}: {message}" for n, message in sorted(errors)]


# --------------------------------------------------------------------------- vouchers

def list_vouchers(db: Db, ctx: RequestContext, f: dict, page: int, page_size: int):
    return repo.list_vouchers(db, ctx.company_id, ctx.user_id, VOUCHER["view"], f, page, page_size)


def get_voucher(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_voucher(db, ctx.company_id, ctx.user_id, VOUCHER["view"], id)


def save_voucher(db: Db, ctx: RequestContext, id: int | None, body, row_version: bytes | None) -> Row:
    _not_mine(ctx, body.employee_id)
    if body.voucher_date > date.today():
        raise _invalid("voucherDate", "The voucher date cannot be in the future.")
    return repo.save_voucher(db, ctx.company_id, ctx.user_id, VOUCHER["create" if id is None else "edit"], id, body,
                             row_version)


def delete_voucher(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_voucher(db, ctx.company_id, ctx.user_id, VOUCHER["delete"], id, row_version)


def decide_voucher(db: Db, ctx: RequestContext, id: int, action: str, remarks, row_version: bytes) -> Row:
    return repo.decide_voucher(db, ctx.company_id, ctx.user_id, VOUCHER[action], id, action, remarks, row_version)


# --------------------------------------------------------------------------- final settlement

def list_final_settlements(db: Db, ctx: RequestContext, f: dict, page: int, page_size: int):
    return repo.list_final_settlements(db, ctx.company_id, ctx.user_id, FS["view"], f, page, page_size)


def get_final_settlement(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_final_settlement(db, ctx.company_id, ctx.user_id, FS["view"], id)


def recalculate_final_settlement(db: Db, ctx: RequestContext, id: int) -> Row:
    return payroll_run_service.calculate_final_settlement(db, ctx, id, FS["process"])


def close_final_settlement(db: Db, ctx: RequestContext, id: int, row_version: bytes,
                           file_id: int | None = None) -> Row:
    row = repo.get_final_settlement(db, ctx.company_id, ctx.user_id, FS["close"], id)
    _not_mine(ctx, row["employee_id"])
    return repo.close_final_settlement(db, ctx.company_id, ctx.user_id, FS["close"], id, row_version, file_id)


def final_settlement_payslip(db: Db, ctx: RequestContext, id: int):
    row = repo.get_final_settlement(db, ctx.company_id, ctx.user_id, FS["view"], id)
    if row["payslip_id"] is None:
        raise AppError(404, "NOT_FOUND", "This settlement has not been worked out yet.")
    return payroll_run_service.get_payslip(db, ctx, row["payslip_id"])


# --------------------------------------------------------------------------- opening balances

def list_opening_balances(db: Db, ctx: RequestContext, f: dict, page: int, page_size: int):
    return repo.list_opening_balances(db, ctx.company_id, ctx.user_id, OPENING["view"], f, page, page_size)


def opening_balances_of(db: Db, ctx: RequestContext, employee_id: int):
    return repo.opening_balances_of(db, ctx.company_id, ctx.user_id, OPENING["view"], employee_id)


def get_opening_balance(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_opening_balance(db, ctx.company_id, ctx.user_id, OPENING["view"], id)


def save_opening_balance(db: Db, ctx: RequestContext, id: int | None, body, row_version: bytes | None) -> Row:
    _not_mine(ctx, body.employee_id)
    if body.amount == 0:
        raise _invalid("amount", "The amount cannot be zero.")
    return repo.save_opening_balance(db, ctx.company_id, ctx.user_id, OPENING["create" if id is None else "edit"], id,
                                     body, row_version)


def delete_opening_balance(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_opening_balance(db, ctx.company_id, ctx.user_id, OPENING["delete"], id, row_version)


def import_opening_balances(db: Db, ctx: RequestContext, body) -> tuple[int, list[str]]:
    return _import(db, ctx, body, OpeningBalanceImportRow,
                   lambda rows: repo.import_opening_balances(db, ctx.company_id, ctx.user_id, OPENING["import"], rows))


# --------------------------------------------------------------------------- employee accounts

def list_account_entries(db: Db, ctx: RequestContext, f: dict, page: int, page_size: int):
    return repo.list_account_entries(db, ctx.company_id, ctx.user_id, ACCOUNTS["view"], f, page, page_size)


def get_account_entry(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_account_entry(db, ctx.company_id, ctx.user_id, ACCOUNTS["view"], id)


def save_account_entry(db: Db, ctx: RequestContext, id: int | None, body, row_version: bytes | None) -> Row:
    _not_mine(ctx, body.employee_id)
    credit, debit = (body.amount, 0) if body.direction == "credit" else (0, body.amount)
    return repo.save_account_entry(db, ctx.company_id, ctx.user_id, ACCOUNTS["create" if id is None else "edit"], id,
                                   body, credit, debit, row_version)


def delete_account_entry(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_account_entry(db, ctx.company_id, ctx.user_id, ACCOUNTS["delete"], id, row_version)


def import_account_entries(db: Db, ctx: RequestContext, body) -> tuple[int, list[str]]:
    return _import(db, ctx, body, AccountImportRow,
                   lambda rows: repo.import_account_entries(db, ctx.company_id, ctx.user_id, ACCOUNTS["import"], rows))


def account_statement(db: Db, ctx: RequestContext, employee_id, account_type_id, from_month, to_month, page: int,
                      page_size: int):
    return repo.account_statement(db, ctx.company_id, ctx.user_id, ACCOUNTS["view"], employee_id, account_type_id,
                                  from_month, to_month, page, page_size)


# --------------------------------------------------------------------------- salary revision

def list_revisions(db: Db, ctx: RequestContext, f: dict, page: int, page_size: int):
    return repo.list_revisions(db, ctx.company_id, ctx.user_id, REVISION["view"], f, page, page_size)


def get_revision(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_revision(db, ctx.company_id, ctx.user_id, REVISION["view"], id)


def current_salary(db: Db, ctx: RequestContext, employee_id: int, as_of) -> Row:
    return repo.current_salary(db, ctx.company_id, ctx.user_id, REVISION["view"], employee_id, as_of)


def save_revision(db: Db, ctx: RequestContext, id: int | None, body, row_version: bytes | None) -> Row:
    _not_mine(ctx, body.employee_id)
    if body.change_type == "percent" and body.change_value <= -100:
        raise _invalid("changeValue", "A percentage cut cannot be 100% or more.")
    if body.change_value == 0:
        raise _invalid("changeValue", "The change cannot be zero.")
    return repo.save_revision(db, ctx.company_id, ctx.user_id, REVISION["create" if id is None else "edit"], id, body,
                              row_version)


def delete_revision(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    row = repo.get_revision(db, ctx.company_id, ctx.user_id, REVISION["delete"], id)
    _not_mine(ctx, row["employee_id"])
    repo.delete_revision(db, ctx.company_id, ctx.user_id, REVISION["delete"], id, row_version)


def import_revisions(db: Db, ctx: RequestContext, body) -> tuple[int, list[str]]:
    return _import(db, ctx, body, SalaryImportRow,
                   lambda rows: repo.import_revisions(db, ctx.company_id, ctx.user_id, REVISION["import"], rows))


# --------------------------------------------------------------------------- leave encashment

def list_encashments(db: Db, ctx: RequestContext, f: dict, page: int, page_size: int):
    return repo.list_encashments(db, ctx.company_id, ctx.user_id, ENCASH["view"], f, page, page_size)


def get_encashment(db: Db, ctx: RequestContext, id: int):
    return repo.get_encashment(db, ctx.company_id, ctx.user_id, ENCASH["view"], id)


def save_encashment(db: Db, ctx: RequestContext, id: int | None, body, row_version: bytes | None):
    if not body.all_employees:
        if not body.employee_ids:
            raise _invalid("employeeIds", "Pick the employees, or All Employees.")
        for e in body.employee_ids:
            _not_mine(ctx, e)
    return repo.save_encashment(db, ctx.company_id, ctx.user_id, ENCASH["create" if id is None else "edit"], id, body,
                                json.dumps(body.employee_ids), row_version)


def delete_encashment(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_encashment(db, ctx.company_id, ctx.user_id, ENCASH["delete"], id, row_version)
