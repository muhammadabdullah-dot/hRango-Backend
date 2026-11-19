"""The organisation's own subscription and billing (Settings -> Subscription): its plan, invoices and billing
details, and sending proof of a bank transfer. Open to the Account Owner even while access is locked
(app/middlewares/auth.py), so a locked organisation can still pay."""
from fastapi import APIRouter, Depends, status

from app.controllers import billing_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.billing import (
    BillingDetailsIn,
    BillingInvoiceDetailOut,
    BillingInvoiceOut,
    BillingOut,
    PaymentSubmitIn,
)
from app.schemas.common import Item, Paginated

router = APIRouter(prefix="/billing", tags=["billing"])
VIEW = require("billing.subscription.view")


@router.get("", response_model=Item[BillingOut | None])
def get_billing(db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    """Plan, status and access, what is owed, billing details, plan usage and how to pay. null when the company
    belongs to no hRango organisation."""
    return c.get_overview(db, ctx)


@router.put("/details", response_model=Item[BillingOut])
def save_details(body: BillingDetailsIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("billing.subscription.edit"))) -> dict:
    """What invoices are made out to (legal name, address, NTN) and where billing e-mails go."""
    return c.save_details(db, ctx, body)


@router.get("/invoices", response_model=Paginated[BillingInvoiceOut])
def list_invoices(paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_invoices(db, ctx, paging)


@router.get("/invoices/{invoice_id}", response_model=Item[BillingInvoiceDetailOut])
def get_invoice(invoice_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    """One invoice as it is printed (404 for another organisation's)."""
    return c.get_invoice(db, ctx, invoice_id)


@router.post("/invoices/{invoice_id}/payments", response_model=Item[BillingInvoiceDetailOut],
             status_code=status.HTTP_201_CREATED)
def submit_payment(invoice_id: int, body: PaymentSubmitIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("billing.subscription.submit"))) -> dict:
    """"We paid by bank transfer": the reference, date, amount and a proof (an upload, module billing). It waits
    for hRango to confirm (409 PAYMENT_PENDING while one does; 409 INVOICE_CLOSED for a paid or void invoice)."""
    return c.submit_payment(db, ctx, invoice_id, body)
