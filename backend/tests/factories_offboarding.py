"""Helpers for the assets and off-boarding tests. Assets are made through this module's own
endpoints; records owned by other modules (employment periods, resignation requests, a closed final
settlement, which payroll does) are written with plain SQL, as tests/factories.py does."""
from datetime import date

from app.core.db import Db
from tests import factories


def _scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def _exec(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def asset_type(client, headers: dict, name: str | None = None) -> dict:
    r = client.post("/api/assets/types", json={"name": name or f"Type {factories.tag()}"}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def asset(client, headers: dict, type_id: str | None = None, **fields) -> dict:
    type_id = type_id or asset_type(client, headers)["id"]
    body = {"name": f"Laptop {factories.tag()}", "assetTypeId": type_id, "assetCondition": "new",
            "identificationNo": f"SN-{factories.tag()}", "currentValue": 150000, "acquiredDate": "2024-01-15", **fields}
    r = client.post("/api/assets/company-assets", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def allocate(client, headers: dict, asset_id: str, employee_id: int, on: str = "2024-02-01", **fields) -> dict:
    r = client.post("/api/assets/allocations", json={"assetId": asset_id, "employeeId": str(employee_id),
                                                     "allocatedOn": on, **fields}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def employment_period(db: Db, employee_id: int, joining_date: date) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT hr.employment_period (employee_id, joining_date) OUTPUT INSERTED.id "
                       "VALUES (?, ?)", employee_id, joining_date)


def employee_status(db: Db, employee_id: int) -> str:
    return _scalar(db, "SELECT status FROM hr.employee WHERE id = ?", employee_id)


def close_final_settlement(db: Db, end_of_employment_id: int) -> None:
    """What payroll's Close FS does: close the settlement, then let the record complete."""
    _exec(db, "UPDATE sep.final_settlement SET status = N'closed', closed_at = SYSUTCDATETIME() "
              "WHERE end_of_employment_id = ?", end_of_employment_id)


def resignation_request(db: Db, company_id: int, employee_id: int, resignation_date: date,
                        last_working_date: date | None = None, notice_period_days: int | None = None,
                        serve_notice: bool = False, reason: str = "Moving abroad") -> int:
    """An approved resignation request as the requests module stores it (req.request + req.req_resignation)."""
    type_id = _scalar(db, "SELECT id FROM req.request_type WHERE code = N'resignation'")
    if type_id is None:
        type_id = _scalar(db, "SET NOCOUNT ON; INSERT req.request_type (code, name, kind, is_active) OUTPUT INSERTED.id "
                              "VALUES (N'resignation', N'Resignation', N'resignation', 1)")
    request_id = _scalar(db, "SET NOCOUNT ON; INSERT req.request (company_id, code, request_type_id, employee_id, "
                             "from_date, reason, status) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, ?, N'approved')",
                         company_id, f"RSG-{factories.tag()}", type_id, employee_id, resignation_date, reason)
    _exec(db, "INSERT req.req_resignation (request_id, resignation_type, resignation_date, last_working_date, "
              "notice_period_days, serve_notice) VALUES (?, N'voluntary', ?, ?, ?, ?)",
          request_id, resignation_date, last_working_date, notice_period_days, serve_notice)
    return request_id


def apply_resignation(db: Db, company_id: int, actor_user_id: int, request_id: int) -> None:
    db.call("sep.usp_request_apply_resignation", company_id=company_id, actor_user_id=actor_user_id,
            request_id=request_id)


def revert_resignation(db: Db, company_id: int, actor_user_id: int, request_id: int) -> None:
    db.call("sep.usp_request_revert_resignation", company_id=company_id, actor_user_id=actor_user_id,
            request_id=request_id)
