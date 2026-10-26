"""Test helpers for the Requests and Loans modules. Records other modules own (schedules, leave
types, pay items) are written with plain SQL, as tests/factories.py does."""
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from app.core.db import Db
from tests import factories


def _scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def execute(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
        while cur.nextset():
            pass
    finally:
        cur.close()


@dataclass
class Person:
    employee_id: int
    user_id: int
    headers: dict


@dataclass
class Org:
    """A company with a small team: staff report to the manager, whose final authority is `fa`.
    `other` sits in another team under `other_manager`. `hr` is an HR Manager, `admin` a Company
    Administrator (both without an employee record)."""
    company_id: int
    department_id: int
    branch_id: int
    location_id: int
    fa: Person
    manager: Person
    staff: Person
    staff2: Person
    other_manager: Person
    other: Person
    hr: dict
    admin: dict


def person(db: Db, client, company_id: int, roles: str, branch_id: int, department_id: int,
           line_manager_id: int | None = None, final_authority_id: int | None = None, first_name: str = "Test",
           join: date | None = date(2020, 1, 1), employment_type_id: int | None = None) -> Person:
    emp = factories.employee(db, company_id, branch_id=branch_id, department_id=department_id,
                             line_manager_id=line_manager_id, first_name=first_name)
    execute(db, "UPDATE hr.employee SET final_authority_id = ?, employment_type_id = ?, location_id = "
                "(SELECT location_id FROM org.branch WHERE id = ?) WHERE id = ?",
            final_authority_id, employment_type_id, branch_id, emp)
    if join:
        execute(db, "INSERT hr.employment_period (employee_id, joining_date) VALUES (?, ?)", emp, join)
    who = factories.login_as(db, client, company_id, role_codes=roles, employee_id=emp)
    return Person(employee_id=emp, user_id=who["user_id"], headers=who["headers"])


def org(db: Db, client) -> Org:
    company_id = factories.company(db)
    location_id = factories.location(db, company_id)
    branch_id = factories.branch(db, company_id, location_id=location_id)
    department_id = factories.department(db, company_id)
    fa = person(db, client, company_id, "employee,line_manager", branch_id, department_id, first_name="Farah")
    manager = person(db, client, company_id, "employee,line_manager", branch_id, department_id,
                     line_manager_id=fa.employee_id, final_authority_id=fa.employee_id, first_name="Mansoor")
    staff = person(db, client, company_id, "employee", branch_id, department_id, line_manager_id=manager.employee_id,
                   final_authority_id=fa.employee_id, first_name="Sana")
    staff2 = person(db, client, company_id, "employee", branch_id, department_id, line_manager_id=manager.employee_id,
                    final_authority_id=fa.employee_id, first_name="Saad")
    other_manager = person(db, client, company_id, "employee,line_manager", branch_id, department_id,
                           final_authority_id=fa.employee_id, first_name="Omar")
    other = person(db, client, company_id, "employee", branch_id, department_id,
                   line_manager_id=other_manager.employee_id, final_authority_id=fa.employee_id, first_name="Owais")
    hr = factories.login_as(db, client, company_id, role_codes="hr_manager")
    admin = factories.login_as(db, client, company_id, role_codes="company_admin")
    return Org(company_id, department_id, branch_id, location_id, fa, manager, staff, staff2, other_manager, other,
               hr, admin)


def travel_body(start: date, days: int = 2, **extra) -> dict:
    depart = datetime.combine(start, time(9, 0))
    arrive = datetime.combine(start + timedelta(days=days - 1), time(18, 0))
    return {"details": {"purpose": "Client visit", "legs": [
        {"travelType": "domestic", "fromPlace": "Lahore", "toPlace": "Karachi", "travelMode": "air",
         "departAt": depart.isoformat(), "arriveAt": arrive.isoformat()}]}, **extra}


def time_slot(db: Db, company_id: int, start: time = time(9, 0), end: time = time(17, 0)) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT sch.time_slot (company_id, code, name, start_time, end_time, "
                       "duration_minutes, workable_minutes) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, 480, 480)",
                   company_id, f"TS-{factories.tag()}", f"Slot {factories.tag()}", start, end)


def schedule(db: Db, company_id: int, employee_id: int, day: date, slot_id: int,
             start: time = time(9, 0), end: time = time(17, 0)) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT sch.schedule (company_id, employee_id, work_date, start_at, end_at, "
                       "time_slot_id, planned_minutes) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, ?, 480)",
                   company_id, employee_id, day, datetime.combine(day, start), datetime.combine(day, end), slot_id)


def leave_type(db: Db, company_id: int, **flags) -> int:
    cols = {"is_active": 1, "allow_back_date": 1, "is_deductible": 1, "gender": "any", "marital_status": "any",
            "tenure": "employment", "balance_basis": "flat", **flags}
    names = ", ".join(cols)
    marks = ", ".join("?" for _ in cols)
    return _scalar(db, f"SET NOCOUNT ON; INSERT lv.leave_type (company_id, title, {names}) OUTPUT INSERTED.id "
                       f"VALUES (?, ?, {marks})", company_id, f"Leave {factories.tag()}", *cols.values())


def allot_leave(db: Db, employee_id: int, leave_type_id: int, days: float) -> None:
    execute(db, "INSERT lv.leave_ledger (employee_id, leave_type_id, fiscal_year, entry_date, days, reason) "
                "VALUES (?, ?, 2026, '2026-01-01', ?, N'allotment')", employee_id, leave_type_id, days)


def employment_type(db: Db, company_id: int) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT org.employment_type (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)",
                   company_id, f"Permanent {factories.tag()}")


