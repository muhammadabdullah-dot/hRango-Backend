"""Billing procedures (db/procedures/plat/usp_billing_lifecycle.sql): the nightly run, the organisation's own
billing, and payment proofs."""
from datetime import date
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def run(db: Db, today: date | None, renewal_days: int, read_only_at: int, locked_at: int,
        trial_locked_at: int, customer_id: int | None = None) -> list[Row]:
    return db.call("plat.usp_billing_run", today=today, renewal_days=renewal_days, read_only_at=read_only_at,
                   locked_at=locked_at, trial_locked_at=trial_locked_at, customer_id=customer_id)


def invoice_mail_target(db: Db, invoice_id: int) -> Row | None:
    return db.call_one("plat.usp_invoice_mail_target", invoice_id=invoice_id)


def overview(db: Db, company_id: int) -> Row | None:
    return db.call_one("plat.usp_billing_overview", company_id=company_id)


def usage(db: Db, company_id: int) -> Row | None:
    return db.call_one("plat.usp_plan_usage", company_id=company_id)


def invoices(db: Db, company_id: int, page: int, page_size: int) -> tuple[int, list[Row]]:
    sets = db.call_sets("plat.usp_billing_invoice_list", company_id=company_id, page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1]


def invoice(db: Db, company_id: int, invoice_id: int) -> Row:
    return db.call_one("plat.usp_billing_invoice_get", company_id=company_id, id=invoice_id)


def save_details(db: Db, company_id: int, user_id: int, f: Row) -> Row:
    return db.call_one("plat.usp_billing_details_save", company_id=company_id, actor_user_id=user_id,
                       billing_name=f["billing_name"], billing_email=f["billing_email"],
                       billing_address=f["billing_address"], tax_number=f["tax_number"])


def submit_payment(db: Db, company_id: int, user_id: int, invoice_id: int, f: Row) -> Row:
    return db.call_one("plat.usp_payment_submit", company_id=company_id, actor_user_id=user_id, invoice_id=invoice_id,
                       reference=f["reference"], paid_on=f["paid_on"], amount=f["amount"], file_id=f["file_id"],
                       note=f["note"])


def payments(db: Db, status: str | None, page: int, page_size: int) -> tuple[int, list[Row]]:
    sets = db.call_sets("plat.usp_payment_submission_list", status=status, page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1]


def review_payment(db: Db, staff_id: int, submission_id: int, decision: str, note: str | None,
                   row_version: bytes) -> Row:
    return db.call_one("plat.usp_payment_submission_review", actor_id=staff_id, id=submission_id, decision=decision,
                       note=note, row_version=row_version)


def extend_trial(db: Db, staff_id: int, subscription_id: int, days: int, row_version: bytes) -> Row:
    return db.call_one("plat.usp_subscription_trial_extend", actor_id=staff_id, id=subscription_id, days=days,
                       row_version=row_version)
