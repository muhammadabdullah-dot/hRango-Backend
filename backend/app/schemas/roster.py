from datetime import date, datetime, time
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel


class RosterDayIn(ApiModel):
    # 1 = Monday ... 7 = Sunday. A weekday left out of the list is a day off.
    weekday: int = Field(ge=1, le=7)
    is_day_off: bool = False
    # Required on a working day.
    time_slot_id: int | None = None


class RosterGroupIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    from_date: date
    # Blank = open-ended.
    to_date: date | None = None
    description: str | None = None
    is_active: bool = True
    days: list[RosterDayIn] = Field(min_length=1, max_length=7)
    row_version: str | None = None


class RosterDayOut(ApiModel):
    weekday: int
    is_day_off: bool
    time_slot_id: str | None
    time_slot_code: str | None
    time_slot_name: str | None
    start_time: time | None
    end_time: time | None
    is_overnight: bool | None
    duration_minutes: int | None
    workable_minutes: int | None


class RosterGroupOut(ApiModel):
    id: str
    title: str
    from_date: date
    to_date: date | None
    description: str | None
    is_active: bool
    # Employees enrolled now or later (not discontinued).
    enrolled_count: int
    # On the list only.
    working_days: int | None = None
    # On the single item only: always seven days, Monday first.
    days: list[RosterDayOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EnrolIn(ApiModel):
    employee_ids: list[int] = Field(min_length=1, max_length=1000)
    start_date: date
    # Blank = the roster group's end (or open-ended).
    end_date: date | None = None


class EnrolmentEditIn(ApiModel):
    start_date: date
    end_date: date | None = None
    row_version: str | None = None


class DiscontinueIn(ApiModel):
    # The last day on the roster; today when blank.
    end_date: date | None = None
    row_version: str | None = None


class EnrolmentOut(ApiModel):
    id: str
    roster_group_id: str
    roster_group_title: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    designation_name: str | None
    branch_name: str | None
    start_date: date
    end_date: date | None
    status: Literal["active", "discontinued"]
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EnrolmentList(ApiModel):
    data: list[EnrolmentOut]
