"""Sample data for the staff portal, on a development database only:

    .venv\\Scripts\\python.exe -m scripts.demo_platform

Adds the plans, makes the existing companies organisations, and registers made-up organisations through the same
code the portal uses, so each is a real company with an Account Owner. Prices are placeholders. Safe to run again.
"""
import secrets
import sys
from datetime import date, timedelta
from typing import Any

from app.core.config import settings
from app.core.db import Db, connect
from app.repos import platform_repo as repo
from app.services import platform_service as service
from scripts.seed import db_name

PLANS = [("Basic", "Attendance, leave and the employee record.", 15000, 150000, 50),
         ("Advanced", "Adds payroll, recruitment and performance.", 35000, 350000, 250),
         ("Premium", "Every module, no limit on employees.", 75000, 750000, None)]

# name, contact, country, months ago, plan, cycle, subscription status, organisation status
ORGANISATIONS = [
    ("Indus Textile Mills", "Hira Malik", "Pakistan", 10, "Premium", "annual", "active", "active"),
    ("Margalla Foods", "Bilal Ahmed", "Pakistan", 8, "Advanced", "monthly", "active", "active"),
    ("Karachi Port Logistics", "Sana Iqbal", "Pakistan", 7, "Advanced", "annual", "active", "active"),
    ("Gulf Edge Trading FZ-LLC", "Omar Farooq", "United Arab Emirates", 5, "Premium", "monthly", "past_due", "active"),
    ("Lahore Software House", "Ayla Raza", "Pakistan", 4, "Basic", "monthly", "active", "active"),
    ("Sialkot Sports Works", "Hamza Tariq", "Pakistan", 3, "Basic", "monthly", "active", "suspended"),
    ("Peshawar Pharma", "Zainab Khan", "Pakistan", 1, "Advanced", "monthly", "trial", "active"),
    ("Quetta Minerals", "Yousaf Baloch", "Pakistan", 0, "Basic", "monthly", "trial", "active"),
]

# company, contact, source, stage, employees, expected a month, follow up in days
LEADS = [
    ("Faisalabad Knitwear", "Asad Mehmood", "referral", "proposal", 320, 35000, 3),
    ("Multan Agro", "Nimra Sheikh", "website", "demo", 140, 35000, 5),
    ("Rawal Construction", "Kamran Ali", "event", "contacted", 600, 75000, 7),
    ("Hyderabad Cables", "Fatima Noor", "outbound", "new", 90, 15000, 2),
    ("Blue Area Consulting", "Salman Yousuf", "website", "new", 35, 15000, 1),
    ("Thar Energy Services", "Mariam Aziz", "referral", "demo", 410, 75000, 10),
    ("Northern Hotels", "Daniyal Shah", "event", "lost", 220, 35000, None),
]

# organisation, subject, priority, status
TICKETS = [
    ("Indus Textile Mills", "Biometric device is not sending punches", "urgent", "open"),
    ("Margalla Foods", "Need help closing the October payroll", "high", "in_progress"),
    ("Karachi Port Logistics", "How do we add a second company?", "normal", "open"),
    ("Lahore Software House", "Change the Account Owner", "low", "resolved"),
    ("Peshawar Pharma", "Import employees from a spreadsheet", "normal", "open"),
]


