"""Assets rules. Checks that need the database (allocated twice, duplicates, history) live in the
procedures; rules that do not live here.

Asset types and company assets belong to the company, not to an employee, so own scope (which the
Employee role holds on every *.view and *.create) does not reach them.
"""
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import forbidden, invalid
from app.middlewares.auth import RequestContext
from app.repos import assets_repo


def _company_level(ctx: RequestContext) -> None:
    if not (ctx.scopes - {"own", ""}):
        raise forbidden()


def _date_range(from_date: date | None, to_date: date | None) -> None:
    if from_date and to_date and from_date > to_date:
        raise invalid("From must not be after To.", "to")


# --- Asset types ---------------------------------------------------------------------------------

def list_asset_types(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None,
                     page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    _company_level(ctx)
    return assets_repo.list_asset_types(db, ctx.company_id, search, is_active, page, page_size)


def get_asset_type(db: Db, ctx: RequestContext, type_id: int) -> dict[str, Any]:
    _company_level(ctx)
    return assets_repo.get_asset_type(db, ctx.company_id, type_id)


def save_asset_type(db: Db, ctx: RequestContext, type_id: int | None, name: str, description: str | None,
                    is_active: bool, row_version: bytes | None) -> dict[str, Any]:
    _company_level(ctx)
    return assets_repo.save_asset_type(db, ctx.company_id, ctx.user_id, type_id, name, description, is_active,
                                       row_version)


def delete_asset_type(db: Db, ctx: RequestContext, type_id: int, row_version: bytes) -> None:
    _company_level(ctx)
    assets_repo.delete_asset_type(db, ctx.company_id, ctx.user_id, type_id, row_version)


# --- Company assets ------------------------------------------------------------------------------

def list_assets(db: Db, ctx: RequestContext, search: str | None, status: str | None, availability: str | None,
                asset_type_id: int | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    _company_level(ctx)
    return assets_repo.list_assets(db, ctx.company_id, search, status, availability, asset_type_id, page, page_size)


def get_asset(db: Db, ctx: RequestContext, asset_id: int) -> dict[str, Any]:
    _company_level(ctx)
    return assets_repo.get_asset(db, ctx.company_id, asset_id)


def save_asset(db: Db, ctx: RequestContext, asset_id: int | None, fields: dict[str, Any],
               row_version: bytes | None) -> dict[str, Any]:
    _company_level(ctx)
    if fields["acquired_date"] and fields["acquired_date"] > date.today():
        raise invalid("The acquired date cannot be in the future.", "acquiredDate")
    return assets_repo.save_asset(db, ctx.company_id, ctx.user_id, asset_id, fields, row_version)


def set_asset_active(db: Db, ctx: RequestContext, asset_id: int, active: bool, row_version: bytes) -> dict[str, Any]:
    _company_level(ctx)
    return assets_repo.set_asset_active(db, ctx.company_id, ctx.user_id, asset_id, active, row_version)


def delete_asset(db: Db, ctx: RequestContext, asset_id: int, row_version: bytes) -> None:
    _company_level(ctx)
    assets_repo.delete_asset(db, ctx.company_id, ctx.user_id, asset_id, row_version)


def asset_history(db: Db, ctx: RequestContext, asset_id: int) -> list[dict[str, Any]]:
    _company_level(ctx)
    return assets_repo.asset_history(db, ctx.company_id, asset_id)


# --- Allocations ---------------------------------------------------------------------------------

def list_allocations(db: Db, ctx: RequestContext, search: str | None, employee_id: int | None,
                     asset_type_id: int | None, asset_id: int | None, status: str | None, from_date: date | None,
                     to_date: date | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    _date_range(from_date, to_date)
    return assets_repo.list_allocations(db, ctx.company_id, ctx.user_id, search, employee_id, asset_type_id,
                                        asset_id, status, from_date, to_date, page, page_size)


def get_allocation(db: Db, ctx: RequestContext, allocation_id: int) -> dict[str, Any]:
    return assets_repo.get_allocation(db, ctx.company_id, ctx.user_id, allocation_id)


def allocate(db: Db, ctx: RequestContext, asset_id: int, employee_id: int, allocated_on: date,
             description: str | None, file_id: int | None) -> dict[str, Any]:
    return assets_repo.allocate(db, ctx.company_id, ctx.user_id, asset_id, employee_id, allocated_on, description,
                                file_id)


def deallocate(db: Db, ctx: RequestContext, allocation_id: int, deallocated_on: date, return_condition: str | None,
               remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return assets_repo.deallocate(db, ctx.company_id, ctx.user_id, allocation_id, deallocated_on, return_condition,
                                  remarks, row_version)


# --- Clearance forms -----------------------------------------------------------------------------

def list_clearances(db: Db, ctx: RequestContext, search: str | None, status: str | None, employee_id: int | None,
                    department_id: int | None, end_of_employment_id: int | None,
                    page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return assets_repo.list_clearances(db, ctx.company_id, ctx.user_id, search, status, employee_id, department_id,
                                       end_of_employment_id, page, page_size)


def get_clearance(db: Db, ctx: RequestContext, clearance_id: int) -> dict[str, Any]:
    return assets_repo.get_clearance(db, ctx.company_id, ctx.user_id, clearance_id)


def clearance_prefill(db: Db, ctx: RequestContext, employee_id: int) -> dict[str, Any]:
    return assets_repo.clearance_prefill(db, ctx.company_id, ctx.user_id, employee_id)


def save_clearance(db: Db, ctx: RequestContext, clearance_id: int | None, header: dict[str, Any],
                   items: list[dict[str, Any]], row_version: bytes | None) -> dict[str, Any]:
    if header["approval_date"] and header["approval_date"] < header["clearance_date"]:
        raise invalid("The approval date is before the clearance date.", "approvalDate")
    return assets_repo.save_clearance(db, ctx.company_id, ctx.user_id, clearance_id, header, items, row_version)


def delete_clearance(db: Db, ctx: RequestContext, clearance_id: int, row_version: bytes) -> None:
    assets_repo.delete_clearance(db, ctx.company_id, ctx.user_id, clearance_id, row_version)


def approve_clearances(db: Db, ctx: RequestContext, forms: list[tuple[int, bytes]]) -> list[dict[str, Any]]:
    return assets_repo.approve_clearances(db, ctx.company_id, ctx.user_id, forms)


def unapprove_clearances(db: Db, ctx: RequestContext, forms: list[tuple[int, bytes]]) -> list[dict[str, Any]]:
    return assets_repo.unapprove_clearances(db, ctx.company_id, ctx.user_id, forms)
