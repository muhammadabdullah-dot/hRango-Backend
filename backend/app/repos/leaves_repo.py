"""Leaves data access. The only layer that knows procedure names and parameters."""
from datetime import date
from typing import Any

from app.core.db import Db


def _page(db: Db, proc: str, **params: Any) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets(proc, **params)
    return total[0]["total"], rows


# --- General settings ------------------------------------------------------------------------------

def get_settings(db: Db, company_id: int) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_settings_get", company_id=company_id)


def save_settings(db: Db, company_id: int, actor_user_id: int, final_approval_by: str, approve_on_status: str,
                  post_deadline: bool, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_settings_save", company_id=company_id, actor_user_id=actor_user_id,
                       final_approval_by=final_approval_by, approve_on_status=approve_on_status,
                       post_deadline=post_deadline, row_version=row_version)


# --- Leave types -----------------------------------------------------------------------------------

def list_types(db: Db, company_id: int, search: str | None, is_active: bool | None,
               page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_type_list", company_id=company_id, search=search, is_active=is_active,
                 page=page, page_size=page_size)


def get_type(db: Db, company_id: int, type_id: int) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_type_get", company_id=company_id, id=type_id)


def save_type(db: Db, company_id: int, actor_user_id: int, type_id: int | None, fields: dict[str, Any],
              experience_slabs: str, short_slabs: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_type_save", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
                       **fields, experience_slabs=experience_slabs, short_slabs=short_slabs, row_version=row_version)


def delete_type(db: Db, company_id: int, actor_user_id: int, type_id: int, row_version: bytes) -> None:
    db.call("lv.usp_leave_type_delete", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
            row_version=row_version)


# --- Leave policies --------------------------------------------------------------------------------

def list_policies(db: Db, company_id: int, search: str | None, kind: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_policy_list", company_id=company_id, search=search, kind=kind,
                 page=page, page_size=page_size)


def get_policy(db: Db, company_id: int, policy_id: int) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_policy_get", company_id=company_id, id=policy_id)


def save_policy(db: Db, company_id: int, actor_user_id: int, policy_id: int | None, title: str, policy_kind: str,
                policy_level: str, allow_half_day: bool, allow_short_leave: bool, is_active: bool, types: str,
                row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_policy_save", company_id=company_id, actor_user_id=actor_user_id, id=policy_id,
                       title=title, policy_kind=policy_kind, policy_level=policy_level, allow_half_day=allow_half_day,
                       allow_short_leave=allow_short_leave, is_active=is_active, types=types,
                       row_version=row_version)


def delete_policy(db: Db, company_id: int, actor_user_id: int, policy_id: int, row_version: bytes) -> None:
    db.call("lv.usp_leave_policy_delete", company_id=company_id, actor_user_id=actor_user_id, id=policy_id,
            row_version=row_version)


def list_enrolled(db: Db, company_id: int, policy_id: int, search: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_policy_employee_list", company_id=company_id, id=policy_id, search=search,
                 page=page, page_size=page_size)


def enrol(db: Db, company_id: int, actor_user_id: int, policy_id: int, employee_ids: str) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_policy_employee_add", company_id=company_id, actor_user_id=actor_user_id,
                       id=policy_id, employee_ids=employee_ids)


def unenrol(db: Db, company_id: int, actor_user_id: int, policy_id: int, employee_id: int) -> None:
    db.call("lv.usp_leave_policy_employee_remove", company_id=company_id, actor_user_id=actor_user_id, id=policy_id,
            employee_id=employee_id)


# --- Balances and ledger ---------------------------------------------------------------------------

def list_balances(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int | None,
                  leave_type_id: int | None, as_of: date | None, search: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_balance_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, employee_id=employee_id, leave_type_id=leave_type_id, as_of=as_of,
                 search=search, page=page, page_size=page_size)


def list_ledger(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int | None,
                leave_type_id: int | None, fiscal_year: int | None, reason: str | None,
                page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_ledger_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, employee_id=employee_id, leave_type_id=leave_type_id,
                 fiscal_year=fiscal_year, reason=reason, page=page, page_size=page_size)


def add_ledger_entry(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int,
                     leave_type_id: int, entry_date: date, days: Any, reason: str, remarks: str | None) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_ledger_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, employee_id=employee_id, leave_type_id=leave_type_id,
                       entry_date=entry_date, days=days, reason=reason, remarks=remarks)


def process_allotment(db: Db, company_id: int, actor_user_id: int, permission_code: str, fiscal_year: int,
                      as_of: date | None, leave_type_id: int | None, employee_id: int | None) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_allotment_process", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, fiscal_year=fiscal_year, as_of=as_of,
                       leave_type_id=leave_type_id, employee_id=employee_id)


def process_carry_forward(db: Db, company_id: int, actor_user_id: int, permission_code: str, from_fiscal_year: int,
                          leave_type_id: int | None, employee_id: int | None) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_carry_forward_process", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, from_fiscal_year=from_fiscal_year,
                       leave_type_id=leave_type_id, employee_id=employee_id)


# --- Leave applications ----------------------------------------------------------------------------

def list_applications(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str,
                      filters: dict[str, Any], page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_application_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, tab=tab, **filters, page=page, page_size=page_size)


def count_applications(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str,
                       filters: dict[str, Any]) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_application_counts", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, tab=tab, **filters)


def get_application(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                    application_id: int) -> dict[str, Any]:
    return db.call_one("lv.usp_leave_application_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=application_id)


# --- Leave encashment ------------------------------------------------------------------------------

def list_encashments(db: Db, company_id: int, actor_user_id: int, permission_code: str, leave_type_id: int | None,
                     fiscal_year: int | None, employee_id: int | None, mode: str | None,
                     page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "lv.usp_leave_encashment_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, leave_type_id=leave_type_id, fiscal_year=fiscal_year,
                 employee_id=employee_id, mode=mode, page=page, page_size=page_size)


def get_encashment(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                   encashment_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    head, lines = db.call_sets("lv.usp_leave_encashment_get", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, id=encashment_id)
    return head[0], lines


def save_encashment(db: Db, company_id: int, actor_user_id: int, permission_code: str, encashment_id: int | None,
                    leave_type_id: int | None, fiscal_year: int | None, encashment_date: date,
                    applies_to_all: bool, employee_ids: str | None, basis: str, amount_per_leave: Any, mode: str,
                    row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    head, lines = db.call_sets("lv.usp_leave_encashment_save", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, id=encashment_id, leave_type_id=leave_type_id,
                               fiscal_year=fiscal_year, encashment_date=encashment_date,
                               applies_to_all=applies_to_all, employee_ids=employee_ids, basis=basis,
                               amount_per_leave=amount_per_leave, mode=mode, row_version=row_version)
    return head[0], lines


def delete_encashment(db: Db, company_id: int, actor_user_id: int, encashment_id: int, row_version: bytes) -> None:
    db.call("lv.usp_leave_encashment_delete", company_id=company_id, actor_user_id=actor_user_id, id=encashment_id,
            row_version=row_version)