def months_back(today: date, months: int) -> date:
    total = today.year * 12 + today.month - 1 - months
    return date(total // 12, total % 12 + 1, min(today.day, 28))


def next_renewal(start: date, today: date, annual: bool) -> date:
    step = 12 if annual else 1
    current = start
    while current <= today:
        total = current.year * 12 + current.month - 1 + step
        current = date(total // 12, total % 12 + 1, current.day)
    return current


def invoices(db: Db, actor: int, customer_id: int, amount: float, start: date, today: date, annual: bool,
             late: bool) -> None:
    months = 12 if annual else 1
    issue = start
    while issue <= today:
        row = repo.add_invoice(db, actor, {"customer_id": customer_id, "issue_date": issue,
                                           "due_date": issue + timedelta(days=15), "amount": amount})
        due = issue + timedelta(days=15)
        last = months_back(today, months) <= issue
        if not (late and last) and due < today:
            repo.set_invoice_status(db, actor, row["id"], {"status": "paid", "paid_on": due - timedelta(days=4),
                                                           "payment_reference": f"BANK-{row['id']:05d}"},
                                    row["row_version"])
        total = issue.year * 12 + issue.month - 1 + months
        issue = date(total // 12, total % 12 + 1, issue.day)


def main() -> None:
    name = db_name(settings.db_url)
    if not name.endswith("_dev"):
        sys.exit(f"Refusing: {name} is not a development database.")
    db = Db(connect())
    today = date.today()
    actor = db.conn.cursor().execute("SELECT TOP 1 id FROM plat.staff_account WHERE role = N'super_admin' ORDER BY id").fetchval()
    if actor is None:
        sys.exit("Add the Super Admin first: python -m scripts.seed --platform-admin <email>")

    plans = {p["name"]: p for p in repo.list_plans(db)}
    for plan_name, description, monthly, annual, limit in PLANS:
        if plan_name not in plans:
            plans[plan_name] = repo.save_plan(db, actor, None, {
                "name": plan_name, "description": description, "price_monthly": monthly, "price_annual": annual,
                "employee_limit": limit, "is_active": True}, None)

    cur = db.conn.cursor()
    known = {c["name"]: c for c in repo.list_page(db, "plat.usp_customer_list", search=None, status=None, page=1,
                                                  page_size=100)[1]}

    # Companies from the first install: they are organisations already, with no record yet.
    loose = cur.execute("""SELECT co.id, co.name, u.email, u.display_name FROM org.company co
        LEFT JOIN auth.user_account u ON u.company_id = co.id AND u.is_account_owner = 1
        WHERE NOT EXISTS (SELECT 1 FROM plat.customer_company cc WHERE cc.company_id = co.id)""").fetchall()
    for company_id, company, email, owner in loose:
        known[company] = repo.add_customer(db, actor, company_id, {
            "name": company, "contact_name": owner, "contact_email": email or "contact@hrango.local",
            "contact_phone": None, "country": "Pakistan", "notes": None}, None)
        cur.execute("UPDATE plat.customer SET created_at = ? WHERE id = ?", months_back(today, 11), known[company]["id"])
        start = months_back(today, 11)
        sub = repo.save_subscription(db, actor, None, {
            "customer_id": known[company]["id"], "plan_id": plans["Premium"]["id"], "billing_cycle": "annual",
            "status": "active", "amount": None, "start_date": start,
            "renews_on": next_renewal(start, today, True)}, None)
        invoices(db, actor, known[company]["id"], float(sub["amount"]), start, today, True, False)

    for org, contact, country, months, plan, cycle, sub_status, status in ORGANISATIONS:
        if org in known:
            continue
        slug = "".join(ch for ch in org.lower() if ch.isalnum())[:30]
        row = service.register_customer(db, actor, {
            "name": org, "contact_name": contact, "contact_email": f"contact@{slug}.example", "contact_phone": None,
            "country": country, "notes": "Sample data.", "owner_name": contact,
            "owner_email": f"owner@{slug}.example", "owner_password": secrets.token_urlsafe(16), "plan_id": None,
            "lead_id": None})
        start = months_back(today, months)
        cur.execute("UPDATE plat.customer SET created_at = ? WHERE id = ?", start, row["id"])
        annual = cycle == "annual"
        renews = today + timedelta(days=9) if sub_status == "trial" else next_renewal(start, today, annual)
        sub = repo.save_subscription(db, actor, None, {
            "customer_id": row["id"], "plan_id": plans[plan]["id"], "billing_cycle": cycle, "status": sub_status,
            "amount": None, "start_date": start, "renews_on": renews}, None)
        if sub_status != "trial":
            invoices(db, actor, row["id"], float(sub["amount"]), start, today, annual, sub_status == "past_due")
        if status != "active":
            fresh = repo.get_customer(db, row["id"])
            repo.set_customer_status(db, actor, row["id"], status, fresh["row_version"])
        known[org] = row

    if not repo.list_page(db, "plat.usp_lead_list", search=None, stage=None, page=1, page_size=1)[0]:
        for company, contact, source, stage, people, expected, days in LEADS:
            slug = "".join(ch for ch in company.lower() if ch.isalnum())
            repo.save_lead(db, actor, None, {
                "company_name": company, "contact_name": contact, "contact_email": f"info@{slug}.example",
                "contact_phone": None, "source": source, "stage": stage, "employee_count": people,
                "expected_monthly": expected, "next_follow_up": today + timedelta(days=days) if days else None,
                "notes": None, "owner_staff_id": actor}, None)

    if not repo.list_page(db, "plat.usp_ticket_list", search=None, status=None, customer_id=None, page=1, page_size=1)[0]:
        for org, subject, priority, status in TICKETS:
            repo.save_ticket(db, actor, None, {
                "customer_id": known[org]["id"], "subject": subject, "detail": None, "priority": priority,
                "status": status, "assignee_staff_id": None}, None)

    figures: dict[str, Any] = repo.dashboard(db)[0][0]
    print({k: figures[k] for k in ("organisations", "trials", "paying_subscriptions", "monthly_revenue",
                                   "overdue_invoices", "open_leads", "open_tickets")})


if __name__ == "__main__":
    main()
