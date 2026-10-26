from datetime import date, datetime, time
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel, PageMeta

# ---------------------------------------------------------------- settings: time slots and break types


class BreakIn(ApiModel):
    break_type_id: int
    start_time: time
    end_time: time
    # The break counts as working time (it is not taken off the planned minutes).
    is_inclusive: bool = False


class TimeSlotIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    color: str | None = Field(None, max_length=20)
    start_time: time
    # At or before the start time = ends the next day (overnight).
    end_time: time
    # Flexible slots only: the minutes to work inside the window. Fixed slots: computed.
    workable_minutes: int | None = Field(None, ge=1, le=1440)
    is_flexible: bool = False
    full_overtime: bool = False
    short_overtime: bool = False
    breaks: list[BreakIn] = Field(default_factory=list, max_length=20)
    row_version: str | None = None


class TimeSlotBreakOut(ApiModel):
    id: str
    break_type_id: str
    break_type_name: str
    start_time: time
    end_time: time
    is_inclusive: bool


class TimeSlotOut(ApiModel):
    id: str
    code: str
    name: str
    color: str | None
    start_time: time
    end_time: time
    duration_minutes: int
    workable_minutes: int
    is_flexible: bool
    is_overnight: bool
    full_overtime: bool
    short_overtime: bool
    # On the list only.
    break_count: int | None = None
    # On the single item only.
    breaks: list[TimeSlotBreakOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class BreakTypeIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    # What a device or a log sends at the start (break out) and the end (break in) of the break.
    start_identifier: str = Field(min_length=1, max_length=50)
    end_identifier: str = Field(min_length=1, max_length=50)
    row_version: str | None = None


class BreakTypeOut(ApiModel):
    id: str
    name: str
    start_identifier: str
    end_identifier: str
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- settings: rest days and holidays


class RestDayRuleIn(ApiModel):
    from_date: date
    to_date: date
    # 1 = Monday ... 7 = Sunday.
    weekdays: list[int] = Field(min_length=1, max_length=7)
    # 0 = every week in the range; n = a cycle of n weeks of which the first `step` weeks are on.
    repeat_every_weeks: int = Field(0, ge=0, le=8)
    step: int = Field(1, ge=1, le=8)
    is_payable: bool = False
    employee_ids: list[int] = Field(min_length=1, max_length=5000)
    row_version: str | None = None


class RuleEmployeeOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    designation_name: str | None


class RestDayRuleOut(ApiModel):
    id: str
    from_date: date
    to_date: date
    weekdays: list[int]
    repeat_every_weeks: int
    step: int
    is_payable: bool
    employee_count: int
    # Rest days this rule made (dates already rest days from elsewhere are not counted).
    rest_day_count: int
    employees: list[RuleEmployeeOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class RestDayRangeDeleteIn(ApiModel):
    start_date: date
    end_date: date
    employee_ids: list[int] = Field(default_factory=list, max_length=5000)
    all_employees: bool = False


HolidayRuleType = Literal["employee", "org_structure", "geo_location", "religion"]


class HolidayRuleIn(ApiModel):
    rule_type: HolidayRuleType
    employee_id: int | None = None
    location_id: int | None = None
    branch_id: int | None = None
    country_id: int | None = None
    state_id: int | None = None
    city_id: int | None = None
    religion: str | None = Field(None, max_length=50)


class HolidayIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    holiday_type: Literal["public", "local"]
    start_date: date
    end_date: date
    description: str | None = None
    # On: the day is a holiday in the time sheet. Off: listed, but still a working day.
    attendance_exempt: bool = False
    # Who the holiday applies to; none = everyone.
    rules: list[HolidayRuleIn] = Field(default_factory=list, max_length=500)
    row_version: str | None = None


class HolidayRuleOut(ApiModel):
    id: str
    rule_type: HolidayRuleType
    employee_id: str | None
    employee_name: str | None
    location_id: str | None
    location_name: str | None
    branch_id: str | None
    branch_name: str | None
    country_id: str | None
    country_name: str | None
    state_id: str | None
    state_name: str | None
    city_id: str | None
    city_name: str | None
    religion: str | None


class HolidayOut(ApiModel):
    id: str
    name: str
    holiday_type: str
    start_date: date
    end_date: date
    description: str | None
    attendance_exempt: bool
    day_count: int
    # On the list only.
    rule_count: int | None = None
    # On the single item only.
    rules: list[HolidayRuleOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- schedules


class ScheduleBatchIn(ApiModel):
    """Create Scheduling: one time slot, or a roster group's weekly pattern, over a date range."""
    start_date: date
    end_date: date
    time_slot_id: int | None = None
    roster_group_id: int | None = None
    # 1 = Monday ... 7 = Sunday; empty = every day.
    weekdays: list[int] = Field(default_factory=list, max_length=7)
    # Repeat: 0 = never, 1..8 = every n weeks; `step` = weeks on in each cycle.
    repeat_every_weeks: int = Field(0, ge=0, le=8)
    step: int = Field(1, ge=1, le=8)
    geo_fence_id: int | None = None
    is_wfh: bool = False
    # With a roster group and no employees: its members enrolled on each date.
    employee_ids: list[int] = Field(default_factory=list, max_length=5000)
    # Replace the time slots' breaks on every shift of the batch.
    breaks: list[BreakIn] | None = None
    # Replace shifts already planned on these dates instead of refusing.
    replace_existing: bool = False


class DefaultShiftIn(ApiModel):
    """Apply Default Shift: each employee's roster (when enrolled) or default time slot, every day."""
    start_date: date
    end_date: date
    employee_ids: list[int] = Field(min_length=1, max_length=5000)
    replace_existing: bool = False


class ScheduleBatchOut(ApiModel):
    id: str
    batch_kind: str
    start_date: date
    end_date: date
    time_slot_id: str | None
    time_slot_name: str | None
    roster_group_id: str | None
    roster_group_title: str | None
    weekdays: list[int]
    repeat_every_weeks: int
    step: int
    geo_fence_id: str | None
    is_wfh: bool
    created_count: int
    replaced_count: int
    skipped_rest_days: int
    skipped_no_shift: int
    created_at: datetime


class ScheduleIn(ApiModel):
    # Required when adding; an edit keeps the employee (use swap to move a shift to someone else).
    employee_id: int | None = None
    work_date: date
    time_slot_id: int
    # Both or neither: other times than the slot's for this day.
    start_time: time | None = None
    end_time: time | None = None
    geo_fence_id: int | None = None
    is_wfh: bool = False
    # This shift's breaks; leave out to take the time slot's breaks.
    breaks: list[BreakIn] | None = None
    row_version: str | None = None


class ScheduleBreakOut(ApiModel):
    __local_times__ = frozenset({'start_at', 'end_at'})  # wall-clock, no zone
    id: str
    break_type_id: str
    break_type_name: str
    start_at: datetime
    end_at: datetime
    is_inclusive: bool


class ScheduleOut(ApiModel):
    __local_times__ = frozenset({'start_at', 'end_at'})  # wall-clock, no zone
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    work_date: date
    # Local wall-clock date-times; end_at is the next day for an overnight shift.
    start_at: datetime
    end_at: datetime
    time_slot_id: str
    time_slot_code: str
    time_slot_name: str
    time_slot_color: str | None
    is_flexible: bool
    is_overnight: bool
    full_overtime: bool
    short_overtime: bool
    schedule_batch_id: str | None
    geo_fence_id: str | None
    geo_fence_name: str | None
    is_wfh: bool
    planned_minutes: int
    is_rest_day: bool
    breaks: list[ScheduleBreakOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class SwapIn(ApiModel):
    # Swap with this shift of another employee, or give the shift to `with_employee_id` on its date.
    with_schedule_id: int | None = None
    with_employee_id: int | None = None
    row_version: str | None = None


class BulkDeleteIn(ApiModel):
    # Either these shifts (Multi Delete) ...
    ids: list[int] | None = Field(None, max_length=5000)
    # ... or a date range for some employees or everyone (Delete Scheduling).
    start_date: date | None = None
    end_date: date | None = None
    employee_ids: list[int] = Field(default_factory=list, max_length=5000)
    all_employees: bool = False
    # Also delete rest days in the range (date range only).
    delete_rest_days: bool = False


class BulkDeleteOut(ApiModel):
    deleted_schedules: int
    deleted_rest_days: int


class BulkEditIn(ApiModel):
    ids: list[int] = Field(min_length=1, max_length=5000)
    time_slot_id: int | None = None
    geo_fence_id: int | None = None
    clear_geo_fence: bool = False
    is_wfh: bool | None = None


class BulkEditOut(ApiModel):
    updated_schedules: int


# ---------------------------------------------------------------- the board


class BoardEmployeeOut(ApiModel):
    id: str
    code: str
    name: str
    designation_name: str | None
    department_name: str | None
    status: str
    default_time_slot_id: str | None
    default_time_slot_name: str | None
    # Planned minutes and shifts in the requested range.
    planned_minutes: int
    shift_count: int


class BoardShiftOut(ApiModel):
    __local_times__ = frozenset({'start_at', 'end_at'})  # wall-clock, no zone
    id: str
    work_date: date
    start_at: datetime
    end_at: datetime
    time_slot_id: str
    time_slot_code: str
    time_slot_name: str
    time_slot_color: str | None
    is_flexible: bool
    is_overnight: bool
    geo_fence_id: str | None
    geo_fence_name: str | None
    is_wfh: bool
    planned_minutes: int
    schedule_batch_id: str | None
    row_version: str


class BoardRestDayOut(ApiModel):
    id: str
    rest_date: date
    is_payable: bool
    rest_day_rule_id: str | None
    request_id: str | None


class BoardHolidayOut(ApiModel):
    holiday_date: date
    holiday_id: str
    holiday_name: str
    holiday_type: str
    attendance_exempt: bool


class BoardRowOut(ApiModel):
    employee: BoardEmployeeOut
    shifts: list[BoardShiftOut]
    rest_days: list[BoardRestDayOut]
    holidays: list[BoardHolidayOut]


class DayTotalOut(ApiModel):
    work_date: date
    planned_minutes: int
    shift_count: int


class BoardPage(ApiModel):
    data: list[BoardRowOut]
    meta: PageMeta
    # Planned minutes per date over every matching employee (not just this page).
    day_totals: list[DayTotalOut]


class YearMonthOut(ApiModel):
    month: int
    planned_minutes: int
    shift_count: int
    rest_days: int


class YearRowOut(ApiModel):
    employee: BoardEmployeeOut
    months: list[YearMonthOut]


class YearPage(ApiModel):
    data: list[YearRowOut]
    meta: PageMeta


# ---------------------------------------------------------------- pickers


class OptionOut(ApiModel):
    id: str
    name: str
    code: str | None = None
    start_time: time | None = None
    end_time: time | None = None
    is_overnight: bool | None = None
    is_flexible: bool | None = None


class OptionList(ApiModel):
    data: list[OptionOut]
