from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import Field, PlainSerializer

from app.schemas.common import ApiModel

Number = Annotated[Decimal, PlainSerializer(float, return_type=float, when_used="json")]
AppliesTo = Literal["late_arrival", "early_departure", "overtime", "half_day_leave"]
Weekday = Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
ClockEvent = Literal["clock_in", "clock_out"]


class PolicyRuleIn(ApiModel):
    clock_event: ClockEvent
    # Minutes past the expected time a day may be off before it counts (per occurrence).
    minutes: int = Field(default=0, ge=0, le=1440)
    # Every n-th occurrence in the period raises a warning.
    occurrence_count: int = Field(default=1, ge=1, le=100)


class WarningPolicyIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    applies_to: AppliesTo
    period: Literal["day", "week", "month", "year"]
    # Total Grace Minutes in a period before days start to count.
    grace_minutes: int | None = Field(default=None, ge=0, le=100000)
    week_start_day: Weekday | None = None
    week_end_day: Weekday | None = None
    is_active: bool = True
    rules: list[PolicyRuleIn] = Field(min_length=1, max_length=2)
    row_version: str | None = None


class PenaltyRuleIn(ApiModel):
    # The n-th warning in the period that this penalty applies to.
    after_count: int = Field(ge=1, le=100)
    period: Literal["week", "month", "year"]
    penalty_type: Literal["half_day", "full_day", "percentage"]
    # Share of a day; set from the type for half_day (50) and full_day (100).
    percentage: Number | None = Field(default=None, gt=0, le=100)
    deduction: Literal["payroll", "leave", "both"]
    # The balance a leave deduction is taken from.
    leave_type_id: int | None = None


class PenaltiesIn(ApiModel):
    penalties: list[PenaltyRuleIn] = Field(max_length=50)
    row_version: str | None = None


class PolicyRuleOut(ApiModel):
    clock_event: str
    minutes: int
    occurrence_count: int


class PenaltyRuleOut(ApiModel):
    id: str
    after_count: int
    period: str
    penalty_type: str
    percentage: Number
    deduction: str
    leave_type_id: str | None = None
    leave_type_title: str | None = None


class WarningPolicyOut(ApiModel):
    id: str
    title: str
    applies_to: str
    period: str
    grace_minutes: int | None
    week_start_day: str | None
    week_end_day: str | None
    is_active: bool
    rules: list[PolicyRuleOut]
    penalties: list[PenaltyRuleOut]
    warning_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class PenaltyListOut(ApiModel):
    id: str
    warning_policy_id: str
    policy_title: str
    applies_to: str
    after_count: int
    period: str
    penalty_type: str
    percentage: Number
    deduction: str
    leave_type_id: str | None
    leave_type_title: str | None
    created_at: datetime


class WarningOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    warning_policy_id: str
    policy_title: str
    applies_to: str
    period: str
    clock_event: str
    timesheet_day_id: str
    work_date: date
    minutes: int | None
    occurrence_no: int | None
    penalty_rule_id: str | None
    penalty_type: str | None
    penalty_percentage: Number | None
    deduction: str | None
    payslip_id: str | None
    created_at: datetime


class RaiseIn(ApiModel):
    from_date: date
    to_date: date
    employee_id: int | None = None
    warning_policy_id: int | None = None


class RaiseOut(ApiModel):
    raised: int
    penalised: int
    # The whole calendar years worked out again.
    from_date: date
    to_date: date


class HistoryOut(ApiModel):
    id: str
    performed_at: datetime | None
    action_name: str | None
    policy_id: str | None
    policy_title: str | None
    field_name: str | None
    old_value: str | None
    new_value: str | None
    performed_by_user_id: str | None
    performed_by_name: str | None
