"""Test helpers for organisation, employees, access, dashboard and inbox tests. Plain SQL on
purpose (see tests/factories.py); names carry a random suffix so runs never collide."""
import json
from datetime import date

from app.core.db import Db
from tests.factories import tag


def scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def execute(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def master(db: Db, company_id: int, table: str, name: str | None = None) -> int:
    """A row in org.<table> (division, designation, grade, job_level, employee_group, employment_type)."""
    return scalar(db, f"SET NOCOUNT ON; INSERT org.[{table}] (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)",
                  company_id, name or f"{table} {tag()}")


def job_title(db: Db, company_id: int, max_head_count: int | None = None) -> int:
    return scalar(db, "SET NOCOUNT ON; INSERT org.job_title (company_id, name, limit_head_count, max_head_count) "
                      "OUTPUT INSERTED.id VALUES (?, ?, ?, ?)", company_id, f"Title {tag()}",
                  1 if max_head_count else 0, max_head_count)


def override(db: Db, user_id: int, code: str, effect: str = "grant", scope: str | None = "company") -> None:
    """A grant or denial in the user's home company."""
    execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope) "
                "SELECT u.company_id, u.id, p.id, ?, ? FROM auth.permission p JOIN auth.user_account u ON u.id = ? "
                "WHERE p.code = ?", effect, scope if effect == "grant" else None, user_id, code)


def role_id(db: Db, company_id: int, code: str) -> int:
    return scalar(db, "SELECT id FROM auth.role WHERE company_id = ? AND code = ?", company_id, code)


def request_type(db: Db, code: str) -> int:
    rid = scalar(db, "SELECT id FROM req.request_type WHERE code = ?", code)
    if rid is None:
        rid = scalar(db, "SET NOCOUNT ON; INSERT req.request_type (code, name, kind, is_active) OUTPUT INSERTED.id "
                         "VALUES (?, ?, ?, 1)", code, code.title(), code)
    return rid


def _request(db: Db, company_id: int, employee_id: int, kind: str) -> int:
    return scalar(db, "SET NOCOUNT ON; INSERT req.request (company_id, code, request_type_id, employee_id, status, "
                      "submitted_at) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, N'approved', SYSUTCDATETIME())",
                  company_id, f"RQ-{tag()}", request_type(db, kind), employee_id)


def promotion_request(db: Db, company_id: int, employee_id: int, grade_id: int, job_level_id: int,
                      designation_id: int, job_title_id: int, new_salary: float, effective_date: date,
                      is_demotion: bool = False) -> int:
    rid = _request(db, company_id, employee_id, "promotion")
    execute(db, "INSERT req.req_promotion (request_id, is_demotion, grade_id, job_level_id, designation_id, "
                "job_title_id, new_salary, effective_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            rid, is_demotion, grade_id, job_level_id, designation_id, job_title_id, new_salary, effective_date)
    return rid


def transfer_request(db: Db, company_id: int, employee_id: int, location_id: int, branch_id: int,
                     department_id: int, line_manager_id: int, final_authority_id: int,
                     effective_date: date) -> int:
    rid = _request(db, company_id, employee_id, "transfer")
    execute(db, "INSERT req.req_transfer (request_id, location_id, branch_id, department_id, line_manager_id, "
                "final_authority_id, effective_date) VALUES (?, ?, ?, ?, ?, ?, ?)",
            rid, location_id, branch_id, department_id, line_manager_id, final_authority_id, effective_date)
    return rid


def branch_location(db: Db, branch_id: int) -> int:
    return scalar(db, "SELECT location_id FROM org.branch WHERE id = ?", branch_id)


def timesheet_day(db: Db, company_id: int, employee_id: int, work_date: date, day_status: str) -> None:
    execute(db, "INSERT att.timesheet_day (company_id, employee_id, work_date, day_status) VALUES (?, ?, ?, ?)",
            company_id, employee_id, work_date, day_status)


def employee_fields(db: Db, employee_id: int, *columns: str) -> tuple:
    cur = db.conn.cursor()
    try:
        return tuple(cur.execute(f"SELECT {', '.join(columns)} FROM hr.employee WHERE id = ?", employee_id).fetchone())
    finally:
        cur.close()


# ---------------------------------------------------------------- employee profile tests

def grant(db: Db, user_id: int, *codes: str, scope: str = "own") -> None:
    """Personal grants of several codes with one scope."""
    for code in codes:
        override(db, user_id, code, scope=scope)


def city(db: Db) -> int:
    """Any seeded city (org.city is reference data)."""
    return scalar(db, "SELECT TOP 1 id FROM org.city ORDER BY id")


def events(db: Db, company_id: int, event_type: str, entity_id: int | None = None) -> list[dict]:
    """Payloads of the events of this type published for the company (newest first)."""
    cur = db.conn.cursor()
    try:
        rows = cur.execute("SELECT payload FROM core.outbox_event WHERE company_id = ? AND event_type = ? "
                           "AND (? IS NULL OR entity_id = ?) ORDER BY id DESC",
                           company_id, event_type, entity_id, entity_id).fetchall()
        return [json.loads(r[0]) for r in rows]
    finally:
        cur.close()


def notification_titles(db: Db, user_id: int) -> list[str]:
    cur = db.conn.cursor()
    try:
        return [r[0] for r in cur.execute("SELECT title FROM core.notification WHERE user_account_id = ? ORDER BY id DESC",
                                          user_id).fetchall()]
    finally:
        cur.close()
