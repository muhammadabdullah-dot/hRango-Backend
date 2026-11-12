from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel

EMAIL = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"
StaffRole = Literal["super_admin", "admin", "support", "billing", "sales"]


class StaffLoginIn(ApiModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=200)


class StaffMe(ApiModel):
    id: str
    email: str
    display_name: str
    role: StaffRole


class StaffSession(ApiModel):
    token: str
    staff: StaffMe


class StaffIn(ApiModel):
    email: str = Field(min_length=3, max_length=254, pattern=EMAIL)
    display_name: str = Field(min_length=1, max_length=200)
    role: StaffRole
    is_active: bool = True
    # New staff only; afterwards PUT /platform/staff/{id}/password.
    password: str | None = Field(None, min_length=12, max_length=200)
    row_version: str | None = None


class StaffPasswordIn(ApiModel):
    password: str = Field(min_length=12, max_length=200)


class StaffOut(ApiModel):
    id: str
    email: str
    display_name: str
    role: StaffRole
    is_active: bool
    last_login_at: datetime | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class StaffAuditOut(ApiModel):
    id: str
    action_name: str
    entity_type: str | None
    entity_ref: str | None
    detail: str | None
    ip_address: str | None
    staff_id: str | None
    staff_name: str | None
    created_at: datetime


class StaffLookup(ApiModel):
    id: str
    display_name: str
    role: StaffRole


class CustomerIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    contact_name: str | None = Field(None, max_length=200)
    contact_email: str = Field(min_length=3, max_length=254, pattern=EMAIL)
    contact_phone: str | None = Field(None, max_length=50)
    country: str | None = Field(None, max_length=100)
    notes: str | None = Field(None, max_length=1000)
    row_version: str | None = None


class CustomerRegisterIn(CustomerIn):
    """Creates the company with its default roles and its Account Owner, who signs in with this password."""
    owner_name: str = Field(min_length=1, max_length=200)
    owner_email: str = Field(min_length=3, max_length=254, pattern=EMAIL)
    owner_password: str = Field(min_length=8, max_length=200)
    plan_id: int | None = None
    lead_id: int | None = None


class CustomerStatusIn(ApiModel):
    status: Literal["active", "suspended", "cancelled"]
    row_version: str


class CustomerOut(ApiModel):
    id: str
    name: str
    contact_name: str | None
    contact_email: str
    contact_phone: str | None
    country: str | None
    status: str
    notes: str | None
    company_count: int
    employee_count: int
    plan_name: str | None
    subscription_status: str | None
    renews_on: date | None
    created_at: datetime
    row_version: str


class CustomerCompanyOut(ApiModel):
    id: str
    name: str
    is_active: bool
    employee_count: int


class PlanIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(None, max_length=500)
    price_monthly: Decimal = Field(ge=0)
    price_annual: Decimal = Field(ge=0)
    employee_limit: int | None = Field(None, ge=1)
    is_active: bool = True
    row_version: str | None = None


class PlanOut(ApiModel):
    id: str
    name: str
    description: str | None
    price_monthly: float
    price_annual: float
    employee_limit: int | None
    is_active: bool
    subscription_count: int
    row_version: str


class SubscriptionIn(ApiModel):
    customer_id: int
    plan_id: int
    billing_cycle: Literal["monthly", "annual"]
    status: Literal["trial", "active", "past_due", "cancelled"]
    amount: Decimal | None = Field(None, ge=0)
    start_date: date
    renews_on: date | None = None
    row_version: str | None = None


class SubscriptionOut(ApiModel):
    id: str
    customer_id: str
    customer_name: str
    plan_id: str
    plan_name: str
    billing_cycle: str
    status: str
    amount: float
    start_date: date
    renews_on: date | None
    cancelled_on: date | None
    row_version: str


class InvoiceIn(ApiModel):
    customer_id: int
    issue_date: date
    due_date: date
    amount: Decimal = Field(gt=0)


class InvoiceStatusIn(ApiModel):
    status: Literal["paid", "void"]
    paid_on: date | None = None
    payment_reference: str | None = Field(None, max_length=100)
    row_version: str


class InvoiceOut(ApiModel):
    id: str
    number: str
    customer_id: str
    customer_name: str
    issue_date: date
    due_date: date
    amount: float
    status: str
    paid_on: date | None
    payment_reference: str | None
    row_version: str


class LeadIn(ApiModel):
    company_name: str = Field(min_length=1, max_length=200)
    contact_name: str | None = Field(None, max_length=200)
    contact_email: str | None = Field(None, max_length=254)
    contact_phone: str | None = Field(None, max_length=50)
    source: str | None = Field(None, max_length=50)
    stage: Literal["new", "contacted", "demo", "proposal", "won", "lost"] = "new"
    employee_count: int | None = Field(None, ge=1)
    expected_monthly: Decimal | None = Field(None, ge=0)
    next_follow_up: date | None = None
    notes: str | None = Field(None, max_length=1000)
    owner_staff_id: int | None = None
    row_version: str | None = None


class LeadOut(ApiModel):
    id: str
    company_name: str
    contact_name: str | None
    contact_email: str | None
    contact_phone: str | None
    source: str | None
    stage: str
    employee_count: int | None
    expected_monthly: float | None
    next_follow_up: date | None
    notes: str | None
    owner_staff_id: str | None
    owner_name: str | None
    customer_id: str | None
    row_version: str


class TicketIn(ApiModel):
    customer_id: int
    subject: str = Field(min_length=1, max_length=200)
    detail: str | None = Field(None, max_length=2000)
    priority: Literal["low", "normal", "high", "urgent"] = "normal"
    status: Literal["open", "in_progress", "resolved", "closed"] = "open"
    assignee_staff_id: int | None = None
    row_version: str | None = None


class TicketOut(ApiModel):
    id: str
    customer_id: str
    customer_name: str
    subject: str
    detail: str | None
    priority: str
    status: str
    assignee_staff_id: str | None
    assignee_name: str | None
    resolved_at: datetime | None
    created_at: datetime
    row_version: str


class DashboardFigures(ApiModel):
    organisations: int
    active_organisations: int
    suspended_organisations: int
    cancelled_organisations: int
    new_this_month: int
    employees: int
    trials: int
    paying_subscriptions: int
    past_due_subscriptions: int
    open_leads: int
    open_tickets: int
    urgent_tickets: int
    # Money, for the roles that work with it (empty otherwise).
    monthly_revenue: float | None
    overdue_invoices: int | None
    overdue_amount: float | None
    paid_this_month: float | None
    pipeline_monthly: float | None


class DashboardMonth(ApiModel):
    month: str
    organisations: int


class DashboardPlan(ApiModel):
    plan: str
    subscriptions: int


class DashboardStage(ApiModel):
    stage: str
    leads: int
    monthly: float | None


class DashboardRenewal(ApiModel):
    id: str
    customer_id: str
    customer_name: str
    plan_name: str
    status: str
    renews_on: date
    amount: float | None


class DashboardOut(ApiModel):
    figures: DashboardFigures
    months: list[DashboardMonth]
    plans: list[DashboardPlan]
    stages: list[DashboardStage]
    renewals: list[DashboardRenewal]
