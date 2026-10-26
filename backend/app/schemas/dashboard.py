from datetime import date, datetime
from decimal import Decimal

from app.schemas.common import ApiModel


class CountItem(ApiModel):
    id: str | None = None
    name: str
    count: int


class GenderCount(ApiModel):
    gender: str
    count: int


class AgeBand(ApiModel):
    band: str
    male: int
    female: int
    other: int


class MonthTurnover(ApiModel):
    month: date
    hired: int
    left: int


class DepartmentGender(ApiModel):
    id: str | None
    name: str
    men: int
    women: int


class JobTitleWomen(ApiModel):
    id: str | None
    name: str
    total: int
    women: int
    women_percent: float


class Workforce(ApiModel):
    """Employee figures (CEO and HR dashboards). Employed = active, probation or notice."""
    month: date
    headcount: int
    women: int
    men: int
    women_percent: float
    hired: int
    left: int
    # Left in the month over the average of the month's opening and current headcount, in percent.
    turnover_percent: float
    by_department: list[CountItem]
    by_employment_type: list[CountItem]
    by_gender: list[GenderCount]
    by_age: list[AgeBand]
    turnover_by_month: list[MonthTurnover]
    by_department_gender: list[DepartmentGender]
    women_by_job_title: list[JobTitleWomen]


class MonthAttendance(ApiModel):
    month: int
    present: int
    absent: int
    on_leave: int


class AttendanceRow(ApiModel):
    __local_times__ = frozenset({'first_in', 'last_out'})  # wall-clock, no zone
    employee_id: str
    employee_name: str
    designation_name: str | None
    first_in: datetime | None
    last_out: datetime | None
    status: str | None


class Attendance(ApiModel):
    """From the time sheet: present (present, half day, short day, WFH, official visit), absent, on leave."""
    day: date
    present: int
    absent: int
    on_leave: int
    absenteeism_percent: float
    by_month: list[MonthAttendance]
    rows: list[AttendanceRow]


class LeaveApplication(ApiModel):
    id: str
    employee_id: str
    employee_name: str
    designation_name: str | None
    applied_at: datetime | None
    from_date: date | None
    to_date: date | None
    days: Decimal | None
    reason: str | None
    status: str


class Notice(ApiModel):
    id: str
    kind: str
    title: str
    body: str | None
    event_date: date | None
    publish_from: date | None
    created_at: datetime


class CeoDashboard(ApiModel):
    workforce: Workforce
    attendance: Attendance
    leave_applications: list[LeaveApplication]


class HrDashboard(ApiModel):
    workforce: Workforce
    attendance: Attendance
    leave_applications: list[LeaveApplication]
    notice_board: list[Notice]
    upcoming_events: list[Notice]


class MyDashboard(ApiModel):
    employee_id: str | None
    attendance: Attendance
    leave_applications: list[LeaveApplication]
    notice_board: list[Notice]
    upcoming_events: list[Notice]
