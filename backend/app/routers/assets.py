from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import assets_controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.assets import (AllocationIn, AllocationOut, AssetHistoryOut, AssetIn, AssetOut, AssetStatus,
                                AssetTypeIn, AssetTypeOut, Availability, ClearanceBulkIn, ClearanceIn, ClearanceOut,
                                ClearancePrefillOut, ClearanceRowOut, DeallocateIn, RowVersionIn)
from app.schemas.common import Item, Paginated

router = APIRouter(prefix="/assets", tags=["assets"])


# --- Asset types ---------------------------------------------------------------------------------

@router.get("/types", response_model=Paginated[AssetTypeOut])
def list_asset_types(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require_any("assets.types.view", "assets.company_assets.view",
                                                               "assets.allocations.assign"))) -> dict:
    return assets_controller.list_asset_types(db, ctx, q, is_active, paging)


@router.get("/types/{type_id}", response_model=Item[AssetTypeOut])
def get_asset_type(type_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("assets.types.view"))) -> dict:
    return assets_controller.get_asset_type(db, ctx, type_id)


@router.post("/types", response_model=Item[AssetTypeOut], status_code=status.HTTP_201_CREATED)
def create_asset_type(body: AssetTypeIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("assets.types.create"))) -> dict:
    return assets_controller.create_asset_type(db, ctx, body)


@router.put("/types/{type_id}", response_model=Item[AssetTypeOut])
def update_asset_type(type_id: int, body: AssetTypeIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("assets.types.edit"))) -> dict:
    return assets_controller.update_asset_type(db, ctx, type_id, body)


@router.delete("/types/{type_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_asset_type(type_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                      db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("assets.types.delete"))) -> Response:
    assets_controller.delete_asset_type(db, ctx, type_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Company assets ------------------------------------------------------------------------------

@router.get("/company-assets", response_model=Paginated[AssetOut])
def list_assets(q: str | None = None, asset_status: AssetStatus | None = Query(None, alias="status"),
                availability: Availability | None = None,
                asset_type_id: int | None = Query(None, alias="assetTypeId"),
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require_any("assets.company_assets.view",
                                                          "assets.allocations.assign"))) -> dict:
    return assets_controller.list_assets(db, ctx, q, asset_status, availability, asset_type_id, paging)


@router.get("/company-assets/{asset_id}", response_model=Item[AssetOut])
def get_asset(asset_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("assets.company_assets.view"))) -> dict:
    return assets_controller.get_asset(db, ctx, asset_id)


@router.get("/company-assets/{asset_id}/history", response_model=Item[list[AssetHistoryOut]])
def asset_history(asset_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("assets.company_assets.view"))) -> dict:
    return assets_controller.asset_history(db, ctx, asset_id)


@router.post("/company-assets", response_model=Item[AssetOut], status_code=status.HTTP_201_CREATED)
def create_asset(body: AssetIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("assets.company_assets.create"))) -> dict:
    return assets_controller.create_asset(db, ctx, body)


@router.put("/company-assets/{asset_id}", response_model=Item[AssetOut])
def update_asset(asset_id: int, body: AssetIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("assets.company_assets.edit"))) -> dict:
    return assets_controller.update_asset(db, ctx, asset_id, body)


@router.patch("/company-assets/{asset_id}/deactivate", response_model=Item[AssetOut])
def deactivate_asset(asset_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("assets.company_assets.edit"))) -> dict:
    return assets_controller.set_asset_active(db, ctx, asset_id, False, body.row_version)


@router.patch("/company-assets/{asset_id}/activate", response_model=Item[AssetOut])
def activate_asset(asset_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("assets.company_assets.edit"))) -> dict:
    return assets_controller.set_asset_active(db, ctx, asset_id, True, body.row_version)


@router.delete("/company-assets/{asset_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_asset(asset_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("assets.company_assets.delete"))) -> Response:
    assets_controller.delete_asset(db, ctx, asset_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Allocations ---------------------------------------------------------------------------------

@router.get("/allocations", response_model=Paginated[AllocationOut])
def list_allocations(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                     asset_type_id: int | None = Query(None, alias="assetTypeId"),
                     asset_id: int | None = Query(None, alias="assetId"),
                     allocation_status: Literal["allocated", "deallocated"] | None = Query(None, alias="status"),
                     from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("assets.allocations.view"))) -> dict:
    return assets_controller.list_allocations(db, ctx, q, employee_id, asset_type_id, asset_id, allocation_status,
                                              from_date, to_date, paging)


@router.get("/allocations/{allocation_id}", response_model=Item[AllocationOut])
def get_allocation(allocation_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("assets.allocations.view"))) -> dict:
    return assets_controller.get_allocation(db, ctx, allocation_id)


@router.post("/allocations", response_model=Item[AllocationOut], status_code=status.HTTP_201_CREATED)
def allocate(body: AllocationIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("assets.allocations.assign"))) -> dict:
    return assets_controller.allocate(db, ctx, body)


@router.patch("/allocations/{allocation_id}/deallocate", response_model=Item[AllocationOut])
def deallocate(allocation_id: int, body: DeallocateIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("assets.allocations.assign"))) -> dict:
    return assets_controller.deallocate(db, ctx, allocation_id, body)


# --- Clearance forms -----------------------------------------------------------------------------

@router.get("/clearance-forms", response_model=Paginated[ClearanceRowOut])
def list_clearances(q: str | None = None,
                    clearance_status: Literal["in_progress", "approved"] | None = Query(None, alias="status"),
                    employee_id: int | None = Query(None, alias="employeeId"),
                    department_id: int | None = Query(None, alias="departmentId"),
                    end_of_employment_id: int | None = Query(None, alias="endOfEmploymentId"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("assets.clearance.view"))) -> dict:
    return assets_controller.list_clearances(db, ctx, q, clearance_status, employee_id, department_id,
                                             end_of_employment_id, paging)


@router.get("/clearance-forms/prefill", response_model=Item[ClearancePrefillOut])
def clearance_prefill(employee_id: int = Query(alias="employeeId"), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("assets.clearance.create"))) -> dict:
    return assets_controller.clearance_prefill(db, ctx, employee_id)


@router.patch("/clearance-forms/approve", response_model=Item[list[ClearanceRowOut]])
def approve_clearances(body: ClearanceBulkIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("assets.clearance.approve"))) -> dict:
    return assets_controller.approve_clearances(db, ctx, body)


@router.patch("/clearance-forms/unapprove", response_model=Item[list[ClearanceRowOut]])
def unapprove_clearances(body: ClearanceBulkIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("assets.clearance.approve"))) -> dict:
    return assets_controller.unapprove_clearances(db, ctx, body)


@router.get("/clearance-forms/{clearance_id}", response_model=Item[ClearanceOut])
def get_clearance(clearance_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("assets.clearance.view"))) -> dict:
    return assets_controller.get_clearance(db, ctx, clearance_id)


@router.post("/clearance-forms", response_model=Item[ClearanceOut], status_code=status.HTTP_201_CREATED)
def create_clearance(body: ClearanceIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("assets.clearance.create"))) -> dict:
    return assets_controller.create_clearance(db, ctx, body)


@router.put("/clearance-forms/{clearance_id}", response_model=Item[ClearanceOut])
def update_clearance(clearance_id: int, body: ClearanceIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("assets.clearance.edit"))) -> dict:
    return assets_controller.update_clearance(db, ctx, clearance_id, body)


@router.delete("/clearance-forms/{clearance_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_clearance(clearance_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("assets.clearance.delete"))) -> Response:
    assets_controller.delete_clearance(db, ctx, clearance_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
