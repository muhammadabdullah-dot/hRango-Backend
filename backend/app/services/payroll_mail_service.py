"""Payroll e-mails: the close e-mail of a monthly run (P1) and the salary revision letter (P2).

The procedures record one pay.mail_outbox row per person: 'disabled' while mail is off (`app.core.mail.enabled()`
false, nothing leaves the server), else 'queued'. A queued row is then handed to the mail sender here: each person
gets their own message (the close e-mail says the payslip is ready, without amounts; the revision letter goes to
the person it is about), queued in core.mail_message with `app.core.mail.queue` and linked to the row
(pay.usp_mail_outbox_hand_off). The mail worker sends it (`mail.deliver_due`, app/services/webhook_dispatcher.py)
and copies the result back to the row and to the run's close e-mail state (pay.usp_mail_outbox_result): queued ->
sent / failed. A row the sender refuses outright (an address it does not accept) is marked failed at once.
TODO(payroll): company-editable templates (and the two "e-mail" options of Settings -> General) are not built.
"""
from datetime import date
from typing import Any

from app.core import mail
from app.core.config import settings
from app.core.db import Db
from app.core.errors import AppError
from app.core.mail_templates import Button, render
from app.middlewares.auth import RequestContext
from app.repos import payroll_runs_repo as runs_repo
from app.repos import payroll_records_repo as records_repo

Row = dict[str, Any]
REVISION_VIEW, REVISION_SEND = "payroll.salary_revision.view", "payroll.salary_revision.send"
CLOSE_KIND, REVISION_KIND = "payroll_close", "salary_revision"


def _month(d: date | None) -> str:
    return d.strftime("%B %Y") if d else ""


def _money(amount, currency: str | None) -> str:
    return f"{currency + ' ' if currency else ''}{float(amount or 0):,.2f}"


def _app_link(path: str) -> Button | None:
    base = (settings.app_public_url or "").rstrip("/")
    return Button("Open hRango", f"{base}{path}") if base else None


# --------------------------------------------------------------------------- P1 close e-mail

def close_email_text(head: Row, name: str | None = None) -> tuple[str, str, str]:
    """Subject, HTML and plain text of one person's close e-mail. No amounts: only that the payslip is out."""
    month = _month(head.get("payroll_month"))
    subject = f"Your payslip for {month} is ready" if month else "Your payslip is ready"
    html, text = render(
        title=subject,
        paragraphs=[f"Hello {name or 'colleague'},",
                    f"Your payslip for {month or head.get('name') or 'this month'} has been released. Sign in to "
                    "hRango and open Payroll > Pay Slips > My Pay Slips to see it."],
        button=_app_link("/payroll/pay-slips/my"), company_name=head.get("company_name"))
    return subject, html, text


def close_email_preview(db: Db, ctx: RequestContext, id: int) -> Row:
    head = runs_repo.close_email_preview(db, ctx.company_id, id)
    subject, body, _ = close_email_text(head)
    return {"enabled": mail.enabled(), "subject": subject, "body_html": body,
            "recipient_count": head["recipient_count"] or 0}


def close_email_subject(db: Db, ctx: RequestContext, id: int) -> str:
    return close_email_text(runs_repo.close_email_preview(db, ctx.company_id, id))[0]


def close_email(db: Db, ctx: RequestContext, id: int) -> Row:
    head, failures = runs_repo.close_email_get(db, ctx.company_id, id)
    return {**head, "failures": failures}


def send_close_email(db: Db, ctx: RequestContext, id: int) -> None:
    """Queues each person's close e-mail of a run just closed (its 'queued' rows) with the mail sender."""
    rows = runs_repo.mail_outbox_pending(db, ctx.company_id, "pay.payroll", id)
    if rows:
        head = runs_repo.close_email_preview(db, ctx.company_id, id)
        for row in rows:
            _, html, text = close_email_text(head, row["employee_name"])
            _hand_off(db, ctx, row, CLOSE_KIND, row["subject"] or close_email_text(head)[0], html, text)
    runs_repo.close_email_refresh(db, id)


# --------------------------------------------------------------------------- P2 salary revision letter

def revision_email_text(r: Row) -> tuple[str, str, str]:
    """Subject, HTML and plain text of the letter to the person whose salary was revised."""
    effective = r["effective_date"].strftime("%d %B %Y") if r.get("effective_date") else ""
    subject = f"Salary revision effective {effective}" if effective else "Salary revision"
    currency = r.get("currency")
    lines = [f"Hello {r.get('employee_name') or 'colleague'},"]
    if r.get("previous_amount") is not None:
        lines.append(f"Your monthly salary has been revised from {_money(r['previous_amount'], currency)} to "
                     f"{_money(r['amount'], currency)}, effective {effective}.")
    else:
        lines.append(f"Your monthly salary is {_money(r['amount'], currency)}, effective {effective}.")
    lines.append("Your pay slips from that date show the new salary.")
    html, text = render(title=subject, paragraphs=lines, company_name=r.get("company_name"))
    return subject, html, text


def revision_email_preview(db: Db, ctx: RequestContext, id: int) -> Row:
    r = records_repo.revision_email_get(db, ctx.company_id, ctx.user_id, REVISION_VIEW, id)
    subject, body, _ = revision_email_text(r)
    return {"subject": subject, "body_html": body, "to": r["to_address"] or ""}


def send_revision_email(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> Row:
    r = records_repo.revision_email_get(db, ctx.company_id, ctx.user_id, REVISION_SEND, id)
    subject, html, text = revision_email_text(r)
    state = records_repo.revision_email_send(db, ctx.company_id, ctx.user_id, REVISION_SEND, id, row_version,
                                             mail.enabled(), subject)
    rows = runs_repo.mail_outbox_pending(db, ctx.company_id, "hr.employee_salary", id)
    for row in rows:
        state = {"status": _hand_off(db, ctx, row, REVISION_KIND, subject, html, text), "sent_at": None}
    return state


# --------------------------------------------------------------------------- handing a row to the mail sender

def _hand_off(db: Db, ctx: RequestContext, row: Row, kind: str, subject: str, html: str, text: str) -> str:
    """Queues one person's message and links it to their pay.mail_outbox row in one transaction; returns the row's
    new status ('queued', 'disabled' when mail was switched off meanwhile, 'failed' when the address is refused)."""
    try:
        with db.transaction():
            queued = mail.queue(db, kind=kind, to_address=row["to_address"] or "", to_name=row["employee_name"],
                                subject=subject, body_html=html, body_text=text, company_id=ctx.company_id,
                                actor_id=ctx.user_id)
            runs_repo.mail_outbox_hand_off(db, row["id"], int(queued["id"]), queued["status"], None)
        return queued["status"]
    except AppError as exc:
        runs_repo.mail_outbox_hand_off(db, row["id"], None, "failed", exc.message)
        return "failed"
