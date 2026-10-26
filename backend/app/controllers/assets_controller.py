"""HTTP shape for the Assets screens: envelopes, row versions as text, rows to response models."""
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.assets import (AllocationIn, AllocationOut, AssetHistoryOut, AssetIn, AssetOut, AssetTypeIn,
                                AssetTypeOut, ClearanceBulkIn, ClearanceIn, ClearanceItemOut, ClearanceOut,
                                ClearancePrefillItem, ClearancePrefillOut, ClearanceRowOut, DeallocateIn)
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.services import assets_service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _asset_type(row: dict[str, Any]) -> AssetTypeOut:
    return AssetTypeOut(**_rv(row))


def _file(row: dict[str, Any], company_id: int) -> FileRef | None:
    """The record's attachment: id, name and a signed download link."""
    if not row.get("file_id"):
        return None
    return FileRef(id=str(row["file_id"]), name=row.get("file_name"), url=file_url(row["file_id"], company_id))


def _asset(row: dict[str, Any], company_id: int) -> AssetOut:
    return AssetOut(**_rv(row), file=_file(row, company_id))


def _allocation(row: dict[str, Any], company_id: int) -> AllocationOut:
    return AllocationOut(**_rv(row), file=_file(row, company_id))


def _clearance_row(row: dict[str, Any]) -> ClearanceRowOut:
    return ClearanceRowOut(**_rv(row))


def _clearance(form: dict[str, Any], company_id: int) -> ClearanceOut:
    return ClearanceOut(**{**_rv(form), "items": [ClearanceItemOut(**i) for i in form["items"]]},
                        file=_file(form, company_id))


# --- Asset types ---------------------------------------------------------------------------------

