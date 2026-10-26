from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import Field, PlainSerializer

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

# Exact in Python (DECIMAL in the database), sent as JSON numbers.
Number = Annotated[Decimal, PlainSerializer(float, return_type=float, when_used="json")]
GoalStatus = Literal["not_started", "in_progress", "completed", "cancelled"]
Outcome = Literal["no_change", "increment", "promotion", "improvement_plan"]

# --- Settings: rating scales ---------------------------------------------------------------------


class ScaleLevel(ApiModel):
    score: Number = Field(ge=0, le=100)
    label: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=2000)


class RatingScaleIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    is_default: bool = False
    is_active: bool = True
    levels: list[ScaleLevel] = Field(min_length=2, max_length=20)
    row_version: str | None = None


class RatingScaleOut(ApiModel):
    id: str
    name: str
    is_default: bool
    is_active: bool
    min_score: Number | None
    max_score: Number | None
    levels: list[ScaleLevel]
    # Appraisal forms using the scale; a scale in use cannot be deleted.
    in_use: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Settings: appraisal forms -------------------------------------------------------------------


class CriterionIn(ApiModel):
    kpi_id: int | None = None
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    weight: Number = Field(gt=0, le=100)


class CriterionOut(ApiModel):
    id: str
    kpi_id: str | None = None
    kpi_name: str | None = None
    name: str
    description: str | None = None
    weight: Number
    sort_order: int | None = None


class AppraisalFormIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    rating_scale_id: int
    # Share of the score that comes from goal achievement; the criteria weights make up the rest of 100.
    goals_weight: Number = Field(default=Decimal(0), ge=0, le=100)
    has_self_review: bool = True
    is_active: bool = True
    criteria: list[CriterionIn] = Field(default_factory=list, max_length=50)
    row_version: str | None = None


class AppraisalFormOut(ApiModel):
    id: str
    name: str
    description: str | None
    rating_scale_id: str
    rating_scale_name: str
    goals_weight: Number
    has_self_review: bool
    is_active: bool
    criteria: list[CriterionOut]
    # Cycles using the form (it cannot be deleted); locked = a launched cycle uses it (weights are fixed).
    in_use: int
    is_locked: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- KPIs ----------------------------------------------------------------------------------------


class KpiIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    key_result_area: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    measure_type: Literal["percentage", "number", "amount", "rating", "yes_no"] = "percentage"
    target_value: Number | None = None
    unit: str | None = Field(default=None, max_length=30)
    default_weight: Number | None = Field(default=None, ge=0, le=100)
    department_id: int | None = None
    job_title_id: int | None = None
    is_active: bool = True
    row_version: str | None = None


class KpiOut(ApiModel):
    id: str
    name: str
    key_result_area: str | None
    description: str | None
    measure_type: str | None
    target_value: Number | None
    unit: str | None
    default_weight: Number | None
    department_id: str | None
    department_name: str | None
    job_title_id: str | None
    job_title_name: str | None
    is_active: bool
    in_use: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --- Goals ---------------------------------------------------------------------------------------


class GoalIn(ApiModel):
    # Empty = the signed-in employee's own goal.
    employee_id: int | None = None
    appraisal_cycle_id: int | None = None
    kpi_id: int | None = None
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    start_date: date | None = None
    due_date: date
    weight: Number = Field(default=Decimal(1), ge=0, le=100)
    target_value: Number | None = None
    actual_value: Number | None = None
    # 0-100. Worked out from actual / target when a target is set; 100 completes the goal.
    progress: Number | None = Field(default=None, ge=0, le=100)
    status: GoalStatus | None = None
    comments: str | None = Field(default=None, max_length=4000)
    row_version: str | None = None


class CheckInIn(ApiModel):
    progress: Number | None = Field(default=None, ge=0, le=100)
    actual_value: Number | None = None
    status: GoalStatus | None = None
    comments: str | None = Field(default=None, max_length=4000)
    row_version: str


class GoalOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None
    employee_name: str
    department_id: str | None
    department_name: str | None
    appraisal_cycle_id: str | None
    appraisal_cycle_name: str | None
    kpi_id: str | None
    kpi_name: str | None
    title: str
    description: str | None
    start_date: date | None
    due_date: date
    weight: Number
    target_value: Number | None
    actual_value: Number | None
    progress: Number
    status: str
    is_overdue: bool
    # Counted in a finalised appraisal: no more changes.
    is_locked: bool
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class CheckInOut(ApiModel):
    id: str
    progress: Number
    actual_value: Number | None
    status: str
    comments: str | None
    created_at: datetime
    created_by_name: str | None


class GoalDetailOut(GoalOut):
    check_ins: list[CheckInOut]


# --- Appraisal cycles ----------------------------------------------------------------------------


class CycleIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    appraisal_form_id: int
    start_date: date
    end_date: date
    self_review_due_date: date | None = None
    manager_review_due_date: date | None = None
    row_version: str | None = None


