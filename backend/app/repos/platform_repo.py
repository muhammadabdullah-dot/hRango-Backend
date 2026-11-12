"""Platform staff: sign-in, sessions, accounts and their audit trail."""
from datetime import datetime
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def login_get(db: Db, email: str) -> Row | None:
    return db.call_one("plat.usp_staff_login_get", email=email)


def session_create(db: Db, staff_id: int, device: str | None, ip_address: str | None, expires_at: datetime) -> Row:
    return db.call_one("plat.usp_staff_session_create", staff_id=staff_id, device=device, ip_address=ip_address,
                       expires_at=expires_at.replace(tzinfo=None))


def session_context(db: Db, session_id: int, staff_id: int) -> Row | None:
    return db.call_one("plat.usp_staff_session_context", session_id=session_id, staff_id=staff_id)


def session_end(db: Db, session_id: int) -> None:
    db.call("plat.usp_staff_session_end", session_id=session_id)


def audit(db: Db, staff_id: int | None, action: str, ip_address: str | None = None, detail: str | None = None) -> None:
    db.call("plat.usp_staff_audit_add", staff_id=staff_id, action=action, ip_address=ip_address, detail=detail)


def list_staff(db: Db, search: str | None, page: int, page_size: int) -> tuple[int, list[Row]]:
    sets = db.call_sets("plat.usp_staff_list", search=search, page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1]


def get_staff(db: Db, staff_id: int) -> Row:
    return db.call_one("plat.usp_staff_get", id=staff_id)


def save_staff(db: Db, actor_id: int, staff_id: int | None, f: Row, password_hash: str | None,
               row_version: bytes | None) -> Row:
    return db.call_one("plat.usp_staff_save", actor_id=actor_id, id=staff_id, email=f["email"],
                       display_name=f["display_name"], role=f["role"], is_active=f["is_active"],
                       password_hash=password_hash, row_version=row_version)


def set_password(db: Db, actor_id: int, staff_id: int, password_hash: str) -> None:
    db.call("plat.usp_staff_password_set", actor_id=actor_id, id=staff_id, password_hash=password_hash)


def list_audit(db: Db, page: int, page_size: int) -> tuple[int, list[Row]]:
    sets = db.call_sets("plat.usp_staff_audit_list", page=page, page_size=page_size)
    return sets[0][0]["total"], sets[1]


def list_page(db: Db, proc: str, **params: Any) -> tuple[int, list[Row]]:
    sets = db.call_sets(proc, **params)
    return sets[0][0]["total"], sets[1]


def staff_lookup(db: Db) -> list[Row]:
    return db.call("plat.usp_staff_lookup")


def dashboard(db: Db) -> list[list[Row]]:
    return db.call_sets("plat.usp_dashboard")


def get_customer(db: Db, customer_id: int) -> Row:
    return db.call_one("plat.usp_customer_get", id=customer_id)


def customer_companies(db: Db, customer_id: int) -> list[Row]:
    return db.call("plat.usp_customer_companies", id=customer_id)


def register_check(db: Db, name: str, owner_email: str) -> None:
    db.call("plat.usp_customer_register_check", name=name, owner_email=owner_email)


def add_customer(db: Db, actor_id: int | None, company_id: int, f: Row, lead_id: int | None) -> Row:
    return db.call_one("plat.usp_customer_add", actor_id=actor_id, company_id=company_id, name=f["name"],
                       contact_name=f["contact_name"], contact_email=f["contact_email"],
                       contact_phone=f["contact_phone"], country=f["country"], notes=f["notes"], lead_id=lead_id)


def save_customer(db: Db, actor_id: int, customer_id: int, f: Row, row_version: bytes) -> Row:
    return db.call_one("plat.usp_customer_save", actor_id=actor_id, id=customer_id, name=f["name"],
                       contact_name=f["contact_name"], contact_email=f["contact_email"],
                       contact_phone=f["contact_phone"], country=f["country"], notes=f["notes"],
                       row_version=row_version)


def set_customer_status(db: Db, actor_id: int, customer_id: int, status: str, row_version: bytes) -> Row:
    return db.call_one("plat.usp_customer_status_set", actor_id=actor_id, id=customer_id, status=status,
                       row_version=row_version)


def list_plans(db: Db) -> list[Row]:
    return db.call("plat.usp_plan_list")


def save_plan(db: Db, actor_id: int, plan_id: int | None, f: Row, row_version: bytes | None) -> Row:
    return db.call_one("plat.usp_plan_save", actor_id=actor_id, id=plan_id, name=f["name"],
                       description=f["description"], price_monthly=f["price_monthly"], price_annual=f["price_annual"],
                       employee_limit=f["employee_limit"], is_active=f["is_active"], row_version=row_version)


def save_subscription(db: Db, actor_id: int, subscription_id: int | None, f: Row, row_version: bytes | None) -> Row:
    return db.call_one("plat.usp_subscription_save", actor_id=actor_id, id=subscription_id,
                       customer_id=f["customer_id"], plan_id=f["plan_id"], billing_cycle=f["billing_cycle"],
                       status=f["status"], amount=f["amount"], start_date=f["start_date"], renews_on=f["renews_on"],
                       row_version=row_version)


def add_invoice(db: Db, actor_id: int, f: Row) -> Row:
    return db.call_one("plat.usp_invoice_add", actor_id=actor_id, customer_id=f["customer_id"],
                       issue_date=f["issue_date"], due_date=f["due_date"], amount=f["amount"])


def set_invoice_status(db: Db, actor_id: int, invoice_id: int, f: Row, row_version: bytes) -> Row:
    return db.call_one("plat.usp_invoice_status_set", actor_id=actor_id, id=invoice_id, status=f["status"],
                       paid_on=f["paid_on"], payment_reference=f["payment_reference"], row_version=row_version)


def save_lead(db: Db, actor_id: int, lead_id: int | None, f: Row, row_version: bytes | None) -> Row:
    return db.call_one("plat.usp_lead_save", actor_id=actor_id, id=lead_id, company_name=f["company_name"],
                       contact_name=f["contact_name"], contact_email=f["contact_email"],
                       contact_phone=f["contact_phone"], source=f["source"], stage=f["stage"],
                       employee_count=f["employee_count"], expected_monthly=f["expected_monthly"],
                       next_follow_up=f["next_follow_up"], notes=f["notes"], owner_staff_id=f["owner_staff_id"],
                       row_version=row_version)


def save_ticket(db: Db, actor_id: int, ticket_id: int | None, f: Row, row_version: bytes | None) -> Row:
    return db.call_one("plat.usp_ticket_save", actor_id=actor_id, id=ticket_id, customer_id=f["customer_id"],
                       subject=f["subject"], detail=f["detail"], priority=f["priority"], status=f["status"],
                       assignee_staff_id=f["assignee_staff_id"], row_version=row_version)