def list_asset_types(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = assets_service.list_asset_types(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _asset_type)


def get_asset_type(db: Db, ctx: RequestContext, type_id: int) -> dict:
    return {"data": _asset_type(assets_service.get_asset_type(db, ctx, type_id))}


def create_asset_type(db: Db, ctx: RequestContext, body: AssetTypeIn) -> dict:
    row = assets_service.save_asset_type(db, ctx, None, body.name, body.description, body.is_active, None)
    return {"data": _asset_type(row)}


def update_asset_type(db: Db, ctx: RequestContext, type_id: int, body: AssetTypeIn) -> dict:
    row = assets_service.save_asset_type(db, ctx, type_id, body.name, body.description, body.is_active,
                                         row_version_in(body.row_version))
    return {"data": _asset_type(row)}


def delete_asset_type(db: Db, ctx: RequestContext, type_id: int, row_version: str | None) -> None:
    assets_service.delete_asset_type(db, ctx, type_id, row_version_in(row_version))


# --- Company assets ------------------------------------------------------------------------------

def list_assets(db: Db, ctx: RequestContext, q: str | None, status: str | None, availability: str | None,
                asset_type_id: int | None, paging: PageParams) -> dict:
    total, rows = assets_service.list_assets(db, ctx, q, status, availability, asset_type_id, paging.page,
                                             paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _asset(r, ctx.company_id))


def get_asset(db: Db, ctx: RequestContext, asset_id: int) -> dict:
    return {"data": _asset(assets_service.get_asset(db, ctx, asset_id), ctx.company_id)}


def _asset_fields(body: AssetIn) -> dict[str, Any]:
    return body.model_dump(by_alias=False, exclude={"row_version"})


def create_asset(db: Db, ctx: RequestContext, body: AssetIn) -> dict:
    return {"data": _asset(assets_service.save_asset(db, ctx, None, _asset_fields(body), None), ctx.company_id)}


def update_asset(db: Db, ctx: RequestContext, asset_id: int, body: AssetIn) -> dict:
    row = assets_service.save_asset(db, ctx, asset_id, _asset_fields(body), row_version_in(body.row_version))
    return {"data": _asset(row, ctx.company_id)}


def set_asset_active(db: Db, ctx: RequestContext, asset_id: int, active: bool, row_version: str) -> dict:
    row = assets_service.set_asset_active(db, ctx, asset_id, active, row_version_in(row_version))
    return {"data": _asset(row, ctx.company_id)}


def delete_asset(db: Db, ctx: RequestContext, asset_id: int, row_version: str | None) -> None:
    assets_service.delete_asset(db, ctx, asset_id, row_version_in(row_version))


def asset_history(db: Db, ctx: RequestContext, asset_id: int) -> dict:
    rows = assets_service.asset_history(db, ctx, asset_id)
    return {"data": [AssetHistoryOut(**{**r, "action": r["action_name"]}) for r in rows]}


# --- Allocations ---------------------------------------------------------------------------------

def list_allocations(db: Db, ctx: RequestContext, q: str | None, employee_id: int | None, asset_type_id: int | None,
                     asset_id: int | None, status: str | None, from_date: date | None, to_date: date | None,
                     paging: PageParams) -> dict:
    total, rows = assets_service.list_allocations(db, ctx, q, employee_id, asset_type_id, asset_id, status,
                                                  from_date, to_date, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _allocation(r, ctx.company_id))


def get_allocation(db: Db, ctx: RequestContext, allocation_id: int) -> dict:
    return {"data": _allocation(assets_service.get_allocation(db, ctx, allocation_id), ctx.company_id)}


def allocate(db: Db, ctx: RequestContext, body: AllocationIn) -> dict:
    row = assets_service.allocate(db, ctx, body.asset_id, body.employee_id, body.allocated_on, body.description,
                                  body.file_id)
    return {"data": _allocation(row, ctx.company_id)}


def deallocate(db: Db, ctx: RequestContext, allocation_id: int, body: DeallocateIn) -> dict:
    row = assets_service.deallocate(db, ctx, allocation_id, body.deallocated_on, body.return_condition, body.remarks,
                                    row_version_in(body.row_version))
    return {"data": _allocation(row, ctx.company_id)}


# --- Clearance forms -----------------------------------------------------------------------------

def list_clearances(db: Db, ctx: RequestContext, q: str | None, status: str | None, employee_id: int | None,
                    department_id: int | None, end_of_employment_id: int | None, paging: PageParams) -> dict:
    total, rows = assets_service.list_clearances(db, ctx, q, status, employee_id, department_id,
                                                 end_of_employment_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _clearance_row)


def get_clearance(db: Db, ctx: RequestContext, clearance_id: int) -> dict:
    return {"data": _clearance(assets_service.get_clearance(db, ctx, clearance_id), ctx.company_id)}


def clearance_prefill(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    form = assets_service.clearance_prefill(db, ctx, employee_id)
    return {"data": ClearancePrefillOut(**{**form, "items": [ClearancePrefillItem(**i) for i in form["items"]]})}


def _clearance_parts(body: ClearanceIn) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    header = body.model_dump(by_alias=False, exclude={"items", "row_version"})
    return header, [i.model_dump(by_alias=False) for i in body.items]


def create_clearance(db: Db, ctx: RequestContext, body: ClearanceIn) -> dict:
    header, items = _clearance_parts(body)
    return {"data": _clearance(assets_service.save_clearance(db, ctx, None, header, items, None), ctx.company_id)}


def update_clearance(db: Db, ctx: RequestContext, clearance_id: int, body: ClearanceIn) -> dict:
    header, items = _clearance_parts(body)
    form = assets_service.save_clearance(db, ctx, clearance_id, header, items, row_version_in(body.row_version))
    return {"data": _clearance(form, ctx.company_id)}


def delete_clearance(db: Db, ctx: RequestContext, clearance_id: int, row_version: str | None) -> None:
    assets_service.delete_clearance(db, ctx, clearance_id, row_version_in(row_version))


def _forms(body: ClearanceBulkIn) -> list[tuple[int, bytes]]:
    return [(f.id, row_version_in(f.row_version)) for f in body.forms]


def approve_clearances(db: Db, ctx: RequestContext, body: ClearanceBulkIn) -> dict:
    return {"data": [_clearance_row(r) for r in assets_service.approve_clearances(db, ctx, _forms(body))]}


def unapprove_clearances(db: Db, ctx: RequestContext, body: ClearanceBulkIn) -> dict:
    return {"data": [_clearance_row(r) for r in assets_service.unapprove_clearances(db, ctx, _forms(body))]}
