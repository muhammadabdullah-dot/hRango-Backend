"""Employee record rules. Scope (who may reach whom) is applied in the procedures through
auth.fn_visible_employees with the code the endpoint required; placement checks, duplicates,
head-count limits and line-manager cycles are there too. Field formats live here."""
import json
import re
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, forbidden, invalid
from app.core.permissions import CODES
from app.middlewares.auth import RequestContext
from app.repos import auth_repo, employees_repo

_CNIC = re.compile(r"^\d{13}$")


def normalise_cnic(value: str | None) -> str | None:
    """A Pakistani CNIC: 13 digits, stored as 12345-1234567-1. Blank means none."""
    if value is None or not value.strip():
        return None
    digits = re.sub(r"[\s-]", "", value)
    if not _CNIC.match(digits):
        raise invalid("A CNIC has 13 digits, e.g. 35202-1234567-1.", "cnic")
    return f"{digits[:5]}-{digits[5:12]}-{digits[12]}"


def _holds(db: Db, ctx: RequestContext, code: str) -> bool:
    return bool(auth_repo.permission_check(db, ctx.company_id, ctx.user_id, code)["allowed"])


def list_employees(db: Db, ctx: RequestContext, filters: dict[str, Any], page: int, page_size: int):
    return employees_repo.list_employees(db, ctx.company_id, ctx.user_id, "employees.directory.view", filters,
                                         page, page_size)


def employee_summary(db: Db, ctx: RequestContext, filters: dict[str, Any]) -> dict[str, Any]:
    return employees_repo.employee_summary(db, ctx.company_id, ctx.user_id, "employees.directory.view", filters)


def lookup(db: Db, ctx: RequestContext, permission: str, search: str | None, branch_id: int | None,
           department_id: int | None, include_inactive: bool, page: int,
           page_size: int) -> tuple[int, list[dict[str, Any]]]:
    """Picker: the employees the caller reaches through `permission` (default employees.directory.view).
    A request screen passes its own code, e.g. requests.leave.create, to list whom the user may file for."""
    if permission not in CODES:
        raise invalid("This is not a permission code.", "permission")
    return employees_repo.lookup_employees(db, ctx.company_id, ctx.user_id, permission, search, branch_id,
                                           department_id, include_inactive, page, page_size)


def get_employee(db: Db, ctx: RequestContext, employee_id: int) -> dict[str, Any]:
    return employees_repo.get_employee(db, ctx.company_id, ctx.user_id, employee_id, "employees.directory.view")


def create_employee(db: Db, ctx: RequestContext, fields: dict[str, Any]) -> dict[str, Any]:
    if fields.get("joining_date") is None:
        raise invalid("Joining date is required.", "joiningDate")
    if fields.get("status") not in ("active", "probation"):
        raise invalid("A new employee starts as active or on probation.", "status")
    cnic = normalise_cnic(fields.get("cnic"))
    if cnic is not None and not _holds(db, ctx, "employees.identity.edit"):
        raise forbidden("You may not record CNICs.")
    _check_dates(fields)
    return employees_repo.save_employee(db, ctx.company_id, ctx.user_id, "employees.directory.create", None, fields,
                                        cnic is not None, cnic, None)


def update_employee(db: Db, ctx: RequestContext, employee_id: int, fields: dict[str, Any],
                    row_version: bytes) -> dict[str, Any]:
    if fields.get("line_manager_id") == employee_id:
        raise invalid("An employee cannot report to themselves.", "lineManagerId")
    _check_dates(fields)
    return employees_repo.save_employee(db, ctx.company_id, ctx.user_id, "employees.directory.edit", employee_id,
                                        fields, False, None, row_version)


def save_identity(db: Db, ctx: RequestContext, employee_id: int, cnic: str | None, row_version: bytes) -> dict[str, Any]:
    return employees_repo.save_identity(db, ctx.company_id, ctx.user_id, employee_id, normalise_cnic(cnic), row_version)


def set_active(db: Db, ctx: RequestContext, employee_id: int, active: bool, row_version: bytes) -> dict[str, Any]:
    if not active and ctx.employee_id == employee_id:
        raise forbidden("You cannot switch off your own record.")
    return employees_repo.set_active(db, ctx.company_id, ctx.user_id, employee_id, active, row_version)


def list_periods(db: Db, ctx: RequestContext, employee_id: int) -> list[dict[str, Any]]:
    return employees_repo.list_periods(db, ctx.company_id, ctx.user_id, employee_id)


def save_period(db: Db, ctx: RequestContext, employee_id: int, period_id: int | None, f: dict[str, Any],
                row_version: bytes | None) -> dict[str, Any]:
    if f.get("end_date") is not None and f["end_date"] < f["joining_date"]:
        raise invalid("The end date is before the joining date.", "endDate")
    return employees_repo.save_period(db, ctx.company_id, ctx.user_id, employee_id, period_id, f["joining_date"],
                                      f.get("confirmation_date"), f.get("probation_end_date"), f.get("end_date"),
                                      row_version)


def list_history(db: Db, ctx: RequestContext, employee_id: int) -> list[dict[str, Any]]:
    return employees_repo.list_history(db, ctx.company_id, ctx.user_id, employee_id)


def list_changes(db: Db, ctx: RequestContext, employee_id: int, page: int, page_size: int):
    return employees_repo.list_changes(db, ctx.company_id, ctx.user_id, employee_id, page, page_size)


def list_salary(db: Db, ctx: RequestContext, employee_id: int) -> list[dict[str, Any]]:
    return employees_repo.list_salary(db, ctx.company_id, ctx.user_id, employee_id)


