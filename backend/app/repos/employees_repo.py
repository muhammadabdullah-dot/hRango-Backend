"""Employee records data access. The only layer that knows the hr procedure names and parameters."""
from datetime import date
from decimal import Decimal
from typing import Any

from app.core.db import Db

_EMPLOYEE_FIELDS = ("code", "first_name", "last_name", "parent_name", "gender", "marital_status", "religion",
                    "nationality", "date_of_birth", "email", "phone_1", "phone_2", "home_address", "home_city_id",
                    "branch_id", "location_id",
                    "area_id", "department_id", "division_id", "cost_center_id", "designation_id", "job_title_id",
                    "grade_id", "job_level_id", "employee_group_id", "employment_type_id", "line_manager_id",
                    "final_authority_id", "status", "salary_frequency", "joining_date", "probation_end_date",
                    "confirmation_date")


def list_employees(db: Db, company_id: int, actor_user_id: int, permission_code: str, filters: dict[str, Any],
                   page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("hr.usp_employee_list", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, **filters, page=page, page_size=page_size)
    return total[0]["total"], rows


def employee_summary(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                     filters: dict[str, Any]) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_summary", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, **filters)


def lookup_employees(db: Db, company_id: int, actor_user_id: int, permission_code: str, search: str | None,
                     branch_id: int | None, department_id: int | None, include_inactive: bool,
                     page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("hr.usp_employee_lookup", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, search=search, branch_id=branch_id,
                               department_id=department_id, include_inactive=include_inactive, page=page,
                               page_size=page_size)
    return total[0]["total"], rows


def get_employee(db: Db, company_id: int, actor_user_id: int, employee_id: int, permission_code: str) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_get", company_id=company_id, actor_user_id=actor_user_id, id=employee_id,
                       permission_code=permission_code)


def save_employee(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int | None,
                  fields: dict[str, Any], set_cnic: bool, cnic: str | None,
                  row_version: bytes | None) -> dict[str, Any]:
    params = {k: fields.get(k) for k in _EMPLOYEE_FIELDS}
    return db.call_one("hr.usp_employee_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=employee_id, **params, set_cnic=set_cnic, cnic=cnic,
                       row_version=row_version)


def save_identity(db: Db, company_id: int, actor_user_id: int, employee_id: int, cnic: str | None,
                  row_version: bytes) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_identity_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=employee_id, cnic=cnic, row_version=row_version)


def set_active(db: Db, company_id: int, actor_user_id: int, employee_id: int, active: bool,
               row_version: bytes) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_active_set", company_id=company_id, actor_user_id=actor_user_id,
                       id=employee_id, active=active, row_version=row_version)


def list_periods(db: Db, company_id: int, actor_user_id: int, employee_id: int) -> list[dict[str, Any]]:
    return db.call("hr.usp_employment_period_list", company_id=company_id, actor_user_id=actor_user_id,
                   employee_id=employee_id)


