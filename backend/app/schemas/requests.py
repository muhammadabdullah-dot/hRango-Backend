"""Request and response bodies of the Requests module: the request engine (every request type),
approvals and Request Settings. Each request type has its own `details` body; the header fields
are shared. Ids are strings in JSON; inputs accept strings or numbers."""
from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, Generic, Literal, TypeVar

from pydantic import Field

from app.schemas.common import ApiModel, PageMeta

# ---------------------------------------------------------------- per-type details (input)

PunchType = Literal["check_in", "check_out", "break_out", "break_in"]
ShortLeaveType = Literal["half_day", "quarter_day"]
ResignationType = Literal["resignation", "voluntary", "retirement", "contract_end"]
TravelType = Literal["domestic", "international"]
TravelMode = Literal["bus", "train", "taxi", "air", "own_car", "pool_car"]
StayType = Literal["hotel", "self"]
PaymentMethod = Literal["bank", "cash", "pay_order", "cheque"]
RequisitionType = Literal["stationery", "it_equipment", "furniture", "asset", "consumable", "service", "other"]
OvertimeType = Literal["mandatory", "voluntary"]


class LeaveDetails(ApiModel):
    leave_type_id: int
    is_short: bool = False
    short_leave_type: ShortLeaveType | None = None
    start_time: time | None = None
    end_time: time | None = None


class PunchDetails(ApiModel):
    punch_date: date | None = None
    punch_type: PunchType
    punch_time: time


class TimeWindowDetails(ApiModel):
    """Relaxation and Official Visit: one date with a time range."""
    window_date: date | None = None
    start_time: time
    end_time: time


class WorkFromHomeDetails(ApiModel):
    # The days ticked on the week strip; empty means every shift day between fromDate and toDate.
    dates: list[date] | None = None


class OvertimeDetails(ApiModel):
    department_id: int
    location_id: int | None = None
    branch_id: int | None = None
    overtime_date: date | None = None
    start_time: time
    end_time: time
    applied_minutes: int | None = Field(None, gt=0)
    # The bulk form's Type; kept when an edit leaves it out.
    overtime_type: OvertimeType | None = None


class RestDayDetails(ApiModel):
    department_id: int
    roster_group_id: int
    is_payable: bool = False


class ShiftSwapDetails(ApiModel):
    """Either a new shift for the day (timeSlotId) or a swap with a colleague (withEmployeeId)."""
    shift_date: date | None = None
    time_slot_id: int | None = None
    with_employee_id: int | None = None


class PromotionDetails(ApiModel):
    is_demotion: bool = False
    grade_id: int
    job_level_id: int | None = None
    designation_id: int
    job_title_id: int
    new_salary: Decimal = Field(gt=0)
    effective_date: date | None = None
    benefit_pay_item_ids: list[int] = []


class TransferDetails(ApiModel):
    location_id: int
    branch_id: int
    department_id: int
    line_manager_id: int
    final_authority_id: int
    effective_date: date | None = None


class ResignationDetails(ApiModel):
    resignation_type: ResignationType = "resignation"
    resignation_date: date | None = None
    last_working_date: date | None = None
    notice_period_days: int | None = Field(None, ge=0)
    serve_notice: bool = False


class GuarantorIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    cnic: str = Field(min_length=5, max_length=15, pattern=r"^[0-9-]+$")
    known_since: date
    relationship: str = Field(min_length=1, max_length=200)
    extension_no: str | None = Field(None, max_length=20)
    description: str | None = None
    # An uploaded file (POST /api/files): the guarantor's CNIC copy or similar.
    file_id: int | None = None


class LoanDetails(ApiModel):
    loan_type_id: int
    loan_category_id: int | None = None
    amount_requested: Decimal = Field(gt=0)
    required_date: date | None = None
    extension_no: str | None = Field(None, max_length=20)
    guarantors: list[GuarantorIn] = []


class TravelAdvanceIn(ApiModel):
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)


class TravelLegIn(ApiModel):
    travel_type: TravelType
    from_place: str = Field(min_length=1, max_length=200)
    to_place: str = Field(min_length=1, max_length=200)
    travel_mode: TravelMode
    distance_km: Decimal | None = Field(None, ge=0)
    depart_at: datetime
    arrive_at: datetime
    stay_required: bool = False


