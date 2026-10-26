"""Recruitment bodies: job openings, applicants, applications and their pipeline, hiring, interviews with
evaluations, offers, rejection reasons and the recruitment dashboard. Files (CV, offer letter) are ids of
uploads made through /api/files; responses carry a signed link (FileRef)."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Money = Decimal
WorkMode = Literal["on_site", "remote", "hybrid"]
Source = Literal["career_site", "referral", "job_board", "linkedin", "walk_in", "agency", "other"]
Stage = Literal["applied", "screening", "shortlisted", "interview", "offer", "hired", "rejected", "withdrawn"]


class RowVersionIn(ApiModel):
    row_version: str


class RemarksIn(ApiModel):
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


# ---------------------------------------------------------------- job openings


class OpeningIn(ApiModel):
    # Blank: the next JOB-0001 number is given.
    code: str | None = Field(None, max_length=30)
    # Blank with an open position: the position's title (or the job title's name).
    title: str | None = Field(None, max_length=200)
    open_position_id: int | None = None
    job_title_id: int | None = None
    designation_id: int | None = None
    department_id: int | None = None
    branch_id: int | None = None
    employment_type_id: int | None = None
    hiring_manager_id: int | None = None
    city_id: int | None = None
    work_mode: WorkMode | None = None
    experience_from_years: int | None = Field(None, ge=0, le=60)
    experience_to_years: int | None = Field(None, ge=0, le=60)
    # Blank with an open position: its seats still open.
    vacancies: int | None = Field(None, ge=1, le=10000)
    posted_on: date | None = None
    apply_by: date | None = None
    close_on: date | None = None
    salary_from: Money | None = Field(None, ge=0)
    salary_to: Money | None = Field(None, ge=0)
    is_salary_visible: bool = False
    description: str | None = None
    requirements: str | None = None
    row_version: str | None = None


class OpeningOut(ApiModel):
    id: str
    code: str
    title: str
    status: str
    open_position_id: str | None
    open_position_title: str | None
    open_position_seats: int | None
    job_title_id: str | None
    job_title_name: str | None
    designation_id: str | None
    designation_name: str | None
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
    employment_type_id: str | None
    employment_type_name: str | None
    hiring_manager_id: str | None
    hiring_manager_name: str | None
    city_id: str | None
    city_name: str | None
    state_id: str | None
    state_name: str | None
    work_mode: str | None
    experience_from_years: int | None
    experience_to_years: int | None
    vacancies: int
    hired_count: int
    remaining_vacancies: int
    application_count: int
    active_application_count: int
    posted_on: date | None
    apply_by: date | None
    close_on: date | None
    salary_from: float | None
    salary_to: float | None
    is_salary_visible: bool
    description: str | None
    requirements: str | None
    published_at: datetime | None
    closed_at: datetime | None
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- applicants


class ApplicantIn(ApiModel):
    first_name: str = Field(min_length=1, max_length=200)
    last_name: str = Field(min_length=1, max_length=200)
    email: str = Field(min_length=3, max_length=254)
    phone: str | None = Field(None, max_length=30)
    gender: Literal["male", "female", "other"] | None = None
    date_of_birth: date | None = None
    city_id: int | None = None
    address: str | None = Field(None, max_length=500)
    current_employer: str | None = Field(None, max_length=200)
    current_job_title: str | None = Field(None, max_length=200)
    experience_years: Decimal | None = Field(None, ge=0, le=99)
    current_salary: Money | None = Field(None, ge=0)
    expected_salary: Money | None = Field(None, ge=0)
    notice_period_days: int | None = Field(None, ge=0, le=365)
    highest_education: str | None = Field(None, max_length=200)
    linkedin_url: str | None = Field(None, max_length=500)
    source: Source | None = None
    referred_by_employee_id: int | None = None
    # An upload made first through POST /api/files.
    cv_file_id: int | None = None
    notes: str | None = None
    row_version: str | None = None


class ApplicantOut(ApiModel):
    id: str
    first_name: str
    last_name: str
    full_name: str
    email: str
    phone: str | None
    gender: str | None
    date_of_birth: date | None
    city_id: str | None
    city_name: str | None
    state_name: str | None
    country_name: str | None
    address: str | None
    current_employer: str | None
    current_job_title: str | None
    experience_years: float | None
    current_salary: float | None
    expected_salary: float | None
    notice_period_days: int | None
    highest_education: str | None
    linkedin_url: str | None
    source: str | None
    referred_by_employee_id: str | None
    referred_by_name: str | None
    cv_file_id: str | None
    cv: FileRef | None = None
    notes: str | None
    application_count: int
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- applications


class ApplicationIn(ApiModel):
    """Apply an existing applicant (applicantId) or add a new one in the same call (applicant)."""
    job_opening_id: int
    applicant_id: int | None = None
    applicant: ApplicantIn | None = None
    applied_on: date | None = None
    source: Source | None = None
    cover_letter: str | None = None
    remarks: str | None = Field(None, max_length=4000)


class ApplicationOut(ApiModel):
    __local_times__ = frozenset({'next_interview_at'})  # wall-clock, no zone
    id: str
    job_opening_id: str
    job_opening_code: str
    job_opening_title: str
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
    applicant_id: str
    applicant_name: str
    applicant_email: str
    applicant_phone: str | None
    applicant_current_job_title: str | None
    applicant_city_name: str | None
    cv_file_id: str | None
    cv: FileRef | None = None
    applied_on: date
    source: str | None
    cover_letter: str | None
    stage: str
    stage_changed_at: datetime | None
    rejection_reason_id: str | None
    rejection_reason_name: str | None
    rejected_stage: str | None
    remarks: str | None
    employee_id: str | None
    employee_code: str | None
    hired_at: datetime | None
    interview_count: int
    next_interview_at: datetime | None
    average_rating: float | None
    evaluation_count: int | None
    latest_offer_id: str | None
    latest_offer_status: str | None
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


class StageHistoryOut(ApiModel):
    id: str
    from_stage: str | None
    to_stage: str
    changed_at: datetime
    changed_by_user_id: str | None
    changed_by_name: str | None
    remarks: str | None


class StageIn(ApiModel):
    stage: Literal["applied", "screening", "shortlisted", "interview", "offer"]
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


class RejectIn(ApiModel):
    rejection_reason_id: int | None = None
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


class HireIn(ApiModel):
    """Blank fields take the accepted offer's (placement, joining date, salary) or the opening's; the line
    manager defaults to the opening's hiring manager."""
    row_version: str
    code: str | None = Field(None, max_length=30)
    joining_date: date | None = None
    branch_id: int | None = None
    department_id: int | None = None
    designation_id: int | None = None
    job_title_id: int | None = None
    employment_type_id: int | None = None
    line_manager_id: int | None = None
    salary: Money | None = Field(None, ge=0)
    status: Literal["active", "probation"] | None = None
    probation_end_date: date | None = None
    cnic: str | None = Field(None, max_length=15)
    remarks: str | None = Field(None, max_length=4000)


