from datetime import date, datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

AssetCondition = Literal["old", "new", "fair"]
AssetStatus = Literal["active", "damaged", "lost", "decommissioned"]
Availability = Literal["available", "allocated", "unavailable"]
ReturnCondition = Literal["good", "fair", "damaged"]
ReturnStatus = Literal["complete", "partial", "not_returned"]


class RowVersionIn(ApiModel):
    row_version: str


# --- Asset types ---------------------------------------------------------------------------------

class AssetTypeIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = None
    is_active: bool = True
    row_version: str | None = None


class AssetTypeOut(ApiModel):
    id: str
    code: str
    name: str
    description: str | None
    is_active: bool
    asset_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Company assets ------------------------------------------------------------------------------

class AssetIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    asset_type_id: int
    identification_no: str | None = Field(None, max_length=100)
    is_taxable: bool = False
    asset_condition: AssetCondition
    manufacturer: str | None = Field(None, max_length=100)
    model: str | None = Field(None, max_length=100)
    current_value: float | None = Field(None, ge=0)
    acquired_date: date | None = None
    description: str | None = None
    # An uploaded file (POST /api/files): its id.
    file_id: int | None = None
    row_version: str | None = None


class AssetOut(ApiModel):
    id: str
    code: str
    name: str
    asset_type_id: str
    asset_type_name: str
    identification_no: str | None
    is_taxable: bool
    asset_condition: str
    manufacturer: str | None
    model: str | None
    current_value: float | None
    acquired_date: date | None
    description: str | None
    file_id: str | None
    # The attachment: id, name and a signed download link (expires).
    file: FileRef | None = None
    status: str
    # available, allocated (someone holds it) or unavailable (not active)
    availability: str
    holder_id: str | None
    holder_code: str | None
    holder_name: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class AssetHistoryOut(ApiModel):
    id: str
    action: str
    field_name: str | None
    old_value: str | None
    new_value: str | None
    performed_at: datetime
    performed_by_user_id: str | None
    performed_by_name: str | None


# --- Allocations ---------------------------------------------------------------------------------

class AllocationIn(ApiModel):
    asset_id: int
    employee_id: int
    allocated_on: date
    description: str | None = None
    # An uploaded file (POST /api/files): its id.
    file_id: int | None = None


class DeallocateIn(ApiModel):
    deallocated_on: date
    return_condition: ReturnCondition | None = None
    remarks: str | None = Field(None, max_length=500)
    row_version: str


class AllocationOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    company_name: str
    asset_id: str
    asset_code: str
    asset_name: str
    identification_no: str | None
    asset_type_id: str
    asset_type_name: str
    allocated_on: date
    deallocated_on: date | None
    status: str
    description: str | None
    return_condition: str | None
    deallocation_remarks: str | None
    file_id: str | None
    # The attachment: id, name and a signed download link (expires).
    file: FileRef | None = None
    asset_clearance_id: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Clearance forms -----------------------------------------------------------------------------

class ClearanceItemIn(ApiModel):
    asset_allocation_id: int
    condition_at_clearance: ReturnCondition
    reason: str | None = None
    return_status: ReturnStatus
    comments: str | None = None


class ClearanceIn(ApiModel):
    employee_id: int
    end_of_employment_id: int | None = None
    clearance_date: date
    checked_by_id: int | None = None
    approved_by_id: int | None = None
    approval_date: date | None = None
    # An uploaded file (POST /api/files): its id.
    file_id: int | None = None
    items: list[ClearanceItemIn] = []
    row_version: str | None = None


class ClearanceRef(ApiModel):
    id: int
    row_version: str


class ClearanceBulkIn(ApiModel):
    forms: list[ClearanceRef] = Field(min_length=1)


class ClearanceItemOut(ApiModel):
    id: str
    asset_allocation_id: str
    asset_id: str
    asset_code: str
    asset_name: str
    identification_no: str | None
    allocated_on: date
    condition_at_clearance: str | None
    reason: str | None
    return_status: str | None
    comments: str | None


class ClearanceRowOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    department_id: str | None
    department_name: str | None
    end_of_employment_id: str | None
    clearance_date: date
    approval_date: date | None
    # in_progress or approved
    status: str
    item_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class ClearanceOut(ClearanceRowOut):
    checked_by_id: str | None
    checked_by_name: str | None
    approved_by_id: str | None
    approved_by_name: str | None
    file_id: str | None
    # The attachment: id, name and a signed download link (expires).
    file: FileRef | None = None
    items: list[ClearanceItemOut]


class ClearancePrefillItem(ApiModel):
    asset_allocation_id: str
    asset_id: str
    asset_code: str
    asset_name: str
    identification_no: str | None
    allocated_on: date


class ClearancePrefillOut(ApiModel):
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    department_id: str | None
    department_name: str | None
    end_of_employment_id: str | None
    items: list[ClearancePrefillItem]
