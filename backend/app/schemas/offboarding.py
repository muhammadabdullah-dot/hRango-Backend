from datetime import date, datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Reason = Literal["resignation", "termination", "retirement", "other"]
FieldType = Literal["number", "string", "date", "boolean"]


class RowVersionIn(ApiModel):
    row_version: str


# --- End of employment ---------------------------------------------------------------------------

class EndOfEmploymentIn(ApiModel):
    employee_id: int
    reason: Reason
    # The Notice Period tick. Without it the last working date is the day the record is made.
    serve_notice: bool = False
    notice_period_days: int | None = Field(None, ge=0)
    last_working_date: date | None = None
    needs_final_settlement: bool = False
    needs_asset_clearance: bool = False
    asset_clear_by_date: date | None = None
    replacement_id: int | None = None
    delegatee_id: int | None = None
    description: str | None = None
    # An uploaded file (POST /api/files): its id.
    file_id: int | None = None
    row_version: str | None = None


class ChecklistAnswerIn(ApiModel):
    checklist_field_id: int
    # Number, text, yyyy-mm-dd date or true / false. Empty or null clears the answer.
    answer: str | int | float | bool | None = None


class ChecklistAnswersIn(ApiModel):
    answers: list[ChecklistAnswerIn]
    row_version: str


class RehireIn(ApiModel):
    joining_date: date
    row_version: str


class EndOfEmploymentRowOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    branch_name: str | None
    location_name: str | None
    department_name: str | None
    designation_name: str | None
    reason: str
    serve_notice: bool
    last_working_date: date
    # pending or completed
    status: str
    completed_at: datetime | None
    is_rehired: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class ChecklistAnswerOut(ApiModel):
    checklist_field_id: str
    field_name: str
    field_type: str
    checklist_id: str
    checklist_name: str
    answer: str | None


class WaitingItemOut(ApiModel):
    # final_settlement, asset_clearance, assets, checklist, last_working_date
    item: str
    label: str


class EndOfEmploymentOut(EndOfEmploymentRowOut):
    employee_email: str | None
    employee_phone: str | None
    date_of_birth: date | None
    photo_file_id: str | None
    # Signed link to the employee's photo (expires).
    photo_url: str | None = None
    joining_date: date | None
    resignation_request_id: str | None
    notice_period_days: int | None
    needs_final_settlement: bool
    needs_asset_clearance: bool
    asset_clear_by_date: date | None
    replacement_id: str | None
    replacement_name: str | None
    delegatee_id: str | None
    delegatee_name: str | None
    description: str | None
    file_id: str | None
    # The attachment: id, name and a signed download link (expires).
    file: FileRef | None = None
    final_settlement_id: str | None
    final_settlement_status: str | None
    clearance_id: str | None
    clearance_status: str | None
    rehire_joining_date: date | None
    answers: list[ChecklistAnswerOut]
    waiting_for: list[WaitingItemOut]


# --- Off-boarding checklist settings -------------------------------------------------------------

class ChecklistFieldIn(ApiModel):
    id: int | None = None
    name: str = Field(min_length=1, max_length=200)
    field_type: FieldType
    is_required: bool = False
    # Value range for a number field.
    min_value: float | None = None
    max_value: float | None = None
    # Length range for a string field.
    min_length: int | None = Field(None, ge=0)
    max_length: int | None = Field(None, ge=0)


class ChecklistIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = None
    is_active: bool = True
    fields: list[ChecklistFieldIn] = []
    row_version: str | None = None


class ChecklistFieldOut(ApiModel):
    id: str
    name: str
    field_type: str
    is_required: bool
    min_value: float | None
    max_value: float | None
    min_length: int | None
    max_length: int | None
    sort_order: int | None


class ActiveChecklistFieldOut(ChecklistFieldOut):
    offboarding_checklist_id: str
    checklist_name: str


class ChecklistOut(ApiModel):
    id: str
    code: str
    name: str
    description: str | None
    is_active: bool
    field_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str
    # Filled on a single checklist; empty in lists.
    fields: list[ChecklistFieldOut] = []
