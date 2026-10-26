"""Manpower planning bodies: E-Budget Settings (budget durations, position titles, employee positions and
their salary ranges), plans with their lines, e-budgets and approvals, open positions."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Money = Decimal

# ---------------------------------------------------------------- budget durations


class BudgetDurationIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    start_date: date
    end_date: date
    is_current: bool = False
    row_version: str | None = None


class BudgetDurationOut(ApiModel):
    id: str
    name: str
    start_date: date
    end_date: date
    is_current: bool
    plan_count: int
    budget_count: int
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- position titles (org.job_title)


class PositionTitleOut(ApiModel):
    id: str
    name: str
    position_count: int
    active_position_count: int
    open_position_count: int
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None


# ---------------------------------------------------------------- employee positions


class PositionIn(ApiModel):
    # Blank: the next POS-0001 number is given.
    code: str | None = Field(None, max_length=30)
    job_title_id: int
    branch_id: int
    employee_group_id: int
    division_id: int | None = None
    department_id: int | None = None
    sub_department_id: int | None = None
    cost_center_id: int | None = None
    grade_id: int | None = None
    reports_to_id: int | None = None
    employee_id: int | None = None
    status: Literal["active", "inactive"] = "active"
    min_salary: Money = Field(ge=0)
    max_salary: Money = Field(gt=0)
    row_version: str | None = None


class PositionOut(ApiModel):
    id: str
    code: str
    status: str
    job_title_id: str
    job_title_name: str
    branch_id: str
    branch_name: str
    employee_group_id: str
    employee_group_name: str
    division_id: str | None
    division_name: str | None
    department_id: str | None
    department_name: str | None
    sub_department_id: str | None
    sub_department_name: str | None
    cost_center_id: str | None
    cost_center_name: str | None
    grade_id: str | None
    grade_name: str | None
    reports_to_id: str | None
    reports_to_code: str | None
    reports_to_title: str | None
    employee_id: str | None
    employee_name: str | None
    min_salary: float | None
    max_salary: float | None
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    updated_by_name: str | None
    row_version: str


class PositionImportRow(ApiModel):
    """One line of an Upload Excel sheet, by names (the sheet is read by the frontend)."""
    code: str | None = None
    position_title: str | None = None
    station: str | None = None
    employee_group: str | None = None
    division: str | None = None
    department: str | None = None
    sub_department: str | None = None
    cost_center: str | None = None
    grade: str | None = None
    reports_to: str | None = None
    min_salary: Decimal | str | None = None
    max_salary: Decimal | str | None = None


class PositionImportIn(ApiModel):
    rows: list[PositionImportRow] = Field(min_length=1, max_length=2000)


class ImportErrorOut(ApiModel):
    row_no: int
    field: str | None
    message: str


class ImportResultOut(ApiModel):
    created: int
    errors: list[ImportErrorOut]


class SalaryRangeIn(ApiModel):
    effective_date: date
    min_salary: Money = Field(ge=0)
    max_salary: Money = Field(gt=0)


class SalaryRangeOut(ApiModel):
    id: str
    position_id: str
    effective_date: date
    min_salary: float
    max_salary: float
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- plans


class PlanLineIn(ApiModel):
    kind: Literal["new_position", "existing_employee"]
    position_id: int | None = None
    employee_id: int | None = None
    headcount: int | None = None
    start_date: date | None = None
    end_date: date | None = None
    # New positions: blank takes the position's band.
    min_salary: Money | None = None
    max_salary: Money | None = None
    # Existing employees: blank takes the current salary.
    monthly_salary: Money | None = None
    total_allowance: Money | None = None


class PlanIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    budget_duration_id: int
    division_id: int | None = None
    branch_id: int | None = None
    department_id: int | None = None
    sub_department_id: int | None = None
    employee_group_id: int | None = None
    description: str | None = Field(None, max_length=4000)
    lines: list[PlanLineIn] = Field(max_length=500)
    # Uploaded files (POST /api/files) for the plan; the list replaces the plan's files. Omit to keep them.
    file_ids: list[int] | None = Field(None, max_length=20)
    row_version: str | None = None


class PlanOut(ApiModel):
    id: str
    title: str
    budget_duration_id: str
    budget_duration_name: str
    is_current: bool
    division_id: str | None
    division_name: str | None
    branch_id: str | None
    branch_name: str | None
    department_id: str | None
    department_name: str | None
    sub_department_id: str | None
    sub_department_name: str | None
    employee_group_id: str | None
    employee_group_name: str | None
    description: str | None
    monthly_amount: float
    annual_amount: float
    status: str
    submitted_at: datetime | None
    has_new_positions: bool
    has_existing_positions: bool
    budget_count: int
    approved_budget_count: int
    is_locked: bool
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    updated_by_name: str | None
    row_version: str


class PlanLineOut(ApiModel):
    id: str
    kind: str
    sort_order: int | None
    position_id: str | None
    position_code: str | None
    job_title_name: str | None
    employee_id: str | None
    employee_code: str | None
    employee_name: str | None
    department_name: str | None
    branch_name: str | None
    headcount: int
    start_date: date
    end_date: date
    months: int
    min_salary: float | None
    max_salary: float | None
    monthly_salary: float | None
    total_allowance: float
    total_salary: float
    annual_gross: float
    e_budget_id: str | None


# ---------------------------------------------------------------- e-budgets


class BudgetIn(ApiModel):
    title: str | None = Field(None, max_length=200)
    budget_duration_id: int
    job_title_id: int | None = None
    department_id: int | None = None
    amount: Money = Field(gt=0)
    total_positions: int = Field(0, ge=0)
    start_date: date
    end_date: date
    row_version: str | None = None


class BudgetOut(ApiModel):
    id: str
    title: str
    budget_duration_id: str
    budget_duration_name: str
    manpower_plan_id: str | None
    plan_title: str | None
    job_title_id: str | None
    job_title_name: str | None
    department_id: str | None
    department_name: str | None
    amount: float
    total_positions: int
    start_date: date
    end_date: date
    status: str
    decided_by_user_id: str | None
    decided_by_name: str | None
    decided_at: datetime | None
    remarks: str | None
    open_position_count: int
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


class PlanFileOut(ApiModel):
    """A file attached to a plan (core.attachment)."""

    attachment_id: str
    id: str
    name: str
    mime_type: str | None
    size_bytes: int | None
    created_at: datetime
    url: str


class PlanDetailOut(PlanOut):
    lines: list[PlanLineOut]
    budgets: list[BudgetOut]
    files: list[PlanFileOut] = []


class DecisionIn(ApiModel):
    remarks: str | None = Field(None, max_length=2000)
    row_version: str


# ---------------------------------------------------------------- open positions


class OpenPositionIn(ApiModel):
    total_positions: int = Field(ge=1)
    end_date: date | None = None
    # An uploaded file (POST /api/files, module manpower): its id.
    jd_file_id: int | None = None
    row_version: str


class RowVersionIn(ApiModel):
    row_version: str


class OpenPositionOut(ApiModel):
    id: str
    title: str
    e_budget_id: str
    budget_title: str
    manpower_plan_id: str | None
    plan_title: str | None
    manpower_plan_line_id: str | None
    position_id: str | None
    position_code: str | None
    job_title_id: str | None
    job_title_name: str | None
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
    approved_positions: int
    total_positions: int
    end_date: date | None
    jd_file_id: str | None
    # The JD: id, name and a signed download link (expires).
    jd_file: FileRef | None = None
    status: str
    approved_at: datetime | None
    approved_by_name: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class FileOut(ApiModel):
    id: str
    name: str
    mime_type: str | None
    size_bytes: int | None
    created_at: datetime
    # Signed download link (expires).
    url: str