# ---------------------------------------------------------------- interviews


class InterviewIn(ApiModel):
    application_id: int | None = None
    title: str | None = Field(None, max_length=200)
    mode: Literal["in_person", "phone", "video"] = "in_person"
    # Local wall-clock time, like attendance times.
    scheduled_at: datetime
    duration_minutes: int = Field(60, ge=5, le=600)
    venue: str | None = Field(None, max_length=500)
    remarks: str | None = None
    interviewer_ids: list[int] = Field(min_length=1, max_length=20)
    row_version: str | None = None


class InterviewOut(ApiModel):
    __local_times__ = frozenset({'scheduled_at', 'ends_at'})  # wall-clock, no zone
    id: str
    application_id: str
    application_stage: str
    job_opening_id: str
    job_opening_title: str
    applicant_id: str
    applicant_name: str
    applicant_email: str
    applicant_phone: str | None
    applicant_city_name: str | None
    cv_file_id: str | None
    cv: FileRef | None = None
    round_no: int
    title: str
    mode: str | None
    scheduled_at: datetime
    duration_minutes: int
    ends_at: datetime
    venue: str | None
    status: str
    result: str | None
    remarks: str | None
    interviewer_names: str | None
    interviewer_count: int
    evaluation_count: int
    average_rating: float | None
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


class InterviewerOut(ApiModel):
    employee_id: str
    employee_code: str | None
    employee_name: str
    job_title_name: str | None
    email: str | None
    has_evaluated: bool