class TravelStayIn(ApiModel):
    stay_type: StayType
    address: str = Field(min_length=1, max_length=500)
    city: str = Field(min_length=1, max_length=200)
    from_date: date
    to_date: date
    nights: int | None = Field(None, ge=0)
    phone: str = Field(min_length=1, max_length=30)
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+$")


class TravelTicketIn(ApiModel):
    ticket_no: str = Field(min_length=1, max_length=50)
    travel_class: str | None = Field(None, max_length=30)
    from_place: str | None = Field(None, max_length=200)
    to_place: str | None = Field(None, max_length=200)
    travel_at: datetime
    description: str | None = None
    file_id: int | None = None


class TravelDetails(ApiModel):
    purpose: str = Field(min_length=1, max_length=500)
    extension_no: str | None = Field(None, max_length=20)
    alt_phone: str | None = Field(None, max_length=30)
    advance_required: bool = False
    advances: list[TravelAdvanceIn] = []
    legs: list[TravelLegIn] = Field(min_length=1)
    stays: list[TravelStayIn] = []
    tickets: list[TravelTicketIn] = []


class ExpenseLineIn(ApiModel):
    """One claim (Figma "Claim Expense"): several are prepared with "Generate Claim" and sent together."""
    title: str = Field(min_length=1, max_length=200)
    claim_date: date | None = None  # today when empty
    expense_category_id: int
    amount: Decimal = Field(gt=0, max_digits=16, decimal_places=2)
    description: str = Field(min_length=1, max_length=4000)
    file_id: int | None = None  # the receipt, uploaded first


class ExpenseDetails(ApiModel):
    lines: list[ExpenseLineIn] = Field(min_length=1, max_length=50)


