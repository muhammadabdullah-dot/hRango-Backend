"""Test helpers for the Leaves and Warning modules. Records other modules own (leave requests in req.*,
time-sheet days in att.*, employment periods in hr.*) are written with plain SQL, filling only the
columns the table has, so a column another module adds does not break these tests."""
from datetime import date, datetime
from typing import Any

from app.core.db import Db
from tests import factories


def _columns(db: Db, table: str) -> set[str]:
    cur = db.conn.cursor()
    try:
        return {r[0] for r in cur.execute("SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(?)", table)}
    finally:
        cur.close()


def insert(db: Db, table: str, values: dict[str, Any]) -> int | None:
    """INSERT the values whose columns exist; returns the new id when the table has one."""
    cols = _columns(db, table)
    pairs = [(k, v) for k, v in values.items() if k in cols]
    names = ", ".join(f"[{k}]" for k, _ in pairs)
    marks = ", ".join("?" for _ in pairs)
    output = "OUTPUT INSERTED.id " if "id" in cols else ""
    cur = db.conn.cursor()
    try:
        cur.execute(f"SET NOCOUNT ON; INSERT {table} ({names}) {output}VALUES ({marks})", *[v for _, v in pairs])
        return cur.fetchval() if output else None
    finally:
        cur.close()


def execute(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def rows(db: Db, sql: str, *params) -> list[dict[str, Any]]:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]
    finally:
        cur.close()


def employee(db: Db, company_id: int, joined: date | None = date(2020, 1, 1), gender: str | None = None,
             status: str = "active", **kw) -> int:
    emp = factories.employee(db, company_id, **kw)
    if gender or status != "active":
        execute(db, "UPDATE hr.employee SET gender = ISNULL(?, gender), status = ? WHERE id = ?", gender, status, emp)
    if joined:
        insert(db, "hr.employment_period", {"employee_id": emp, "joining_date": joined})
    return emp


def leave_request_type(db: Db) -> int:
    rt = scalar(db, "SELECT id FROM req.request_type WHERE code = N'leave'")
    if rt is None:
        rt = insert(db, "req.request_type", {"code": "leave", "name": "Leave", "kind": "leave", "prefix": "LV",
                                              "is_active": True, "sort_order": 10})
    return rt


def leave_request(db: Db, company_id: int, employee_id: int, leave_type_id: int, from_date: date, to_date: date,
                  days: float, status: str = "pending") -> int:
    request_id = insert(db, "req.request", {
        "company_id": company_id, "code": f"RQ-LV-{factories.tag()}", "request_type_id": leave_request_type(db),
        "employee_id": employee_id, "from_date": from_date, "to_date": to_date, "days": days, "reason": "Test leave",
        "status": status, "submitted_at": datetime(2030, 1, 1), "is_deleted": False})
    insert(db, "req.req_leave", {"request_id": request_id, "leave_type_id": leave_type_id, "is_short": False,
                                 "days": days})
    return request_id


def timesheet_day(db: Db, company_id: int, employee_id: int, work_date: date, day_status: str = "present",
                  **minutes: int) -> int:
    return insert(db, "att.timesheet_day", {"company_id": company_id, "employee_id": employee_id,
                                            "work_date": work_date, "day_status": day_status,
                                            "processed_at": datetime(2030, 1, 1), **minutes})


def balance(db: Db, company_id: int, employee_id: int, leave_type_id: int, as_of: date) -> dict[str, float]:
    found = rows(db, "SELECT entitled, used, pending, available FROM lv.fn_leave_balance(?, ?, ?, ?)",
                 company_id, employee_id, leave_type_id, as_of)
    return {k: float(v) for k, v in found[0].items()}


LEAVE_TYPE = {"title": "Annual", "shortCode": "AN", "allowance": 10, "isActive": True, "autoAllotment": True,
              "isDeductible": True}


def leave_type(client, headers: dict, **overrides) -> dict:
    t = factories.tag()
    body = {**LEAVE_TYPE, "title": f"Leave {t}", "shortCode": t[:6].upper(), **overrides}
    r = client.post("/api/leaves/types", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def company_policy(client, headers: dict, type_ids: list[str], allowances: list[float | None] | None = None) -> dict:
    allowances = allowances or [None] * len(type_ids)
    r = client.post("/api/leaves/policies", headers=headers, json={
        "title": f"Policy {factories.tag()}", "policyKind": "distribution", "policyLevel": "company",
        "types": [{"leaveTypeId": i, "allowance": a} for i, a in zip(type_ids, allowances)]})
    assert r.status_code == 201, r.text
    return r.json()["data"]
