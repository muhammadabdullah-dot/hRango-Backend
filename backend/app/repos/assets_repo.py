"""Assets data access. The only layer that knows procedure names and parameters."""
import json
from datetime import date
from typing import Any

from app.core.db import Db


# --- Asset types ---------------------------------------------------------------------------------

def list_asset_types(db: Db, company_id: int, search: str | None, is_active: bool | None,
                     page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sep.usp_asset_type_list", company_id=company_id, search=search, is_active=is_active,
                               page=page, page_size=page_size)
    return total[0]["total"], rows


def get_asset_type(db: Db, company_id: int, type_id: int) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_type_get", company_id=company_id, id=type_id)


def save_asset_type(db: Db, company_id: int, actor_user_id: int, type_id: int | None, name: str,
                    description: str | None, is_active: bool, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_type_save", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
                       name=name, description=description, is_active=is_active, row_version=row_version)


def delete_asset_type(db: Db, company_id: int, actor_user_id: int, type_id: int, row_version: bytes) -> None:
    db.call("sep.usp_asset_type_delete", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
            row_version=row_version)


# --- Company assets ------------------------------------------------------------------------------

def list_assets(db: Db, company_id: int, search: str | None, status: str | None, availability: str | None,
                asset_type_id: int | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sep.usp_asset_list", company_id=company_id, search=search, status=status,
                               availability=availability, asset_type_id=asset_type_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_asset(db: Db, company_id: int, asset_id: int) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_get", company_id=company_id, id=asset_id)


def save_asset(db: Db, company_id: int, actor_user_id: int, asset_id: int | None, fields: dict[str, Any],
               row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_save", company_id=company_id, actor_user_id=actor_user_id, id=asset_id,
                       name=fields["name"], asset_type_id=fields["asset_type_id"],
                       identification_no=fields["identification_no"], is_taxable=fields["is_taxable"],
                       asset_condition=fields["asset_condition"], manufacturer=fields["manufacturer"],
                       model=fields["model"], current_value=fields["current_value"],
                       acquired_date=fields["acquired_date"], description=fields["description"],
                       file_id=fields["file_id"], row_version=row_version)


def set_asset_active(db: Db, company_id: int, actor_user_id: int, asset_id: int, active: bool,
                     row_version: bytes) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_set_active", company_id=company_id, actor_user_id=actor_user_id, id=asset_id,
                       active=active, row_version=row_version)


def delete_asset(db: Db, company_id: int, actor_user_id: int, asset_id: int, row_version: bytes) -> None:
    db.call("sep.usp_asset_delete", company_id=company_id, actor_user_id=actor_user_id, id=asset_id,
            row_version=row_version)


def asset_history(db: Db, company_id: int, asset_id: int) -> list[dict[str, Any]]:
    return db.call("sep.usp_asset_history", company_id=company_id, id=asset_id)


# --- Allocations ---------------------------------------------------------------------------------

def list_allocations(db: Db, company_id: int, actor_user_id: int, search: str | None, employee_id: int | None,
                     asset_type_id: int | None, asset_id: int | None, status: str | None, from_date: date | None,
                     to_date: date | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sep.usp_asset_allocation_list", company_id=company_id, actor_user_id=actor_user_id,
                               search=search, employee_id=employee_id, asset_type_id=asset_type_id, asset_id=asset_id,
                               status=status, from_date=from_date, to_date=to_date, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_allocation(db: Db, company_id: int, actor_user_id: int, allocation_id: int) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_allocation_get", company_id=company_id, actor_user_id=actor_user_id,
                       id=allocation_id)


def allocate(db: Db, company_id: int, actor_user_id: int, asset_id: int, employee_id: int, allocated_on: date,
             description: str | None, file_id: int | None) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_allocation_allocate", company_id=company_id, actor_user_id=actor_user_id,
                       asset_id=asset_id, employee_id=employee_id, allocated_on=allocated_on,
                       description=description, file_id=file_id)


def deallocate(db: Db, company_id: int, actor_user_id: int, allocation_id: int, deallocated_on: date,
               return_condition: str | None, remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("sep.usp_asset_allocation_deallocate", company_id=company_id, actor_user_id=actor_user_id,
                       id=allocation_id, deallocated_on=deallocated_on, return_condition=return_condition,
                       remarks=remarks, row_version=row_version)


# --- Clearance forms -----------------------------------------------------------------------------

def list_clearances(db: Db, company_id: int, actor_user_id: int, search: str | None, status: str | None,
                    employee_id: int | None, department_id: int | None, end_of_employment_id: int | None,
                    page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sep.usp_asset_clearance_list", company_id=company_id, actor_user_id=actor_user_id,
                               search=search, status=status, employee_id=employee_id, department_id=department_id,
                               end_of_employment_id=end_of_employment_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def _form(sets: list[list[dict[str, Any]]]) -> dict[str, Any]:
    return {**sets[0][0], "items": sets[1] if len(sets) > 1 else []}


def get_clearance(db: Db, company_id: int, actor_user_id: int, clearance_id: int) -> dict[str, Any]:
    return _form(db.call_sets("sep.usp_asset_clearance_get", company_id=company_id, actor_user_id=actor_user_id,
                              id=clearance_id))


def clearance_prefill(db: Db, company_id: int, actor_user_id: int, employee_id: int) -> dict[str, Any]:
    return _form(db.call_sets("sep.usp_asset_clearance_prefill", company_id=company_id, actor_user_id=actor_user_id,
                              employee_id=employee_id))


def save_clearance(db: Db, company_id: int, actor_user_id: int, clearance_id: int | None, header: dict[str, Any],
                   items: list[dict[str, Any]], row_version: bytes | None) -> dict[str, Any]:
    return _form(db.call_sets(
        "sep.usp_asset_clearance_save", company_id=company_id, actor_user_id=actor_user_id, id=clearance_id,
        employee_id=header["employee_id"], end_of_employment_id=header["end_of_employment_id"],
        clearance_date=header["clearance_date"], checked_by_id=header["checked_by_id"],
        approved_by_id=header["approved_by_id"], approval_date=header["approval_date"], file_id=header["file_id"],
        items=json.dumps(items), row_version=row_version))


def delete_clearance(db: Db, company_id: int, actor_user_id: int, clearance_id: int, row_version: bytes) -> None:
    db.call("sep.usp_asset_clearance_delete", company_id=company_id, actor_user_id=actor_user_id, id=clearance_id,
            row_version=row_version)


def approve_clearances(db: Db, company_id: int, actor_user_id: int, forms: list[tuple[int, bytes]]) -> list[dict[str, Any]]:
    return db.call("sep.usp_asset_clearance_approve", company_id=company_id, actor_user_id=actor_user_id,
                   forms=json.dumps([{"id": i, "row_version": rv.hex()} for i, rv in forms]))


def unapprove_clearances(db: Db, company_id: int, actor_user_id: int, forms: list[tuple[int, bytes]]) -> list[dict[str, Any]]:
    return db.call("sep.usp_asset_clearance_unapprove", company_id=company_id, actor_user_id=actor_user_id,
                   forms=json.dumps([{"id": i, "row_version": rv.hex()} for i, rv in forms]))
