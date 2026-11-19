from typing import Any

from app.core.db import Db
from app.core.errors import not_found
from app.core.paging import PageParams
from app.middlewares.auth import RequestContext
from app.schemas.billing import (
    BillingDetails,
    BillingDetailsIn,
    BillingInvoiceDetailOut,
    BillingInvoiceOut,
    BillingInvoiceRef,
    BillingOut,
    BillingSeller,
    BillingState,
    BillingUsage,
    BillTo,
    PaymentProof,
    PaymentSubmitIn,
)
from app.schemas.common import paginated
from app.services import billing_service as s


def state(row: dict[str, Any] | None) -> BillingState | None:
    """The banner facts in /auth/me; None when the company belongs to no organisation or has no subscription."""
    if not row or row.get("subscription_id") is None:
        return None
    return BillingState(status=row["status"], access=row["access"], plan_name=row["plan_name"],
                        renews_on=row["renews_on"],
                        trial_days_left=s.trial_days_left(row["status"], row["renews_on"]),
                        next_invoice_due=row["next_invoice_due"])


def _overview(db: Db, ctx: RequestContext, row: dict[str, Any]) -> BillingOut:
    usage = s.usage(db, ctx.company_id)
    next_invoice = (BillingInvoiceRef(id=row["next_invoice_id"], number=row["next_invoice_number"],
                                      amount=row["next_invoice_amount"], due_date=row["next_invoice_due"],
                                      proof_pending=bool(row.get("next_invoice_proof_pending")))
                    if row["next_invoice_id"] else None)
    return BillingOut(
        customer_name=row["customer_name"], plan_name=row["plan_name"], status=row["status"],
        access=row["access"] or "full", access_since=row["access_since"], billing_cycle=row["billing_cycle"],
        amount=row["amount"], start_date=row["start_date"], renews_on=row["renews_on"],
        trial_days_left=s.trial_days_left(row["status"], row["renews_on"]),
        open_count=row["open_count"] or 0, open_amount=row["open_amount"] or 0, next_invoice=next_invoice,
        details=BillingDetails(billing_name=row["billing_name"], billing_email=row["billing_email"],
                               billing_address=row["billing_address"], tax_number=row["tax_number"],
                               contact_email=row["contact_email"]),
        usage=BillingUsage(employee_limit=usage["employee_limit"], employees_used=usage["employees_used"],
                           company_count=usage["company_count"]) if usage else None,
        bank_details=s.bank_details(), seller=BillingSeller(**s.seller()))


def get_overview(db: Db, ctx: RequestContext) -> dict:
    row = s.overview(db, ctx.company_id)
    return {"data": _overview(db, ctx, row) if row else None}


def _invoice(row: dict[str, Any]) -> BillingInvoiceOut:
    proof = (PaymentProof(status=row["proof_status"], reference=row["proof_reference"], paid_on=row["proof_paid_on"],
                          review_note=row["proof_review_note"], sent_at=row["proof_sent_at"])
             if row.get("proof_status") else None)
    return BillingInvoiceOut(id=row["id"], number=row["number"], issue_date=row["issue_date"],
                             due_date=row["due_date"], amount=row["amount"], status=row["status"],
                             paid_on=row["paid_on"], payment_reference=row["payment_reference"], source=row["source"],
                             period_start=row["period_start"], period_end=row["period_end"], proof=proof)


def list_invoices(db: Db, ctx: RequestContext, paging: PageParams) -> dict:
    total, rows = s.invoices(db, ctx.company_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _invoice)


def get_invoice(db: Db, ctx: RequestContext, invoice_id: int) -> dict:
    row = s.invoice(db, ctx.company_id, invoice_id)
    if row is None:
        raise not_found("Invoice")
    base = _invoice(row)
    return {"data": BillingInvoiceDetailOut(
        **base.model_dump(by_alias=False),
        bill_to=BillTo(name=row["bill_to_name"], email=row["bill_to_email"], address=row["bill_to_address"],
                       tax_number=row["bill_to_tax_number"]),
        plan_name=row["plan_name"], billing_cycle=row["billing_cycle"], seller=BillingSeller(**s.seller()),
        bank_details=s.bank_details())}


def save_details(db: Db, ctx: RequestContext, body: BillingDetailsIn) -> dict:
    row = s.save_details(db, ctx.company_id, ctx.user_id, body.model_dump(by_alias=False))
    return {"data": _overview(db, ctx, row)}


def submit_payment(db: Db, ctx: RequestContext, invoice_id: int, body: PaymentSubmitIn) -> dict:
    s.submit_payment(db, ctx.company_id, ctx.user_id, invoice_id, body.model_dump(by_alias=False))
    return get_invoice(db, ctx, invoice_id)
