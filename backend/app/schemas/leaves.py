from datetime import date, datetime, time
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import Field, PlainSerializer

from app.schemas.common import ApiModel

# Numbers kept exact in Python (DECIMAL in the database) and sent as JSON numbers.
Number = Annotated[Decimal, PlainSerializer(float, return_type=float, when_used="json")]
Days = Number  # leave days: DECIMAL(6,2), half days allowed

# --- General settings ------------------------------------------------------------------------------


class LeaveSettingsIn(ApiModel):
    # Whose approval completes a leave application.
    final_approval_by: Literal["hr_manager", "line_manager", "department_head"]
    # The status at which an application counts as leave taken.
    approve_on_status: Literal["approved", "pending"]
    # Back-dated applications must be posted within the type's Back Date Leave Limit in Days.
    post_deadline: bool = False
    row_version: str | None = None


class LeaveSettingsOut(ApiModel):
    final_approval_by: str
    approve_on_status: str
    post_deadline: bool
    row_version: str | None


# --- Leave types -----------------------------------------------------------------------------------


class ExperienceSlab(ApiModel):
    min_months: int = Field(ge=0)
    max_months: int | None = Field(default=None, ge=0)
    balance: Days = Field(ge=0, le=366)


class ShortLeaveSlab(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    balance: Days | None = Field(default=None, ge=0, le=366)
    value_type: Literal["percentage", "flat"]
    value: Number | None = Field(default=None, ge=0)


class LeaveTypeIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    short_code: str = Field(min_length=1, max_length=10)
    allowance: Days = Field(ge=0, le=366)
    is_active: bool = True
    is_probation_type: bool = False
    auto_allotment: bool = False
    auto_balance_on_joining: bool = False
    is_composite: bool = False
    is_short_leave: bool = False
    show_in_payslip: bool = False
    is_deductible: bool = True
    is_sandwich: bool = False
    sandwich_across_types: bool = False
    is_earned: bool = False
    allow_back_date: bool = False
    back_date_limit_days: int | None = Field(default=None, ge=0, le=366)
    has_future_limit: bool = False
    future_limit_days: int | None = Field(default=None, ge=0, le=366)
    attachment_required: bool = False
    attachment_rule: Literal["refuse", "note"] | None = None
    allow_encashment: bool = False
    encashment_min: Days | None = Field(default=None, ge=0, le=366)
    encashment_max: Days | None = Field(default=None, ge=0, le=366)
    carry_forward: bool = False
    pro_rated: bool = False
    gender: Literal["any", "male", "female"] = "any"
    marital_status: Literal["any", "single", "married"] = "any"
    allowed_in_probation: bool = False
    min_experience_months: int | None = Field(default=None, ge=0, le=600)
    max_applications: int | None = Field(default=None, ge=1, le=1000)
    gap_between_applications_months: int | None = Field(default=None, ge=0, le=600)
    tenure: Literal["yearly", "monthly", "employment"] = "yearly"
    balance_basis: Literal["flat", "experience"] = "flat"
    accumulative_count: int | None = Field(default=None, ge=1, le=50)
    experience_slabs: list[ExperienceSlab] = Field(default_factory=list, max_length=50)
    short_slabs: list[ShortLeaveSlab] = Field(default_factory=list, max_length=20)
    row_version: str | None = None


class LeaveTypeOut(ApiModel):
    id: str
    title: str
    short_code: str
    allowance: Days | None
    is_active: bool
    is_probation_type: bool
    auto_allotment: bool
    auto_balance_on_joining: bool
    is_composite: bool
    is_short_leave: bool
    show_in_payslip: bool
    is_deductible: bool
    is_sandwich: bool
    sandwich_across_types: bool
    is_earned: bool
    allow_back_date: bool
    back_date_limit_days: int | None
    has_future_limit: bool
    future_limit_days: int | None
    attachment_required: bool
    attachment_rule: str | None
    allow_encashment: bool
    encashment_min: Days | None
    encashment_max: Days | None
    carry_forward: bool
    pro_rated: bool
    gender: str
    marital_status: str
    allowed_in_probation: bool
    min_experience_months: int | None
    max_applications: int | None
    gap_between_applications_months: int | None
    tenure: str
    balance_basis: str
    accumulative_count: int | None
    experience_slabs: list[ExperienceSlab]
    short_slabs: list[ShortLeaveSlab]
    # Ledger postings, leave requests and policies using the type; a type in use cannot be deleted.
    in_use: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Leave policies --------------------------------------------------------------------------------


class PolicyTypeIn(ApiModel):
    leave_type_id: int
    # Days this policy gives; None = the type's own allowance.
    allowance: Days | None = Field(default=None, ge=0, le=366)


class LeavePolicyIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    # "Policy *": a Leave Distribution Policy or a Half leave & Short leave policy.
    policy_kind: Literal["distribution", "half_short"]
    # Company Level Policy (everyone) or Employee Level Policy (the enrolled).
    policy_level: Literal["company", "employee"]
    allow_half_day: bool = False
    allow_short_leave: bool = False
    is_active: bool = True
    types: list[PolicyTypeIn] = Field(default_factory=list, max_length=100)
    row_version: str | None = None


class PolicyTypeOut(ApiModel):
    leave_type_id: str
    leave_type_title: str
    short_code: str | None = None
    allowance: Days | None = None
    effective_allowance: Days | None = None


class LeavePolicyOut(ApiModel):
    id: str
    title: str
    policy_kind: str
    policy_level: str
    allow_half_day: bool
    allow_short_leave: bool
    is_active: bool
    # "No. of Leaves": the days the policy's types add up to.
    total_leaves: Days | None
    # Company level: everyone in the company; employee level: the people enrolled.
    enrolled_count: int
    types: list[PolicyTypeOut]
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EnrolIn(ApiModel):
    employee_ids: list[int] = Field(min_length=1, max_length=1000)


class EnrolledEmployeeOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    enrolled_at: datetime


# --- Balances and ledger ---------------------------------------------------------------------------


class BalanceOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    leave_type_id: str
    leave_type_title: str
    short_code: str | None
    fiscal_year: int
    entitled: Days
    used: Days
    pending: Days
    available: Days


class LedgerEntryIn(ApiModel):
    employee_id: int
    leave_type_id: int
    entry_date: date
    # + adds days, - takes them away (adjustments); an opening balance is positive.
    days: Days = Field(ge=-366, le=366)
    reason: Literal["opening", "adjustment"]
    remarks: str | None = Field(default=None, max_length=2000)


class LedgerEntryOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    leave_type_id: str
    leave_type_title: str
    short_code: str | None
    fiscal_year: int
    entry_date: date
    days: Days
    reason: str
    remarks: str | None
    request_id: str | None
    request_code: str | None
    leave_encashment_id: str | None
    warning_id: str | None
    created_at: datetime


class AllotmentIn(ApiModel):
    fiscal_year: int = Field(ge=2000, le=2100)
    # Earned balances are topped up to this date (default today, capped at the year end).
    as_of: date | None = None
    leave_type_id: int | None = None
    employee_id: int | None = None


class AllotmentOut(ApiModel):
    fiscal_year: int
    allotted: int
    earned: int
    days: Days


class CarryForwardIn(ApiModel):
    from_fiscal_year: int = Field(ge=2000, le=2100)
    leave_type_id: int | None = None
    employee_id: int | None = None


class CarryForwardOut(ApiModel):
    from_fiscal_year: int
    carried: int
    days: Days


# --- Leave applications (read from the requests module) --------------------------------------------


class LeaveApplicationOut(ApiModel):
    id: str
    code: str
    status: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_id: str | None
    department_name: str | None
    leave_type_id: str
    leave_type_title: str
    leave_type_code: str | None
    from_date: date | None
    to_date: date | None
    days: Days | None
    is_short: bool
    short_leave_type: str | None
    start_time: time | None
    end_time: time | None
    reason: str | None
    submitted_at: datetime | None
    decided_at: datetime | None
    cancel_reason: str | None
    created_at: datetime


class LeaveBalanceOut(ApiModel):
    entitled: Days
    used: Days
    pending: Days
    available: Days


class LeaveApplicationDetailOut(LeaveApplicationOut):
    # The person's balance of this leave type in the leave year the leave starts in.
    balance: LeaveBalanceOut | None


class ApplicationCountsOut(ApiModel):
    all: int
    pending: int
    approved: int
    rejected: int
    cancelling: int
    cancelled: int


# --- Leave encashment ------------------------------------------------------------------------------

Basis = Literal["overtime", "earned_salary", "per_hour_rate", "overnight"]
EncashMode = Literal["payroll", "manual"]


class EncashmentIn(ApiModel):
    leave_type_id: int
    fiscal_year: int = Field(ge=2000, le=2100)
    encashment_date: date
    applies_to_all: bool = False
    employee_ids: list[int] = Field(default_factory=list, max_length=5000)
    basis: Basis
    amount_per_leave: Number = Field(ge=0, max_digits=18, decimal_places=2)
    mode: EncashMode


class EncashmentUpdateIn(ApiModel):
    encashment_date: date
    basis: Basis
    amount_per_leave: Number = Field(ge=0, max_digits=18, decimal_places=2)
    mode: EncashMode
    row_version: str | None = None


class EncashmentLineOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    days: Days
    amount: Number
    payslip_id: str | None


class EncashmentOut(ApiModel):
    id: str
    leave_type_id: str
    leave_type_title: str
    short_code: str | None
    fiscal_year: int
    encashment_date: date
    applies_to_all: bool
    basis: str
    amount_per_leave: Number
    mode: str
    employee_count: int
    total_days: Days
    total_amount: Number
    paid_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EncashmentDetailOut(EncashmentOut):
    lines: list[EncashmentLineOut]