class EvaluationOut(ApiModel):
    id: str
    interview_id: str
    employee_id: str
    employee_name: str
    rating: int
    recommendation: str
    strengths: str | None
    concerns: str | None
    comments: str | None
    evaluated_at: datetime
    evaluated_by_user_id: str | None
    evaluated_by_name: str | None
    row_version: str


class InterviewDetailOut(InterviewOut):
    interviewers: list[InterviewerOut]
    evaluations: list[EvaluationOut]


class CompleteIn(ApiModel):
    status: Literal["completed", "no_show"] = "completed"
    result: Literal["passed", "failed", "on_hold"] | None = None
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


class EvaluationIn(ApiModel):
    # Blank: the caller, as an interviewer on the panel.
    employee_id: int | None = None
    rating: int = Field(ge=1, le=5)
    recommendation: Literal["strong_hire", "hire", "no_hire", "strong_no_hire"]
    strengths: str | None = None
    concerns: str | None = None
    comments: str | None = None


# ---------------------------------------------------------------- offers


class OfferIn(ApiModel):
    application_id: int | None = None
    job_title_id: int | None = None
    designation_id: int | None = None
    department_id: int | None = None
    branch_id: int | None = None
    employment_type_id: int | None = None
    offered_salary: Money = Field(gt=0)
    salary_frequency: Literal["monthly", "daily", "hourly"] = "monthly"
    joining_date: date
    probation_months: int | None = Field(None, ge=0, le=24)
    expires_on: date | None = None
    # An upload made first through POST /api/files.
    offer_letter_file_id: int | None = None
    remarks: str | None = None
    row_version: str | None = None


class OfferOut(ApiModel):
    id: str
    application_id: str
    application_stage: str
    job_opening_id: str
    job_opening_title: str
    applicant_id: str
    applicant_name: str
    applicant_email: str
    job_title_id: str | None
    job_title_name: str | None
    designation_id: str | None
    designation_name: str | None
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
    employment_type_id: str | None
    employment_type_name: str | None
    offered_salary: float
    salary_frequency: str | None
    joining_date: date
    probation_months: int | None
    expires_on: date | None
    offer_letter_file_id: str | None
    offer_letter: FileRef | None = None
    status: str
    sent_at: datetime | None
    responded_at: datetime | None
    response_remarks: str | None
    remarks: str | None
    created_at: datetime
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str


class RespondIn(ApiModel):
    decision: Literal["accepted", "declined"]
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


class ApplicationDetailOut(ApplicationOut):
    history: list[StageHistoryOut]
    interviews: list[InterviewOut]
    offers: list[OfferOut]


class ApplicantDetailOut(ApplicantOut):
    applications: list[ApplicationOut]


# ---------------------------------------------------------------- settings: rejection reasons


class RejectionReasonIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    is_active: bool = True
    sort_order: int | None = None
    row_version: str | None = None


class RejectionReasonOut(ApiModel):
    id: str
    name: str
    is_active: bool
    sort_order: int
    usage_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- dashboard


class DashboardTilesOut(ApiModel):
    open_openings: int
    total_openings: int
    open_vacancies: int
    applications: int
    interviews: int
    upcoming_interviews: int
    offers_accepted: int
    hired: int
    rejected: int


class DashboardMonthOut(ApiModel):
    month_no: int
    applications: int
    shortlisted: int
    rejected: int
    hired: int


class DashboardInterviewOut(ApiModel):
    __local_times__ = frozenset({'scheduled_at'})  # wall-clock, no zone
    interview_id: str
    application_id: str
    applicant_id: str
    applicant_name: str
    applicant_email: str
    applicant_phone: str | None
    applicant_city_name: str | None
    job_opening_id: str
    job_opening_title: str
    title: str
    round_no: int
    mode: str | None
    scheduled_at: datetime
    duration_minutes: int
    venue: str | None
    interviewer_names: str | None
    first_interviewer_name: str | None
    first_interviewer_title: str | None


class DashboardActivityOut(ApiModel):
    id: str
    application_id: str
    applicant_name: str
    job_opening_title: str
    from_stage: str | None
    to_stage: str
    changed_at: datetime
    changed_by_name: str | None


class DashboardOut(ApiModel):
    year: int
    month: int | None
    tiles: DashboardTilesOut
    job_statistics: list[DashboardMonthOut]
    upcoming_interviews: list[DashboardInterviewOut]
    recent_activity: list[DashboardActivityOut]