class CycleOut(ApiModel):
    id: str
    name: str
    appraisal_form_id: str
    appraisal_form_name: str
    start_date: date
    end_date: date
    self_review_due_date: date | None
    manager_review_due_date: date | None
    status: str
    launched_at: datetime | None
    closed_at: datetime | None
    participants: int
    self_review: int
    manager_review: int
    reviewed: int
    finalised: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class ParticipantsIn(ApiModel):
    employee_ids: list[int] = Field(default_factory=list, max_length=1000)
    # Everyone working in this department (and reachable by the caller).
    department_id: int | None = None


class ParticipantsOut(ApiModel):
    cycle: CycleOut
    added: int


class RowVersionIn(ApiModel):
    row_version: str


# --- Appraisals and reviews ----------------------------------------------------------------------


class AppraisalOut(ApiModel):
    id: str
    appraisal_cycle_id: str
    appraisal_cycle_name: str
    cycle_status: str
    period_start: date
    period_end: date
    self_review_due_date: date | None
    manager_review_due_date: date | None
    appraisal_form_id: str
    appraisal_form_name: str
    has_self_review: bool
    goals_weight: Number
    rating_scale_id: str
    employee_id: str
    employee_code: str | None
    employee_name: str
    department_id: str | None
    department_name: str | None
    job_title_name: str | None
    reviewer_employee_id: str | None
    reviewer_name: str | None
    status: str
    goals_score: Number | None
    self_score: Number | None
    manager_score: Number | None
    final_score: Number | None
    final_rating_label: str | None
    outcome: str | None
    self_submitted_at: datetime | None
    manager_submitted_at: datetime | None
    finalised_at: datetime | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class RatingRowOut(ApiModel):
    criterion_id: str
    kpi_id: str | None
    kpi_name: str | None
    name: str
    description: str | None
    weight: Number
    sort_order: int | None
    self_rating: Number | None
    self_comment: str | None
    manager_rating: Number | None
    manager_comment: str | None


class AppraisalGoalOut(ApiModel):
    id: str
    title: str
    due_date: date
    weight: Number
    progress: Number
    status: str


class ProposalBriefOut(ApiModel):
    id: str
    change_type: str
    change_value: Number
    effective_date: date
    status: str


class AppraisalDetailOut(AppraisalOut):
    self_comments: str | None
    manager_comments: str | None
    final_comments: str | None
    development_needs: str | None
    letter_file: FileRef | None
    ratings: list[RatingRowOut]
    goals: list[AppraisalGoalOut]
    scale: list[ScaleLevel]
    increment: ProposalBriefOut | None


class RatingIn(ApiModel):
    criterion_id: int
    rating: Number | None = Field(default=None, ge=0, le=100)
    comment: str | None = Field(default=None, max_length=4000)


class ReviewIn(ApiModel):
    ratings: list[RatingIn] = Field(default_factory=list, max_length=50)
    comments: str | None = Field(default=None, max_length=8000)
    # Manager review only: training and development the manager recommends.
    development_needs: str | None = Field(default=None, max_length=8000)
    # False saves a draft; true hands the appraisal to the next stage.
    submit: bool = False
    row_version: str


class IncrementIn(ApiModel):
    change_type: Literal["flat", "percent"]
    change_value: Number = Field(gt=0)
    effective_date: date


class FinaliseIn(ApiModel):
    # Empty = the manager's score.
    final_score: Number | None = Field(default=None, ge=0, le=100)
    final_comments: str | None = Field(default=None, max_length=8000)
    outcome: Outcome = "no_change"
    increment: IncrementIn | None = None
    letter_file_id: int | None = None
    row_version: str


# --- Increments ----------------------------------------------------------------------------------


class IncrementOut(ApiModel):
    id: str
    appraisal_id: str
    appraisal_cycle_id: str
    appraisal_cycle_name: str
    employee_id: str
    employee_code: str | None
    employee_name: str
    department_name: str | None
    final_score: Number | None
    final_rating_label: str | None
    change_type: str
    change_value: Number
    effective_date: date
    current_salary: Number | None
    proposed_salary: Number | None
    status: str
    employee_salary_id: str | None
    decided_at: datetime | None
    remarks: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class DecisionIn(ApiModel):
    remarks: str | None = Field(default=None, max_length=4000)
    row_version: str


# --- My Performance overview ---------------------------------------------------------------------


class GoalCountsOut(ApiModel):
    total: int
    not_started: int
    in_progress: int
    completed: int
    cancelled: int
    overdue: int
    # Weighted by goal weight, cancelled goals left out.
    weighted_progress: Number | None


class UpcomingGoalOut(ApiModel):
    id: str
    title: str
    due_date: date
    progress: Number
    status: str
    is_overdue: bool


class AppraisalSummaryOut(ApiModel):
    id: str
    appraisal_cycle_id: str
    appraisal_cycle_name: str
    period_start: date
    period_end: date
    status: str
    self_review_due_date: date | None
    manager_review_due_date: date | None
    final_score: Number | None
    final_rating_label: str | None
    outcome: str | None
    finalised_at: datetime | None


class OverviewOut(ApiModel):
    employee_id: str
    employee_code: str | None
    employee_name: str
    department_name: str | None
    job_title_name: str | None
    goals: GoalCountsOut
    upcoming_goals: list[UpcomingGoalOut]
    appraisals: list[AppraisalSummaryOut]
