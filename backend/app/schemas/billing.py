"""The organisation's own subscription and billing (Settings -> Subscription): /api/billing."""
from datetime import date, datetime
from decimal import Decimal

from pydantic import Field

from app.schemas.common import ApiModel

EMAIL = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"


class BillingState(ApiModel):
    """The few facts every screen needs (in /auth/me): the banner and the read-only and locked states."""
    status: str | None
    # full, read_only or locked: what the organisation's people may do.
    access: str
    plan_name: str | None
    renews_on: date | None
    # Days until a trial ends (0 on its last day); null when not on a trial.
    trial_days_left: int | None
    next_invoice_due: date | None


class BillingInvoiceRef(ApiModel):
    id: str
    number: str
    amount: float
    due_date: date
    # A bank transfer proof for it is waiting for hRango to confirm.
    proof_pending: bool = False


class BillingDetails(ApiModel):
    billing_name: str | None
    billing_email: str | None
    billing_address: str | None
    tax_number: str | None
    # Where billing e-mails go when billing_email is blank (the address the organisation signed up with).
    contact_email: str


class BillingSeller(ApiModel):
    name: str
    address: str | None
    tax_number: str | None


class BillingUsage(ApiModel):
    employee_limit: int | None
    employees_used: int
    company_count: int


class BillingOut(ApiModel):
    customer_name: str
    plan_name: str | None
    status: str | None
    access: str
    access_since: date | None
    billing_cycle: str | None
    amount: float | None
    start_date: date | None
    renews_on: date | None
    trial_days_left: int | None
    open_count: int
    open_amount: float
    next_invoice: BillingInvoiceRef | None
    details: BillingDetails
    usage: BillingUsage | None
    # How to pay: the bank account (several lines) and who invoices are from.
    bank_details: str | None
    seller: BillingSeller


class PaymentProof(ApiModel):
    status: str
    reference: str
    paid_on: date
    review_note: str | None
    sent_at: datetime


class BillingInvoiceOut(ApiModel):
    id: str
    number: str
    issue_date: date
    due_date: date
    amount: float
    # issued, overdue, paid or void
    status: str
    paid_on: date | None
    payment_reference: str | None
    # renewal (a subscription period) or manual (issued by hRango)
    source: str
    period_start: date | None
    period_end: date | None
    # The latest bank transfer proof sent for it.
    proof: PaymentProof | None


class BillTo(ApiModel):
    name: str
    email: str
    address: str | None
    tax_number: str | None


class BillingInvoiceDetailOut(BillingInvoiceOut):
    """One invoice as it is printed: who it is from and to, what it is for, and how to pay it."""
    bill_to: BillTo
    plan_name: str | None
    billing_cycle: str | None
    seller: BillingSeller
    bank_details: str | None


class BillingDetailsIn(ApiModel):
    billing_name: str | None = Field(None, max_length=200)
    billing_email: str | None = Field(None, max_length=254, pattern=EMAIL)
    billing_address: str | None = Field(None, max_length=500)
    tax_number: str | None = Field(None, max_length=50)


class PaymentSubmitIn(ApiModel):
    reference: str = Field(min_length=1, max_length=100)
    paid_on: date
    amount: Decimal = Field(gt=0)
    # An upload (POST /api/files, module billing): the transfer slip or a screenshot.
    file_id: int | None = None
    note: str | None = Field(None, max_length=500)
