"""Payroll e-mails: the close e-mail of a monthly run (P1) and the salary revision letter (P2).

Mail is not set up yet (`app.core.mail.enabled()` is false): the close records the e-mail as 'disabled' and
asking to send a revision letter records 'disabled'; nothing leaves the server. When mail is enabled the rows
are recorded 'queued' in pay.mail_outbox.
TODO(payroll): when the SMTP sender exists (app/core/mail.py), deliver queued pay.mail_outbox rows, mark them
'sent' / 'failed' (with the error), and set pay.payroll_close_email.status / sent_at when a run's rows are done.
TODO(payroll): the subject and body are a plain built-in template; company-editable templates (and the two
"e-mail" options of Settings -> General) are not built.
"""
from datetime import date
from html import escape
from typing import Any

from app.core import mail
from app.core.db import Db
from app.middlewares.auth import RequestContext
from app.repos import payroll_runs_repo as runs_repo
from app.repos import payroll_records_repo as records_repo

Row = dict[str, Any]
REVISION_VIEW, REVISION_SEND = "payroll.salary_revision.view", "payroll.salary_revision.send"


def _month(d: date | None) -> str:
    return d.strftime("%B %Y") if d else ""


def _money(amount, currency: str | None) -> str:
    return f"{currency + ' ' if currency else ''}{float(amount or 0):,.2f}"


def _page(company: str | None, paragraphs: list[str]) -> str:
    body = "".join(f"<p>{p}</p>" for p in paragraphs)
    sign = f"<p>Regards,<br>{escape(company or 'HR')}</p>"
    return f'<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.5">{body}{sign}</div>'


# --------------------------------------------------------------------------- P1 close e-mail

def close_email_text(head: Row) -> tuple[str, str]:
    """Subject and HTML body of a run's close e-mail. One text for everyone (no amounts in it)."""
    month = _month(head.get("payroll_month"))
    subject = f"Your payslip for {month} is ready" if month else "Your payslip is ready"
    body = _page(head.get("company_name"), [
        "Dear colleague,",
        f"Your payslip for {escape(month or head.get('name') or '')} has been released. "
        "Sign in to HRango and open Payroll &gt; Pay Slips to see it.",
    ])
    return subject, body


def close_email_preview(db: Db, ctx: RequestContext, id: int) -> Row:
    head = runs_repo.close_email_preview(db, ctx.company_id, id)
    subject, body = close_email_text(head)
    return {"enabled": mail.enabled(), "subject": subject, "body_html": body,
            "recipient_count": head["recipient_count"] or 0}


def close_email_subject(db: Db, ctx: RequestContext, id: int) -> str:
    return close_email_text(runs_repo.close_email_preview(db, ctx.company_id, id))[0]


def close_email(db: Db, ctx: RequestContext, id: int) -> Row:
    head, failures = runs_repo.close_email_get(db, ctx.company_id, id)
    return {**head, "failures": failures}


# --------------------------------------------------------------------------- P2 salary revision letter

def revision_email_text(r: Row) -> tuple[str, str]:
    effective = r["effective_date"].strftime("%d %B %Y") if r.get("effective_date") else ""
    subject = f"Salary revision effective {effective}" if effective else "Salary revision"
    currency = r.get("currency")
    lines = [f"Dear {escape(r.get('employee_name') or 'colleague')},"]
    if r.get("previous_amount") is not None:
        lines.append(f"Your monthly salary has been revised from {_money(r['previous_amount'], currency)} to "
                     f"<b>{_money(r['amount'], currency)}</b>, effective {escape(effective)}.")
    else:
        lines.append(f"Your monthly salary is <b>{_money(r['amount'], currency)}</b>, effective {escape(effective)}.")
    return subject, _page(r.get("company_name"), lines)


def revision_email_preview(db: Db, ctx: RequestContext, id: int) -> Row:
    r = records_repo.revision_email_get(db, ctx.company_id, ctx.user_id, REVISION_VIEW, id)
    subject, body = revision_email_text(r)
    return {"subject": subject, "body_html": body, "to": r["to_address"] or ""}


def send_revision_email(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> Row:
    r = records_repo.revision_email_get(db, ctx.company_id, ctx.user_id, REVISION_SEND, id)
    subject, _ = revision_email_text(r)
    return records_repo.revision_email_send(db, ctx.company_id, ctx.user_id, REVISION_SEND, id, row_version,
                                            mail.enabled(), subject)
