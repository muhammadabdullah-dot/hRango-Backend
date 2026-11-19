"""Billing without a payment gateway (roadmap: billing phase 1).

The nightly run (`run_daily`, scripts/nightly.py) issues renewal invoices, ends trials and restricts access when an
invoice stays unpaid (plat.usp_billing_run; the rules are at the top of db/procedures/plat/usp_billing_lifecycle.sql),
then e-mails each organisation what changed. Customers see their plan and invoices on Billing and send proof of a
bank transfer; staff accept or reject it in the Platform portal (Payments), and a payment restores access at once.
Procedure calls are in app/repos/billing_repo.py.
"""
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

from app.core import mail
from app.core.config import settings
from app.core.db import Db
from app.core.errors import AppError
from app.core.mail_templates import Button, render
from app.repos import billing_repo as repo

# Grace periods, in days after an invoice's due date. Keep them in step with the defaults of
# plat.usp_subscription_access_refresh (a payment or a voided invoice works access out with those).
READ_ONLY_AT = 14        # a paying customer: read-only from the 14th day late
LOCKED_AT = 30           # ... and locked from the 30th
TRIAL_LOCKED_AT = 8      # a trial never paid: read-only the day after it ends, locked a week later
RENEWAL_DAYS = 7         # renewal invoices are issued this many days before the subscription renews

BILLING_PATH = "/settings/control-panel/subscriptions"

Row = dict[str, Any]


# ---------------------------------------------------------------- formatting

def money(amount: Decimal | float | None) -> str:
    value = float(amount or 0)
    return f"PKR {value:,.0f}" if value == int(value) else f"PKR {value:,.2f}"


def day(d: date | None) -> str:
    return f"{d.day} {d:%b %Y}" if d else ""


def _billing_url() -> str:
    return settings.app_public_url.rstrip("/") + BILLING_PATH


def _bank_lines() -> list[str]:
    lines = [ln.strip() for ln in settings.billing_bank_details.replace("\\n", "\n").splitlines() if ln.strip()]
    return ["Pay by bank transfer to:", *lines] if lines else []


def _period(row: Row) -> str:
    if row.get("period_start") and row.get("period_end"):
        return f" for {day(row['period_start'])} to {day(row['period_end'])}"
    return ""


def bank_details() -> str | None:
    text = settings.billing_bank_details.replace("\\n", "\n").strip()
    return text or None


def seller() -> dict[str, Any]:
    return {"name": settings.billing_seller_name or "hRango", "address": settings.billing_seller_address or None,
            "tax_number": settings.billing_seller_tax_number or None}


# ---------------------------------------------------------------- the nightly run and its e-mails

def _notice_message(n: Row) -> tuple[str, list[str], list[str]] | None:
    """(title, paragraphs, notes under the button) for one billing notice; None for a kind with no e-mail."""
    kind, org = n["kind"], n["customer_name"]
    number, amount, due = n.get("invoice_number"), money(n.get("invoice_amount")), n.get("due_date")
    trial = n["status"] in ("trial", "expired")
    pay = f"Pay invoice {number} ({amount})" if number else "Pay your invoice"
    send_ref = "After paying, send us the transfer's reference from Billing in hRango so we can confirm it."
    if kind == "invoice_issued":
        return (f"Your hRango invoice {number}",
                [f"Invoice {number} for {org}'s {n['plan_name'] or 'hRango'} plan{_period(n)} is ready: {amount}, "
                 f"due on {day(due)}.", send_ref], _bank_lines())
    if kind.startswith("trial_") and kind[6:].isdigit():
        left = int(kind[6:])
        when = "tomorrow" if left == 1 else f"in {left} days"
        return (f"Your hRango trial ends {when}",
                [f"{org}'s trial of the {n['plan_name'] or 'hRango'} plan ends on {day(n['renews_on'])}.",
                 f"To keep using hRango, {pay[0].lower() + pay[1:]} by then. When the trial ends unpaid, your "
                 "organisation becomes read-only (everything can be seen and exported, nothing changed), and access "
                 "is paused a week later.", send_ref], _bank_lines())
    if kind == "due_today":
        if trial:
            return ("Your hRango trial ends today",
                    [f"{org}'s trial ends today. {pay} today to keep working without interruption.", send_ref],
                    _bank_lines())
        return (f"Invoice {number} is due today", [f"{pay} today for {org}.", send_ref], _bank_lines())
    if kind in ("overdue_3", "overdue_7"):
        if trial:
            after = (f"Your organisation is read-only until it is paid, and access is paused on "
                     f"{day(due + timedelta(days=TRIAL_LOCKED_AT))}.")
        else:
            after = (f"If it stays unpaid, your organisation becomes read-only on "
                     f"{day(due + timedelta(days=READ_ONLY_AT))} and access is paused on "
                     f"{day(due + timedelta(days=LOCKED_AT))}.")
        return (f"Invoice {number} is overdue",
                [f"Invoice {number} for {org} ({amount}) was due on {day(due)}.", after, send_ref], _bank_lines())
    if kind == "trial_ended":
        return ("Your hRango trial has ended",
                [f"{org} is now read-only: everyone can still sign in, see and export, but nothing can be changed.",
                 f"{pay} to continue. If it stays unpaid, access is paused on "
                 f"{day(due + timedelta(days=TRIAL_LOCKED_AT))}. Your data is kept.", send_ref], _bank_lines())
    if kind == "read_only":
        return (f"{org} is now read-only on hRango",
                [f"Invoice {number} ({amount}) was due on {day(due)} and is still unpaid, so {org} is now read-only: "
                 "everything can be seen and exported, nothing changed.",
                 f"{pay} to restore it. If it stays unpaid, access is paused on "
                 f"{day(due + timedelta(days=LOCKED_AT))}.", send_ref], _bank_lines())
    if kind == "locked":
        return ("Access to hRango is paused",
                [f"Invoice {number} ({amount}) for {org} is still unpaid, so access is paused. Only the Account "
                 "Owner can sign in, to Billing. Your data is kept.",
                 f"{pay} and send us the reference to restore access for everyone.", send_ref], _bank_lines())
    return None