def save_period(db: Db, company_id: int, actor_user_id: int, employee_id: int, period_id: int | None,
                joining_date: date, confirmation_date: date | None, probation_end_date: date | None,
                end_date: date | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("hr.usp_employment_period_save", company_id=company_id, actor_user_id=actor_user_id,
                       employee_id=employee_id, id=period_id, joining_date=joining_date,
                       confirmation_date=confirmation_date, probation_end_date=probation_end_date, end_date=end_date,
                       row_version=row_version)


def list_history(db: Db, company_id: int, actor_user_id: int, employee_id: int) -> list[dict[str, Any]]:
    return db.call("hr.usp_employee_history_list", company_id=company_id, actor_user_id=actor_user_id,
                   employee_id=employee_id)


def list_changes(db: Db, company_id: int, actor_user_id: int, employee_id: int, page: int,
                 page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("hr.usp_employee_change_list", company_id=company_id, actor_user_id=actor_user_id,
                               employee_id=employee_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def list_salary(db: Db, company_id: int, actor_user_id: int, employee_id: int) -> list[dict[str, Any]]:
    return db.call("hr.usp_employee_salary_list", company_id=company_id, actor_user_id=actor_user_id,
                   employee_id=employee_id)


def save_salary(db: Db, company_id: int, actor_user_id: int, employee_id: int, salary_id: int | None,
                effective_date: date, amount: Decimal, change_type: str | None, change_value: Decimal | None,
                source: str, remarks: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_salary_save", company_id=company_id, actor_user_id=actor_user_id,
                       employee_id=employee_id, id=salary_id, effective_date=effective_date, amount=amount,
                       change_type=change_type, change_value=change_value, source=source, remarks=remarks,
                       row_version=row_version)


def delete_salary(db: Db, company_id: int, actor_user_id: int, employee_id: int, salary_id: int,
                  row_version: bytes) -> None:
    db.call("hr.usp_employee_salary_delete", company_id=company_id, actor_user_id=actor_user_id,
            employee_id=employee_id, id=salary_id, row_version=row_version)


def list_bank_accounts(db: Db, company_id: int, actor_user_id: int, employee_id: int) -> list[dict[str, Any]]:
    return db.call("hr.usp_employee_bank_account_list", company_id=company_id, actor_user_id=actor_user_id,
                   employee_id=employee_id)


def save_bank_account(db: Db, company_id: int, actor_user_id: int, employee_id: int, account_id: int | None,
                      f: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_bank_account_save", company_id=company_id, actor_user_id=actor_user_id,
                       employee_id=employee_id, id=account_id, account_holder=f.get("account_holder"),
                       account_number=f["account_number"], bank_name=f["bank_name"], branch_name=f.get("branch_name"),
                       branch_code=f.get("branch_code"), tax_payer_id=f.get("tax_payer_id"),
                       is_primary=f.get("is_primary", False), row_version=row_version)


def delete_bank_account(db: Db, company_id: int, actor_user_id: int, employee_id: int, account_id: int,
                        row_version: bytes) -> None:
    db.call("hr.usp_employee_bank_account_delete", company_id=company_id, actor_user_id=actor_user_id,
            employee_id=employee_id, id=account_id, row_version=row_version)


# ---------------------------------------------------------------- profile

def save_photo(db: Db, company_id: int, actor_user_id: int, employee_id: int, file_id: int | None,
               row_version: bytes) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_photo_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=employee_id, file_id=file_id, row_version=row_version)


# Profile tab -> (procedure stem, the fields its _save procedure takes).
TABS: dict[str, tuple[str, tuple[str, ...]]] = {
    "emergency_contacts": ("emergency_contact", ("name", "relation", "phone", "alt_phone", "address", "is_primary")),
    "dependents": ("dependent", ("first_name", "last_name", "relation", "occupation", "date_of_birth")),
    "skills": ("skill", ("skill_title", "skill_level")),
    "education": ("education", ("title", "institute", "from_date", "to_date", "is_in_process", "file_id")),
    "experience": ("experience", ("company_name", "job_title", "from_date", "to_date")),
    "contracts": ("contract", ("contract_type", "duration_months", "from_date", "to_date", "file_id", "remarks")),
    "documents": ("document", ("document_type", "title", "document_number", "issue_date", "expiry_date", "file_id",
                               "remarks")),
}


def list_tab(db: Db, tab: str, company_id: int, actor_user_id: int, employee_id: int) -> list[dict[str, Any]]:
    return db.call(f"hr.usp_employee_{TABS[tab][0]}_list", company_id=company_id, actor_user_id=actor_user_id,
                   employee_id=employee_id)


def save_tab(db: Db, tab: str, company_id: int, actor_user_id: int, employee_id: int, row_id: int | None,
             fields: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    stem, names = TABS[tab]
    return db.call_one(f"hr.usp_employee_{stem}_save", company_id=company_id, actor_user_id=actor_user_id,
                       employee_id=employee_id, id=row_id, **{k: fields.get(k) for k in names},
                       row_version=row_version)


def delete_tab(db: Db, tab: str, company_id: int, actor_user_id: int, employee_id: int, row_id: int,
               row_version: bytes) -> None:
    db.call(f"hr.usp_employee_{TABS[tab][0]}_delete", company_id=company_id, actor_user_id=actor_user_id,
            employee_id=employee_id, id=row_id, row_version=row_version)


def document_expiry_notify(db: Db, company_id: int, days_ahead: int) -> int:
    return db.call_one("hr.usp_employee_document_expiry_notify", company_id=company_id, days_ahead=days_ahead)["reported"]


# ---------------------------------------------------------------- Update Information requests

def list_update_requests(db: Db, company_id: int, actor_user_id: int, employee_id: int | None, status: str | None,
                         page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("hr.usp_employee_change_request_list", company_id=company_id,
                               actor_user_id=actor_user_id, employee_id=employee_id, status=status, page=page,
                               page_size=page_size)
    return total[0]["total"], rows


def get_update_request(db: Db, company_id: int, actor_user_id: int, request_id: int) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_change_request_get", company_id=company_id, actor_user_id=actor_user_id,
                       id=request_id)


def submit_update_request(db: Db, company_id: int, actor_user_id: int, employee_id: int, changes: str,
                          remarks: str | None) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_change_request_submit", company_id=company_id, actor_user_id=actor_user_id,
                       employee_id=employee_id, changes=changes, remarks=remarks)


def decide_update_request(db: Db, company_id: int, actor_user_id: int, request_id: int, decision: str,
                          remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("hr.usp_employee_change_request_decide", company_id=company_id, actor_user_id=actor_user_id,
                       id=request_id, decision=decision, remarks=remarks, row_version=row_version)