def pay_item(db: Db, company_id: int, item_type: str = "deduction") -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT pay.pay_item (company_id, name, item_type, calculation_type, "
                       "tax_distribution) OUTPUT INSERTED.id VALUES (?, ?, ?, N'manual', N'current_month')",
                   company_id, f"Pay item {item_type} {factories.tag()}", item_type)


# Request types the default Employee role does not hold yet (comparison/04-requests.md, "Cross-module
# needs"): tests give them to staff as personal grants, as the role is meant to.
NEW_TYPES = ("expense", "air_ticket", "requisition")


def grant_new_types(db: Db, *user_ids: int) -> None:
    for user_id in user_ids:
        execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope) "
                    "SELECT u.company_id, u.id, p.id, N'grant', N'own' FROM auth.permission p "
                    "JOIN auth.user_account u ON u.id = ? WHERE p.code IN ("
                    + ", ".join(f"N'requests.{t}.{a}'" for t in NEW_TYPES for a in ("view", "create", "cancel"))
                    + ") AND NOT EXISTS (SELECT 1 FROM auth.user_permission_override o WHERE o.user_account_id = u.id "
                    "AND o.company_id = u.company_id AND o.permission_id = p.id)", user_id)


def closed_payslip(db: Db, company_id: int, employee_id: int, month: date) -> None:
    """A closed payroll that paid this person for the month (what pay.fn_month_locked looks for)."""
    payroll_id = _scalar(db, "SET NOCOUNT ON; INSERT pay.payroll (company_id, code, name, kind, payroll_month, status) "
                             "OUTPUT INSERTED.id VALUES (?, ?, ?, N'monthly', ?, N'closed')",
                         company_id, f"PR-{factories.tag()}", f"Payroll {factories.tag()}", month)
    execute(db, "INSERT pay.payslip (company_id, payroll_id, employee_id, payslip_month, status) "
                "VALUES (?, ?, ?, ?, N'released')", company_id, payroll_id, employee_id, month)


def events(db: Db, request_id: int) -> list[str]:
    cur = db.conn.cursor()
    try:
        return [r[0] for r in cur.execute("SELECT event_type FROM core.outbox_event WHERE entity_type = N'req.request' "
                                          "AND entity_id = ? ORDER BY id", request_id).fetchall()]
    finally:
        cur.close()


def notifications(db: Db, user_id: int, request_id: int) -> list[dict]:
    cur = db.conn.cursor()
    try:
        rows = cur.execute("SELECT notification_type, title, link FROM core.notification WHERE user_account_id = ? "
                           "AND entity_type = N'req.request' AND entity_id = ? ORDER BY id", user_id, request_id).fetchall()
        return [{"type": r[0], "title": r[1], "link": r[2]} for r in rows]
    finally:
        cur.close()


class StubProcedure:
    """Replaces a procedure in the test database for the length of a `with` block (an effect hook
    another module owns), then puts the original back, or drops the stub if there was none."""

    def __init__(self, db: Db, name: str, body: str):
        self.db, self.name, self.body = db, name, body
        self.original: str | None = None

    def __enter__(self):
        self.original = _scalar(self.db, "SELECT OBJECT_DEFINITION(OBJECT_ID(?))", self.name)
        execute(self.db, f"CREATE OR ALTER PROCEDURE {self.name} @company_id BIGINT, @actor_user_id BIGINT = NULL, "
                         f"@request_id BIGINT AS BEGIN SET NOCOUNT ON; {self.body} END")
        return self

    def __exit__(self, *exc):
        execute(self.db, f"DROP PROCEDURE {self.name}")
        if self.original:
            execute(self.db, self.original)
        return False


def marks(db: Db, request_id: int, entity_type: str = "test.effect") -> int:
    return _scalar(db, "SELECT COUNT(*) FROM core.audit_log WHERE entity_type = ? AND entity_id = ?",
                   entity_type, request_id)