def _queue(db: Db, kind: str, to_address: str | None, to_name: str | None, title: str, paragraphs: list[str],
           after: list[str] | None = None, button: Button | None = None) -> None:
    if not to_address:
        return
    body_html, body_text = render(title=title, paragraphs=paragraphs, after=after,
                                  button=button or Button("Open Billing", _billing_url()))
    mail.queue(db, kind=f"billing_{kind}", to_address=to_address, to_name=to_name, subject=title,
               body_html=body_html, body_text=body_text)


def run_daily(db: Db, today: date | None = None, customer_id: int | None = None) -> list[Row]:
    """The nightly billing run (every organisation, or one); queues an e-mail for each notice it returns."""
    notices = repo.run(db, today, RENEWAL_DAYS, READ_ONLY_AT, LOCKED_AT, TRIAL_LOCKED_AT, customer_id)
    for n in notices:
        message = _notice_message(n)
        if message:
            title, paragraphs, after = message
            _queue(db, n["kind"], n["to_address"], n["to_name"], title, paragraphs, after)
    return notices


def mail_receipt(db: Db, invoice_id: int) -> None:
    """Payment received: once an invoice is paid (staff marked it, or accepted the bank transfer proof)."""
    t = repo.invoice_mail_target(db, invoice_id)
    if not t:
        return
    lines = [f"Thank you. We have recorded {money(t['invoice_amount'])} for invoice {t['invoice_number']}"
             f"{_period(t)}, paid on {day(t['paid_on'])}."]
    if t.get("renews_on") and t.get("status") == "active":
        lines.append(f"{t['customer_name']}'s {t['plan_name'] or 'hRango'} plan is active; it next renews on "
                     f"{day(t['renews_on'])}.")
    _queue(db, "payment_received", t["to_address"], t["to_name"], f"Payment received for {t['invoice_number']}", lines)


def mail_rejection(db: Db, submission: Row) -> None:
    _queue(db, "payment_rejected", submission["to_address"], submission["to_name"],
           f"We could not confirm your payment for {submission['invoice_number']}",
           [f"We could not match the bank transfer you sent for invoice {submission['invoice_number']} "
            f"(reference {submission['reference']}, {money(submission['amount'])}).",
            f"Reason: {submission['review_note']}",
            "Check the details and send it again from Billing in hRango."])


def mail_staff_proof(db: Db, submission: Row) -> None:
    """Tells hRango's billing team (BILLING_NOTIFY_EMAIL) that a proof is waiting."""
    if not settings.billing_notify_email:
        return
    _queue(db, "proof_sent", settings.billing_notify_email, None,
           f"Bank transfer to confirm: {submission['invoice_number']}",
           [f"{submission['customer_name']} says they paid {money(submission['amount'])} for invoice "
            f"{submission['invoice_number']} on {day(submission['paid_on'])}, reference {submission['reference']}.",
            "Check it against the bank statement, then accept or reject it in the Platform portal under Payments."],
           button=Button("Open Payments", settings.app_public_url.rstrip("/") + "/platform/payments"))


# ---------------------------------------------------------------- the organisation's own billing

def trial_days_left(status: str | None, renews_on: date | None, today: date | None = None) -> int | None:
    if status != "trial" or renews_on is None:
        return None
    return max(0, (renews_on - (today or date.today())).days)


def overview(db: Db, company_id: int) -> Row | None:
    return repo.overview(db, company_id)


def usage(db: Db, company_id: int) -> Row | None:
    return repo.usage(db, company_id)


def invoices(db: Db, company_id: int, page: int, page_size: int) -> tuple[int, list[Row]]:
    return repo.invoices(db, company_id, page, page_size)


def invoice(db: Db, company_id: int, invoice_id: int) -> Row:
    return repo.invoice(db, company_id, invoice_id)


def save_details(db: Db, company_id: int, user_id: int, f: Row) -> Row:
    return repo.save_details(db, company_id, user_id, f)


def submit_payment(db: Db, company_id: int, user_id: int, invoice_id: int, f: Row) -> Row:
    if overview(db, company_id) is None:
        raise AppError(404, "NOT_FOUND", "This organisation has no hRango account to bill.")
    row = repo.submit_payment(db, company_id, user_id, invoice_id, f)
    mail_staff_proof(db, row)
    return row


# ---------------------------------------------------------------- staff (Platform portal)

def review_payment(db: Db, staff_id: int, submission_id: int, decision: str, note: str | None,
                   row_version: bytes) -> Row:
    row = repo.review_payment(db, staff_id, submission_id, decision, note, row_version)
    if row["status"] == "accepted":
        mail_receipt(db, int(row["invoice_id"]))
    elif row["status"] == "rejected":
        mail_rejection(db, row)
    return row
