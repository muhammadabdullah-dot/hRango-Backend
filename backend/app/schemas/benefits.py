"""Benefits bodies: plan years, benefit plans, enrollment windows, employee elections, the Employees tab,
plan files, health benefits and perks."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Category = Literal["medical", "dental", "vision", "retirement", "hsa", "life", "others"]
Availed = Literal["availed", "not_availed"]


class SummaryOut(ApiModel):
    plan_years: int
    plans: int
    enrollment_windows: int
    employees: int


# ---------------------------------------------------------------- plan years


class PlanYearIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    start_date: date
    end_date: date
    plan_ids: list[int] = Field(default_factory=list, max_length=200)
    new_hire_start: Literal["immediately", "waiting_period", "per_employee"] = "immediately"
    waiting_period_days: int | None = Field(None, ge=1, le=365)
    election_period: int = Field(30, ge=1, le=365)
    election_unit: Literal["day", "week", "month"] = "day"
    row_version: str | None = None


class PlanYearOut(ApiModel):
    id: str
    name: str
    start_date: date
    end_date: date
    status: str
    new_hire_start: str
    waiting_period_days: int | None
    election_period: int
    election_unit: str
    plan_ids: list[str]
    plan_count: int
    window_count: int
    pending: int
    approved: int
    incomplete: int
    missing_information: int
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- benefit plans


class BenefitPlanIn(ApiModel):
    category: Category
    name: str = Field(min_length=1, max_length=200)
    plan_type: str | None = Field(None, max_length=100)
    plan_type_ref: str | None = Field(None, max_length=50)
    carrier: str | None = Field(None, max_length=200)
    start_date: date
    end_date: date
    description: str | None = Field(None, max_length=4000)
    status: Literal["active", "inactive"] = "active"
    row_version: str | None = None


class BenefitPlanOut(ApiModel):
    id: str
    category: str
    name: str
    plan_type: str | None
    plan_type_ref: str | None
    carrier: str | None
    start_date: date
    end_date: date
    description: str | None
    status: str
    enrolled: int
    pending: int
    file_count: int
    plan_year_ids: list[str]
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- enrollment windows


class WindowIn(ApiModel):
    plan_year_id: int
    kind: Literal["open_enrollment", "life_event", "new_hire"] = "open_enrollment"
    name: str = Field(min_length=1, max_length=200)
    effective_date: date
    # The last day to enrol.
    closes_on: date
    description: str | None = Field(None, max_length=4000)
    plan_ids: list[int] = Field(min_length=1, max_length=200)
    # Empty: everyone may enrol.
    employee_ids: list[int] = Field(default_factory=list, max_length=5000)
    row_version: str | None = None


class WindowOut(ApiModel):
    id: str
    name: str
    kind: str
    plan_year_id: str
    plan_year_name: str
    effective_date: date
    closes_on: date
    status: str
    description: str | None
    plan_ids: list[str]
    employee_ids: list[str]
    election_count: int
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- elections and the Employees tab


class ElectionIn(ApiModel):
    employee_id: int
    plan_year_id: int
    # Blank: the employee's open window of the plan year.
    enrollment_window_id: int | None = None
    plan_ids: list[int] = Field(default_factory=list, max_length=50)
    waive: bool = False
    # False keeps it incomplete (saved, not sent for approval).
    submit: bool = True
    remarks: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class ElectionOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    department_name: str | None
    job_title_name: str | None
    plan_year_id: str
    plan_year_name: str
    enrollment_window_id: str | None
    enrollment_window_name: str | None
    status: str
    plan_ids: list[str]
    plan_names: str | None
    submitted_at: datetime | None
    decided_by_user_id: str | None
    decided_by_name: str | None
    decided_at: datetime | None
    remarks: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class DecisionIn(ApiModel):
    remarks: str | None = Field(None, max_length=2000)
    row_version: str


class BenefitEmployeeOut(ApiModel):
    id: str
    code: str | None
    name: str | None
    job_title_name: str | None
    department_name: str | None
    date_of_birth: date | None
    marital_status: str | None
    # date_of_birth, marital_status: the details enrolment needs that are blank.
    missing: list[str]
    election_id: str | None
    election_status: str | None


# ---------------------------------------------------------------- files


class FileIn(ApiModel):
    # An uploaded file (POST /api/files, module benefits): its id.
    file_id: int


class BenefitFileOut(ApiModel):
    id: str
    file_id: str
    file_name: str
    mime_type: str | None
    size_bytes: int | None
    plan_id: str
    plan_name: str
    category: str
    # id, name and a signed download link (expires).
    file: FileRef | None = None
    created_at: datetime
    row_version: str


# ---------------------------------------------------------------- health benefits and perks


class HealthBenefitIn(ApiModel):
    employee_id: int
    insurer: str = Field(min_length=1, max_length=200)
    policy_no: str | None = Field(None, max_length=50)
    coverage_amount: Decimal | None = Field(None, ge=0)
    life_cover_amount: Decimal | None = Field(None, ge=0)
    annual_payment: Decimal | None = Field(None, ge=0)
    start_date: date | None = None
    end_date: date | None = None
    status: Availed = "not_availed"
    remarks: str | None = Field(None, max_length=2000)
    # The policy document or insurance card: an uploaded file (POST /api/files, module benefits).
    document_file_id: int | None = None
    row_version: str | None = None


class HealthBenefitOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    department_name: str | None
    insurer: str | None
    policy_no: str | None
    coverage_amount: float | None
    life_cover_amount: float | None
    annual_payment: float | None
    start_date: date | None
    end_date: date | None
    status: str
    remarks: str | None
    document_file_id: str | None = None
    # The document: id, name and a signed download link (expires).
    document_file: FileRef | None = None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class PerkIn(ApiModel):
    employee_id: int
    occasion: Literal["eid_ul_adha", "eid_ul_fitr", "birthday", "ramadan", "new_year"]
    perk_date: date
    description: str | None = Field(None, max_length=2000)
    amount: Decimal | None = Field(None, ge=0)
    status: Availed = "not_availed"
    row_version: str | None = None


class PerkOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str | None
    department_name: str | None
    occasion: str
    perk_date: date
    description: str | None
    amount: float | None
    status: str
    created_at: datetime
    updated_at: datetime | None
    row_version: str