def save_salary(db: Db, ctx: RequestContext, employee_id: int, salary_id: int | None, f: dict[str, Any],
                row_version: bytes | None) -> dict[str, Any]:
    if (f.get("change_type") is None) != (f.get("change_value") is None):
        raise invalid("Give the change type and its value together.", "changeValue")
    return employees_repo.save_salary(db, ctx.company_id, ctx.user_id, employee_id, salary_id, f["effective_date"],
                                      f["amount"], f.get("change_type"), f.get("change_value"), f["source"],
                                      f.get("remarks"), row_version)


def delete_salary(db: Db, ctx: RequestContext, employee_id: int, salary_id: int, row_version: bytes) -> None:
    employees_repo.delete_salary(db, ctx.company_id, ctx.user_id, employee_id, salary_id, row_version)


def list_bank_accounts(db: Db, ctx: RequestContext, employee_id: int) -> list[dict[str, Any]]:
    return employees_repo.list_bank_accounts(db, ctx.company_id, ctx.user_id, employee_id)


def save_bank_account(db: Db, ctx: RequestContext, employee_id: int, account_id: int | None, f: dict[str, Any],
                      row_version: bytes | None) -> dict[str, Any]:
    return employees_repo.save_bank_account(db, ctx.company_id, ctx.user_id, employee_id, account_id, f, row_version)


def delete_bank_account(db: Db, ctx: RequestContext, employee_id: int, account_id: int, row_version: bytes) -> None:
    employees_repo.delete_bank_account(db, ctx.company_id, ctx.user_id, employee_id, account_id, row_version)


# ---------------------------------------------------------------- profile

def save_photo(db: Db, ctx: RequestContext, employee_id: int, file_id: int | None, row_version: bytes) -> dict[str, Any]:
    return employees_repo.save_photo(db, ctx.company_id, ctx.user_id, employee_id, file_id, row_version)


def list_tab(db: Db, ctx: RequestContext, tab: str, employee_id: int) -> list[dict[str, Any]]:
    return employees_repo.list_tab(db, tab, ctx.company_id, ctx.user_id, employee_id)


def save_tab(db: Db, ctx: RequestContext, tab: str, employee_id: int, row_id: int | None, f: dict[str, Any],
             row_version: bytes | None) -> dict[str, Any]:
    start, end = f.get("from_date"), f.get("to_date")
    if start is not None and end is not None and end < start:
        raise invalid("The end date is before the start date.", "toDate")
    if tab == "education" and f.get("is_in_process") and end is not None:
        raise invalid("A course still in process has no end date.", "toDate")
    if tab == "documents" and f.get("issue_date") and f.get("expiry_date") and f["expiry_date"] < f["issue_date"]:
        raise invalid("The expiry date is before the issue date.", "expiryDate")
    if tab == "dependents" and f.get("date_of_birth") and f["date_of_birth"] > date.today():
        raise invalid("Date of birth is in the future.", "dateOfBirth")
    return employees_repo.save_tab(db, tab, ctx.company_id, ctx.user_id, employee_id, row_id, f, row_version)


def delete_tab(db: Db, ctx: RequestContext, tab: str, employee_id: int, row_id: int, row_version: bytes) -> None:
    employees_repo.delete_tab(db, tab, ctx.company_id, ctx.user_id, employee_id, row_id, row_version)


def document_expiry_notify(db: Db, company_id: int, days_ahead: int = 30) -> int:
    """For the nightly job: tells employees about documents expiring within `days_ahead` days, once each."""
    return employees_repo.document_expiry_notify(db, company_id, days_ahead)


# ---------------------------------------------------------------- Update Information requests

def list_update_requests(db: Db, ctx: RequestContext, employee_id: int | None, status: str | None, page: int,
                         page_size: int):
    return employees_repo.list_update_requests(db, ctx.company_id, ctx.user_id, employee_id, status, page, page_size)


def get_update_request(db: Db, ctx: RequestContext, request_id: int) -> dict[str, Any]:
    return employees_repo.get_update_request(db, ctx.company_id, ctx.user_id, request_id)


def submit_update_request(db: Db, ctx: RequestContext, employee_id: int, changes: dict[str, Any],
                          remarks: str | None) -> dict[str, Any]:
    """`changes` holds only the fields the employee sent (snake_case, JSON-ready values)."""
    if not changes:
        raise invalid("Give at least one detail to change.", "changes")
    dob = changes.get("date_of_birth")
    if dob is not None and date.fromisoformat(dob) > date.today():
        raise invalid("Date of birth is in the future.", "dateOfBirth")
    return employees_repo.submit_update_request(db, ctx.company_id, ctx.user_id, employee_id, json.dumps(changes),
                                                remarks)


def decide_update_request(db: Db, ctx: RequestContext, request_id: int, decision: str, remarks: str | None,
                          row_version: bytes) -> dict[str, Any]:
    return employees_repo.decide_update_request(db, ctx.company_id, ctx.user_id, request_id, decision, remarks,
                                                row_version)


def _check_dates(f: dict[str, Any]) -> None:
    dob = f.get("date_of_birth")
    if dob is not None and dob > date.today():
        raise invalid("Date of birth is in the future.", "dateOfBirth")
    joining = f.get("joining_date")
    if joining is not None and dob is not None and joining <= dob:
        raise AppError(422, "VALIDATION_FAILED", "Joining date must be after the date of birth.",
                       {"joiningDate": "Joining date must be after the date of birth."})