class AirTicketDetails(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    claim_date: date | None = None
    travel_date: date
    from_place: str | None = Field(None, max_length=200)
    to_place: str | None = Field(None, max_length=200)
    amount: Decimal = Field(gt=0, max_digits=16, decimal_places=2)
    description: str | None = Field(None, max_length=4000)
    file_id: int | None = None  # the ticket


class RequisitionLineIn(ApiModel):
    item_name: str = Field(min_length=1, max_length=200)
    quantity: Decimal = Field(gt=0, max_digits=16, decimal_places=2)
    unit: str | None = Field(None, max_length=50)
    estimated_unit_cost: Decimal | None = Field(None, ge=0, max_digits=16, decimal_places=2)
    description: str | None = Field(None, max_length=4000)


class RequisitionDetails(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    requisition_type: RequisitionType
    needed_by_date: date
    delivery_location: str | None = Field(None, max_length=200)
    lines: list[RequisitionLineIn] = Field(min_length=1, max_length=100)


# Request types with screens: code -> details body. The code is the URL segment (with hyphens).
TYPE_DETAILS: dict[str, type[ApiModel]] = {
    "leave": LeaveDetails, "punch": PunchDetails, "relaxation": TimeWindowDetails,
    "official_visit": TimeWindowDetails, "work_from_home": WorkFromHomeDetails, "overtime": OvertimeDetails,
    "rest_day": RestDayDetails, "shift_swap": ShiftSwapDetails, "promotion": PromotionDetails,
    "transfer": TransferDetails, "resignation": ResignationDetails, "loan": LoanDetails, "travel": TravelDetails,
    "expense": ExpenseDetails, "air_ticket": AirTicketDetails, "requisition": RequisitionDetails,
}

D = TypeVar("D", bound=ApiModel)


class RequestIn(ApiModel, Generic[D]):
    # Empty for the caller's own request (My); an employee for "All Requests".
    employee_id: int | None = None
    from_date: date | None = None
    to_date: date | None = None
    reason: str | None = Field(None, max_length=4000)
    description: str | None = Field(None, max_length=4000)
    # The application text (written by hand or generated); kept as sent.
    application: str | None = None
    # Uploaded files (POST /api/files) by id.
    attachments: list[int] = Field([], max_length=20)
    details: D
    # Required when editing.
    row_version: str | None = None


# ---------------------------------------------------------------- decisions

class ApprovedLineIn(ApiModel):
    id: int
    approved_amount: Decimal = Field(ge=0, max_digits=16, decimal_places=2)


class ApprovalDetailsIn(ApiModel):
    """What the approver enters: loans, overtime, resignation, air tickets (approvedAmount) and
    expense claims (lines: the approved amount of each claim, 0 = not reimbursed). Other types send nothing."""
    approved_amount: Decimal | None = Field(None, gt=0)
    lines: list[ApprovedLineIn] | None = None
    payment_method: PaymentMethod | None = None
    repayment_date: date | None = None
    currency: str | None = Field(None, min_length=3, max_length=3)
    approved_minutes: int | None = Field(None, ge=0)
    last_working_date: date | None = None
    serve_notice: bool | None = None
    notice_period_days: int | None = Field(None, ge=0)


class DecisionIn(ApiModel):
    remarks: str | None = Field(None, max_length=4000)
    details: ApprovalDetailsIn | None = None
    row_version: str


class ConsentIn(ApiModel):
    agree: bool
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


class ForwardIn(ApiModel):
    employee_id: int
    remarks: str | None = Field(None, max_length=4000)
    row_version: str


class CancelIn(ApiModel):
    reason: str = Field(min_length=1, max_length=4000)
    row_version: str
    # Work from home only (the approver's "WFH Cancel": dates and a time range); 422 for other types.
    # Stored with the cancellation and returned as cancelDates / cancelStartTime / cancelEndTime; they
    # change nothing yet (open product question R2: the whole request is cancelled as before).
    dates: list[date] | None = Field(None, max_length=366)
    start_time: time | None = None
    end_time: time | None = None


class BulkItemIn(ApiModel):
    id: int
    row_version: str
    # What the single approve takes (e.g. overtime approvedMinutes); bulk-reject ignores it. Left out, bulk
    # approve prefills what the form would (a loan's amount ...).
    details: ApprovalDetailsIn | None = None


class BulkDecisionIn(ApiModel):
    items: list[BulkItemIn] = Field(min_length=1, max_length=100)
    remarks: str | None = Field(None, max_length=4000)


class BulkResultOut(ApiModel):
    id: str
    ok: bool
    status: str | None = None
    code: str | None = None
    message: str | None = None


class AttachmentIn(ApiModel):
    file_id: int  # uploaded first: POST /api/files
    label: str | None = Field(None, max_length=200)


# ---------------------------------------------------------------- responses

class RequestTypeOut(ApiModel):
    id: str
    code: str
    name: str
    kind: str
    is_admin_only: bool
    is_active: bool
    sort_order: int | None


class StepOut(ApiModel):
    id: str
    purpose: str
    step_no: int | None
    approver_kind: str | None
    approver_id: str | None
    approver_name: str | None
    acted_by_id: str | None
    acted_by_name: str | None
    is_delegate: bool
    is_consent: bool
    action_taken: str
    remarks: str | None
    acted_at: datetime | None
    created_at: datetime


class AttachmentOut(ApiModel):
    id: str
    file_id: str
    name: str
    mime_type: str | None = None
    size_bytes: int | None = None
    label: str | None = None
    # A signed download link that expires (FILE_LINK_MINUTES).
    url: str
    created_at: datetime


class RequestOut(ApiModel):
    id: str
    code: str
    request_type: str
    request_type_name: str
    kind: str
    employee_id: str
    employee_code: str
    employee_name: str | None
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
    location_id: str | None
    location_name: str | None
    job_title_name: str | None
    joining_date: date | None
    from_date: date | None
    to_date: date | None
    days: float | None
    reason: str | None
    description: str | None
    application: str | None
    status: str
    submitted_at: datetime | None
    decided_at: datetime | None
    cancel_reason: str | None
    # A work from home cancellation's dates and time range, as given (R2).
    cancel_dates: list[date] | None = None
    cancel_start_time: time | None = None
    cancel_end_time: time | None = None
    next_approver_id: str | None
    next_approver_name: str | None
    next_approver_kind: str | None
    final_authority_id: str | None
    final_authority_name: str | None
    details: dict[str, Any]
    created_at: datetime
    updated_at: datetime | None
    row_version: str
    # Approvals lists only.
    is_waiting: bool | None = None
    delegator_id: str | None = None
    delegator_name: str | None = None


class RequestDetailOut(RequestOut):
    steps: list[StepOut]
    attachments: list[AttachmentOut]
    # What the caller may do now (the row menu): view, edit, delete, cancel, approve, reject,
    # consent, disagree, forward. The server checks again when they do it.
    actions: list[str]


class RequestPage(ApiModel):
    data: list[RequestOut]
    meta: PageMeta
    # Counts for the status tabs: pending, approved, rejected, cancelling, cancelled.
    counts: dict[str, int]


# ---------------------------------------------------------------- overtime: typed details, bulk filing

class OvertimeDetailsOut(ApiModel):
    """`details` of an overtime request."""
    department_id: str | None = None
    department_name: str | None = None
    location_id: str | None = None
    location_name: str | None = None
    branch_id: str | None = None
    branch_name: str | None = None
    overtime_date: date | None = None
    start_time: time | None = None
    end_time: time | None = None
    applied_minutes: int | None = None
    approved_minutes: int | None = None
    overtime_type: str | None = None
    # Filed with others through POST /requests/overtime/bulk.
    is_bulk: bool = False
    bulk_id: str | None = None
    # Set on final approval: the overtime policy and slab the approved minutes fell under (empty when none).
    overtime_policy_id: str | None = None
    overtime_policy_name: str | None = None
    slab_min_minutes: int | None = None
    slab_max_minutes: int | None = None
    encashment_type: str | None = None
    encashment_leave_type_id: str | None = None
    encashment_leave_type_name: str | None = None


class OvertimeRequestOut(RequestOut):
    details: OvertimeDetailsOut


class OvertimeRequestDetailOut(RequestDetailOut):
    details: OvertimeDetailsOut


class OvertimeRequestPage(RequestPage):
    data: list[OvertimeRequestOut]


class OvertimeBulkIn(ApiModel):
    """Create Bulk Overtime Request: one overtime request per person, filed on their behalf in one
    all-or-nothing call. The date is fromDate (toDate, when given, must be the same day); details are the
    Apply form's (departmentId ... appliedMinutes)."""
    employee_ids: list[int] = Field(min_length=1, max_length=100)
    overtime_type: OvertimeType
    from_date: date
    to_date: date | None = None
    reason: str = Field(min_length=1, max_length=4000)
    description: str | None = Field(None, max_length=4000)
    application: str | None = None
    attachments: list[int] = Field([], max_length=20)
    details: OvertimeDetails


class OvertimeBulkOut(ApiModel):
    bulk_id: str
    overtime_type: str
    count: int
    requests: list[OvertimeRequestOut]


# ---------------------------------------------------------------- writing the application with AI (R1)

class GenerateApplicationIn(ApiModel):
    """The form as filled so far (every field optional)."""
    employee_id: int | None = None
    from_date: date | None = None
    to_date: date | None = None
    reason: str | None = Field(None, max_length=4000)
    description: str | None = Field(None, max_length=4000)
    details: dict[str, Any] | None = None
    tone: Literal["formal", "neutral"] = "formal"
    language: str = Field("en", min_length=2, max_length=10)


class GeneratedApplicationOut(ApiModel):
    # HTML with <p>, <ul>, <strong> only.
    text: str
    generated_at: datetime


# ---------------------------------------------------------------- settings

class RestrictionIn(ApiModel):
    request_type: str = Field(min_length=1, max_length=30)
    start_date: date
    end_date: date
    description: str | None = Field(None, max_length=4000)
    row_version: str | None = None      # required on edit (PUT)


class RestrictionOut(ApiModel):
    id: str
    company_name: str
    request_type: str
    request_type_name: str
    start_date: date
    end_date: date
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class DelegationIn(ApiModel):
    delegator_id: int
    delegatee_id: int
    request_type: str = Field(min_length=1, max_length=30)
    description: str | None = Field(None, max_length=4000)
    is_active: bool = True


class DelegationPatch(ApiModel):
    """Disable / Enable, and the description."""
    is_active: bool
    description: str | None = Field(None, max_length=4000)
    row_version: str


class DelegationOut(ApiModel):
    id: str
    delegator_id: str
    delegator_name: str | None
    delegatee_id: str
    delegatee_name: str | None
    request_type: str
    request_type_name: str
    description: str | None
    is_active: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# Who can hold a node. Structural ones come from the organisation; the others are held through
# Request Settings -> Authorities.
STRUCTURAL_APPROVERS = ("employee", "line_manager", "hod", "branch_manager", "final_authority", "role")
AUTHORITIES = ("team_lead", "hr_manager", "operations_manager", "finance_manager", "director", "compliance_officer",
               "project_manager", "admin_supervisor", "it_administrator", "area_manager", "admin_manager")
Authority = Literal["team_lead", "hr_manager", "operations_manager", "finance_manager", "director",
                    "compliance_officer", "project_manager", "admin_supervisor", "it_administrator", "area_manager",
                    "admin_manager"]


class FlowNodeIn(ApiModel):
    step_no: int = Field(ge=1, le=999)
    # employee, line_manager, hod, branch_manager, final_authority, role, or an authority code.
    approver_kind: str | None = None
    employee_id: int | None = None
    role_id: int | None = None
    is_condition: bool = False
    # A condition node: "<field> <op> <number>", e.g. "days > 3", "amount >= 100000", "department_id = 12".
    expression: str | None = Field(None, max_length=200)
    next: int | None = None
    if_true: int | None = None
    if_false: int | None = None
    can_edit: bool = False
    can_disagree: bool = False
    is_observer: bool = False


class FlowIn(ApiModel):
    request_type: str = Field(min_length=1, max_length=30)
    purpose: Literal["request", "cancellation"] = "request"
    name: str = Field(min_length=1, max_length=200)
    scope_type: Literal["company", "branch", "department", "employee"] = "company"
    scope_id: int | None = None
    description: str | None = Field(None, max_length=4000)
    is_active: bool = True
    nodes: list[FlowNodeIn] = Field(min_length=1, max_length=100)
    row_version: str | None = None


class FlowNodeOut(ApiModel):
    id: str
    step_no: int
    approver_kind: str | None
    employee_id: str | None
    employee_name: str | None
    role_id: str | None
    role_name: str | None
    is_condition: bool
    expression: str | None
    next: int | None
    if_true: int | None
    if_false: int | None
    can_edit: bool
    can_disagree: bool
    is_observer: bool


class FlowOut(ApiModel):
    id: str
    request_type: str
    request_type_name: str
    purpose: str
    name: str
    scope_type: str
    scope_id: str | None
    scope_name: str | None
    description: str | None
    is_active: bool
    node_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class FlowDetailOut(FlowOut):
    nodes: list[FlowNodeOut]


class AuthorityIn(ApiModel):
    authority: Authority
    employee_id: int
    # Empty: every request type / branch / department.
    request_type: str | None = Field(None, max_length=30)
    branch_id: int | None = None
    department_id: int | None = None
    description: str | None = Field(None, max_length=4000)
    is_active: bool = True
    row_version: str | None = None


class AuthorityOut(ApiModel):
    id: str
    authority: str
    employee_id: str
    employee_name: str | None
    employee_code: str
    designation_name: str | None
    employee_branch_name: str | None
    request_type: str | None
    request_type_name: str | None
    branch_id: str | None
    branch_name: str | None
    department_id: str | None
    department_name: str | None
    description: str | None
    is_active: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- settings: expense categories, reimbursement

class ExpenseCategoryIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    # A reimbursement pay item; empty: the default expense pay item of Request Settings -> Reimbursement.
    pay_item_id: int | None = None
    max_amount: Decimal | None = Field(None, gt=0, max_digits=16, decimal_places=2)
    receipt_required: bool = False
    is_active: bool = True
    description: str | None = Field(None, max_length=4000)
    row_version: str | None = None


class ExpenseCategoryOut(ApiModel):
    id: str
    name: str
    pay_item_id: str | None
    pay_item_name: str | None
    max_amount: Decimal | None
    receipt_required: bool
    is_active: bool
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class ReimbursementSettingIn(ApiModel):
    expense_pay_item_id: int | None = None
    air_ticket_pay_item_id: int | None = None


class ReimbursementSettingOut(ApiModel):
    expense_pay_item_id: str | None
    expense_pay_item_name: str | None
    air_ticket_pay_item_id: str | None
    air_ticket_pay_item_name: str | None
    updated_at: datetime | None


# ---------------------------------------------------------------- self-service options of the request forms

class LeaveTypeOptionOut(ApiModel):
    """A leave type the employee may apply for, with what the Apply Leave form needs."""
    id: str
    name: str
    code: str | None
    is_deductible: bool
    is_short_leave: bool
    allow_half_day: bool
    allow_short_leave: bool
    attachment_required: bool
    attachment_rule: str
    allow_back_date: bool
    back_date_limit_days: int | None
    future_limit_days: int | None
    entitled: float
    used: float
    pending: float
    available: float


class LoanTypeOptionOut(ApiModel):
    id: str
    name: str
    guarantor_required: bool
    non_payable: bool
    min_experience_months: int
    gap_between_requests_months: int | None
    installments: int
    gap_between_installments_months: int | None
    description: str | None
    eligible: bool | None


class LoanCategoryOptionOut(ApiModel):
    id: str
    name: str
    description: str | None


class ColleagueOptionOut(ApiModel):
    id: str
    code: str | None
    name: str | None
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
