"""Request and response bodies for /api/attendance. Date-times are the company's local wall-clock time
(yyyy-mm-ddThh:mm:ss, no zone), like the schedules they are compared with."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel, PageMeta
from app.schemas.files import FileRef

PunchType = Literal["check_in", "check_out", "break_out", "break_in"]
PunchSource = Literal["biometric", "mobile", "web", "manual", "import_file", "punch_request"]
DayStatus = Literal["present", "absent", "holiday", "weekend", "rest_day", "leave", "half_day", "short_day", "wfh",
                    "official_visit", "sandwich", "yet_to_start"]
Flag = Literal["late", "early", "grace", "overtime", "missing_punch", "relaxation", "official_visit", "half_leave",
               "short_leave"]
TargetType = Literal["employee", "country", "location", "branch", "area", "department", "designation", "grade",
                     "job_title", "religion", "nationality"]


# ---------------------------------------------------------------- devices

class DeviceIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    model: str | None = Field(None, max_length=100)
    serial_no: str | None = Field(None, max_length=50)
    ip_address: str | None = Field(None, max_length=45)
    port: int | None = Field(None, ge=1, le=65535)
    branch_id: int | None = None
    address: str | None = Field(None, max_length=500)
    status: Literal["active", "inactive"] = "active"
    row_version: str | None = None


class DeviceOut(ApiModel):
    id: str
    code: str
    name: str
    model: str | None
    serial_no: str | None
    ip_address: str | None
    port: int | None
    branch_id: str | None
    branch_name: str | None
    address: str | None
    status: str
    last_synced_at: datetime | None
    enrolled_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EnrolmentIn(ApiModel):
    employee_id: int
    device_user_no: str = Field(min_length=1, max_length=30)


class EnrolmentsIn(ApiModel):
    enrolments: list[EnrolmentIn] = Field(max_length=20000)
    # The device's rowVersion from the last read.
    row_version: str | None = None


class EnrolmentOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    device_user_no: str
    created_at: datetime


# ---------------------------------------------------------------- punches

class DevicePunchLine(ApiModel):
    line: int | None = None
    device_user_no: str = Field(min_length=1, max_length=30)
    punched_at: str = Field(min_length=1, max_length=40)
    # check_in, check_out, break_out, break_in, or a break type's start / end identifier.
    punch_type: str | None = Field(None, max_length=100)


class DevicePunchesIn(ApiModel):
    lines: list[DevicePunchLine] = Field(min_length=1, max_length=20000)


class FilePunchLine(ApiModel):
    line: int | None = None
    employee_code: str = Field(min_length=1, max_length=30)
    punched_at: str = Field(min_length=1, max_length=40)
    punch_type: str | None = Field(None, max_length=100)


class FilePunchesIn(ApiModel):
    lines: list[FilePunchLine] = Field(min_length=1, max_length=20000)


class ImportLineError(ApiModel):
    line: int
    message: str


class ImportResultOut(ApiModel):
    created: int
    skipped: int
    failed: int
    errors: list[ImportLineError]


class PunchIn(ApiModel):
    employee_id: int
    punched_at: datetime
    punch_type: PunchType
    break_type_id: int | None = None
    remarks: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class PunchIgnoreIn(ApiModel):
    is_ignored: bool
    row_version: str | None = None


class PunchOut(ApiModel):
    __local_times__ = frozenset({'punched_at'})  # wall-clock, no zone
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    punched_at: datetime
    punch_type: str
    break_type_id: str | None
    break_type_name: str | None
    source: str
    device_id: str | None
    device_code: str | None
    device_name: str | None
    latitude: Decimal | None
    longitude: Decimal | None
    ip_address: str | None
    photo_file_id: str | None
    # The clock-in photo: id, name and a signed link (expires).
    photo: FileRef | None = None
    request_id: str | None
    remarks: str | None
    is_manually_updated: bool
    is_ignored: bool
    # Manual and imported punches can be edited or deleted; the others can only be ignored.
    editable: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- clock in / out

class ClockIn(ApiModel):
    # Omitted: the opposite of the last punch (check in, then check out).
    punch_type: Literal["check_in", "check_out"] | None = None
    source: Literal["web", "mobile"] = "web"
    latitude: Decimal | None = Field(None, ge=-90, le=90)
    longitude: Decimal | None = Field(None, ge=-180, le=180)
    # An uploaded picture (POST /api/files, module attendance): its id.
    photo_file_id: int | None = None


class ClockStateOut(ApiModel):
    __local_times__ = frozenset({'now', 'last_punched_at', 'expected_in', 'expected_out'})  # wall-clock, no zone
    # "Employee can mark punch from their dashboard" is on and the user is an employee.
    allowed: bool
    reason: str | None
    photo_required: bool
    location_required: bool
    employee_id: str | None
    employee_name: str | None
    now: datetime
    clocked_in: bool
    next_punch_type: str
    last_punch_type: str | None
    last_punched_at: datetime | None
    expected_in: datetime | None
    expected_out: datetime | None


# ---------------------------------------------------------------- time sheet

class TimesheetDayOut(ApiModel):
    __local_times__ = frozenset({'expected_in', 'expected_out', 'first_in', 'last_out'})  # wall-clock, no zone
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    work_date: date
    schedule_id: str | None
    time_slot_id: str | None
    time_slot_name: str | None
    expected_in: datetime | None
    expected_out: datetime | None
    expected_minutes: int | None
    first_in: datetime | None
    last_out: datetime | None
    worked_minutes: int | None
    break_minutes: int | None
    shift_worked_minutes: int | None
    late_minutes: int | None
    early_left_minutes: int | None
    overtime_before_minutes: int | None
    overtime_after_minutes: int | None
    approved_overtime_minutes: int | None
    grace_consumed_minutes: int | None
    day_status: str
    marked_status: str | None
    leave_request_id: str | None
    is_manually_updated: bool
    is_frozen: bool
    comments: str | None
    processed_at: datetime | None
    flags: list[str]
    # Warnings raised on the day (att.warning) and the heaviest penalty among them (Warnings / Penalty columns).
    warning_count: int
    penalty_type: str | None
    penalty_percentage: Decimal | None
    # Chips of the time sheet: on_time, grace, late, early, overtime, missing, absent (null: nothing to show).
    clock_in_status: str | None
    clock_out_status: str | None
    row_version: str


class FlagOut(ApiModel):
    flag: str
    minutes: int | None


class BreakOut(ApiModel):
    __local_times__ = frozenset({'out_at', 'in_at'})  # wall-clock, no zone
    id: str
    break_type_id: str | None
    break_type_name: str | None
    out_at: datetime
    in_at: datetime | None
    minutes: int | None


class DayDetailOut(ApiModel):
    day: TimesheetDayOut
    flags: list[FlagOut]
    breaks: list[BreakOut]
    punches: list[PunchOut]


class BreakIn(ApiModel):
    break_type_id: int | None = None
    out_at: datetime
    in_at: datetime | None = None


class DayEditIn(ApiModel):
    # Partial update: a field not sent keeps its value; send null to clear it.
    expected_in: datetime | None = None
    expected_out: datetime | None = None
    first_in: datetime | None = None
    last_out: datetime | None = None
    # Mark Absent / Mark Half Day / Mark Short Day; null = computed.
    marked_status: Literal["absent", "half_day", "short_day"] | None = None
    comments: str | None = Field(None, max_length=4000)
    breaks: list[BreakIn] | None = Field(None, max_length=50)
    row_version: str | None = None


class HistoryOut(ApiModel):
    id: str
    field_name: str | None
    old_value: str | None
    new_value: str | None
    action_name: str | None
    performed_at: datetime | None
    performed_by_user_id: str | None
    performed_by_name: str | None


class SummaryOut(ApiModel):
    from_date: date
    to_date: date
    total_days: int
    employees: int
    present: int
    absent: int
    holiday: int
    weekend: int
    rest_day: int
    leave: int
    half_day: int
    short_day: int
    wfh: int
    official_visit: int
    sandwich: int
    yet_to_start: int
    late_arrival: int
    early_left: int
    missing_punch: int
    worked_minutes: int
    overtime_minutes: int
    approved_overtime_minutes: int


class ProcessIn(ApiModel):
    from_date: date
    to_date: date
    # Omitted: every employee the caller may process.
    employee_ids: list[int] | None = Field(None, max_length=5000)
    # Recompute days HR edited by hand, dropping the edits.
    overwrite_manual: bool = False


class ProcessOut(ApiModel):
    processed_days: int
    employees: int


class OverviewTotals(ApiModel):
    total_days: int
    present: int
    absent: int
    holiday: int
    days_off: int
    leave: int
    late_arrival: int
    early_left: int


class OverviewRowOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    designation_name: str | None
    employee_status: str | None
    totals: OverviewTotals
    # yyyy-mm-dd -> day status; days not processed are missing.
    days: dict[str, str]


class OverviewPageOut(ApiModel):
    data: list[OverviewRowOut]
    meta: PageMeta
    days: list[date]


# ---------------------------------------------------------------- settings

class BasicSettings(ApiModel):
    ignore_punch_type: bool = False
    use_check_in_out_for_breaks: bool = False
    short_duration_on_non_flexible: bool = False
    # "Employee can mark punch from their dashboard" (web and mobile Clock In / Clock Out).
    dashboard_punch: bool = False
    # "Allow Multi Shift on single day" (scheduling reads this key).
    allow_multi_shift: bool = False
    picture_on_dashboard_punch: bool = False
    minimum_workable_minutes: int = Field(0, ge=0, le=1440)
    # Minutes after the expected start that do not count as late.
    late_grace_minutes: int = Field(0, ge=0, le=240)
    row_version: str | None = None


class OvertimeSettings(ApiModel):
    overtime_on_check_in: bool = False
    overtime_on_check_out: bool = False
    overtime_approval_required: bool = False
    do_not_auto_create_requests: bool = False
    overtime_on_holidays: bool = False
    overtime_after_duty_duration: bool = False
    # "Shift Hours For Overtime Encashment", in minutes.
    encashment_shift_minutes: int = Field(0, ge=0, le=1440)
    row_version: str | None = None


class TargetIn(ApiModel):
    target_type: TargetType
    target_id: int | None = None
    target_value: str | None = Field(None, max_length=200)


class TargetOut(ApiModel):
    target_type: str
    target_id: str | None
    target_value: str | None


class IpRestrictionIn(ApiModel):
    ipv4: str | None = Field(None, max_length=45)
    ipv6: str | None = Field(None, max_length=45)
    netmask: str | None = Field(None, max_length=45)
    range_start: str | None = Field(None, max_length=45)
    range_end: str | None = Field(None, max_length=45)
    applies_to_all: bool = True
    is_active: bool = True
    targets: list[TargetIn] = Field(default_factory=list, max_length=1000)
    row_version: str | None = None


class IpRestrictionOut(ApiModel):
    id: str
    code: str
    ipv4: str | None
    ipv6: str | None
    netmask: str | None
    range_start: str | None
    range_end: str | None
    applies_to_all: bool
    is_active: bool
    # How many addresses it allows (the design's "Count").
    address_count: int | None
    target_count: int
    targets: list[TargetOut] | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class GeoPoint(ApiModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class GeoFenceIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    shape: Literal["circle", "polygon"]
    center_lat: Decimal | None = Field(None, ge=-90, le=90)
    center_lng: Decimal | None = Field(None, ge=-180, le=180)
    radius_m: int | None = Field(None, gt=0, le=100000)
    polygon_points: list[GeoPoint] | None = Field(None, max_length=500)
    applies_to_all: bool = True
    joining_from_date: date | None = None
    joining_to_date: date | None = None
    is_for_shift: bool = False
    is_active: bool = True
    targets: list[TargetIn] = Field(default_factory=list, max_length=1000)
    row_version: str | None = None


class GeoFenceOut(ApiModel):
    id: str
    code: str
    name: str
    shape: str
    center_lat: Decimal | None
    center_lng: Decimal | None
    radius_m: int | None
    polygon_points: list[GeoPoint] | None
    applies_to_all: bool
    joining_from_date: date | None
    joining_to_date: date | None
    is_for_shift: bool
    is_active: bool
    target_count: int
    targets: list[TargetOut] | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class OvertimeSlabIn(ApiModel):
    min_minutes: int = Field(ge=0)
    max_minutes: int = Field(ge=0)
    encashment_type: Literal["full_day", "leave"]
    leave_type_id: int | None = None


class OvertimeSlabOut(ApiModel):
    id: str
    min_minutes: int
    max_minutes: int
    encashment_type: str
    leave_type_id: str | None
    leave_type_name: str | None


class OvertimePolicyIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    period: Literal["daily", "monthly"]
    description: str | None = Field(None, max_length=4000)
    is_active: bool = True
    slabs: list[OvertimeSlabIn] = Field(default_factory=list, max_length=100)
    row_version: str | None = None


class OvertimePolicyOut(ApiModel):
    id: str
    name: str
    period: str
    description: str | None
    is_active: bool
    slab_count: int
    slabs: list[OvertimeSlabOut] | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str
