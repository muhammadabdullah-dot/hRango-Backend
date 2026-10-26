from datetime import date, datetime, time
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import Field, PlainSerializer

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

# Exact in Python (DECIMAL in the database), sent as JSON numbers.
Number = Annotated[Decimal, PlainSerializer(float, return_type=float, when_used="json")]

# --- Settings ------------------------------------------------------------------------------------


class TrainingSettingsIn(ApiModel):
    # Share of the session days a participant must attend to complete the training.
    min_attendance_percent: Number = Field(ge=0, le=100)
    # Staff may nominate themselves (the nomination still waits for approval).
    allow_self_nomination: bool = True
    row_version: str | None = None


class TrainingSettingsOut(ApiModel):
    min_attendance_percent: Number
    allow_self_nomination: bool
    row_version: str | None


class CategoryIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    is_active: bool = True
    row_version: str | None = None


class CategoryOut(ApiModel):
    id: str
    name: str
    is_active: bool
    in_use: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Programs ------------------------------------------------------------------------------------


class ProgramIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    training_category_id: int | None = None
    description: str | None = Field(default=None, max_length=8000)
    delivery_mode: Literal["classroom", "online", "blended", "on_the_job"] = "classroom"
    provider_type: Literal["internal", "external"] = "internal"
    provider_name: str | None = Field(default=None, max_length=200)
    duration_hours: Number | None = Field(default=None, ge=0, le=9999)
    cost_per_head: Number | None = Field(default=None, ge=0)
    issues_certificate: bool = False
    # Certificates expire after this many months; empty = never.
    certificate_validity_months: int | None = Field(default=None, ge=1, le=600)
    is_mandatory: bool = False
    is_active: bool = True
    row_version: str | None = None


class MaterialIn(ApiModel):
    file_id: int
    label: str | None = Field(default=None, max_length=200)


class MaterialOut(ApiModel):
    id: str
    file_id: str
    name: str
    label: str | None = None
    mime_type: str
    size_bytes: int
    url: str


class ProgramOut(ApiModel):
    id: str
    title: str
    training_category_id: str | None
    training_category_name: str | None
    description: str | None
    delivery_mode: str | None
    provider_type: str | None
    provider_name: str | None
    duration_hours: Number | None
    cost_per_head: Number | None
    issues_certificate: bool
    certificate_validity_months: int | None
    is_mandatory: bool
    is_active: bool
    materials: list[MaterialOut]
    sessions: int
    upcoming_sessions: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Sessions ------------------------------------------------------------------------------------


class SessionIn(ApiModel):
    training_program_id: int
    # Empty = the program's title.
    title: str | None = Field(default=None, max_length=200)
    start_date: date
    end_date: date
    start_time: time | None = None
    end_time: time | None = None
    delivery_mode: Literal["classroom", "online"] = "classroom"
    venue: str | None = Field(default=None, max_length=300)
    online_link: str | None = Field(default=None, max_length=500)
    trainer_type: Literal["internal", "external"] = "internal"
    trainer_employee_id: int | None = None
    trainer_name: str | None = Field(default=None, max_length=200)
    # Seats; empty = no limit.
    capacity: int | None = Field(default=None, ge=1, le=10000)
    nomination_deadline: date | None = None
    cost: Number | None = Field(default=None, ge=0)
    row_version: str | None = None


class SessionOut(ApiModel):
    id: str
    training_program_id: str
    program_title: str
    title: str
    start_date: date
    end_date: date
    session_days: int
    start_time: time | None
    end_time: time | None
    delivery_mode: str | None
    venue: str | None
    online_link: str | None
    trainer_type: str | None
    trainer_employee_id: str | None
    trainer_name: str | None
    trainer_display_name: str | None
    capacity: int | None
    seats_taken: int
    seats_left: int | None
    requested: int
    nomination_deadline: date | None
    status: str
    cost: Number | None
    cancel_reason: str | None
    completed_at: datetime | None
    cancelled_at: datetime | None
    average_rating: Number | None
    feedback_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class CancelIn(ApiModel):
    reason: str | None = Field(default=None, max_length=4000)
    row_version: str


class RowVersionIn(ApiModel):
    row_version: str


# --- Enrolments ----------------------------------------------------------------------------------


class NominateIn(ApiModel):
    training_session_id: int
    # Empty = the signed-in employee nominates themselves.
    employee_ids: list[int] = Field(default_factory=list, max_length=500)
    remarks: str | None = Field(default=None, max_length=4000)


class DecisionIn(ApiModel):
    remarks: str | None = Field(default=None, max_length=4000)
    row_version: str


class CompleteIn(ApiModel):
    score: Number | None = Field(default=None, ge=0, le=100)
    remarks: str | None = Field(default=None, max_length=4000)
    row_version: str


class CertificateIn(ApiModel):
    file_id: int
    certificate_no: str | None = Field(default=None, max_length=100)
    issued_date: date
    row_version: str


class FeedbackIn(ApiModel):
    overall_rating: int = Field(ge=1, le=5)
    trainer_rating: int | None = Field(default=None, ge=1, le=5)
    content_rating: int | None = Field(default=None, ge=1, le=5)
    comments: str | None = Field(default=None, max_length=4000)


class AttendanceDayOut(ApiModel):
    attendance_date: date
    status: str
    remarks: str | None


class FeedbackOut(ApiModel):
    overall_rating: int
    trainer_rating: int | None
    content_rating: int | None
    comments: str | None
    created_at: datetime
    updated_at: datetime | None


class EnrolmentOut(ApiModel):
    id: str
    training_session_id: str
    session_title: str
    start_date: date
    end_date: date
    session_status: str
    training_program_id: str
    program_title: str
    employee_id: str
    employee_code: str | None
    employee_name: str
    department_id: str | None
    department_name: str | None
    status: str
    nomination_source: str | None
    decided_at: datetime | None
    decision_remarks: str | None
    present_days: int
    session_days: int
    # Days present so far / session days; attendance_percent is what was recorded on completion.
    attendance_to_date: Number
    attendance_percent: Number | None
    score: Number | None
    result_remarks: str | None
    completed_at: datetime | None
    certificate: FileRef | None = None
    certificate_no: str | None
    certificate_issued_date: date | None
    certificate_expiry_date: date | None
    feedback_rating: int | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EnrolmentDetailOut(EnrolmentOut):
    attendance: list[AttendanceDayOut]
    feedback: FeedbackOut | None


class FeedbackListOut(ApiModel):
    id: str
    enrolment_id: str
    training_session_id: str
    session_title: str
    employee_id: str
    employee_name: str
    overall_rating: int
    trainer_rating: int | None
    content_rating: int | None
    comments: str | None
    created_at: datetime
    updated_at: datetime | None


# --- Attendance ----------------------------------------------------------------------------------


class MarkIn(ApiModel):
    enrolment_id: int
    status: Literal["present", "absent", "excused"]
    remarks: str | None = Field(default=None, max_length=1000)


class AttendanceIn(ApiModel):
    attendance_date: date
    marks: list[MarkIn] = Field(min_length=1, max_length=1000)


class ParticipantOut(ApiModel):
    enrolment_id: str
    employee_id: str
    employee_code: str | None
    employee_name: str
    status: str
    present_days: int
    session_days: int
    attendance_to_date: Number
    days: list[AttendanceDayOut]


class AttendanceOut(ApiModel):
    session_id: str
    title: str
    start_date: date
    end_date: date
    session_days: int
    status: str
    participants: list[ParticipantOut]
