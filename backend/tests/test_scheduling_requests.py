"""Effects the requests engine runs when a rest-day or shift request is finally approved, and their
reversal on cancellation. The request rows are written with plain SQL: the request screens belong to
the requests module."""
import pytest

from app.core.errors import AppError
from tests import factories
from tests import factories_scheduling as fs


def _request(db, company_id: int, kind: str, employee_id: int, from_date=None, to_date=None) -> int:
    type_id = fs.scalar(db, "SELECT id FROM req.request_type WHERE code = ?", kind)
    if type_id is None:
        pytest.skip(f"request type {kind} is not seeded")
    return fs.scalar(db, "SET NOCOUNT ON; INSERT req.request (company_id, code, request_type_id, employee_id, status, "
                         "from_date, to_date) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, N'approved', ?, ?)",
                     company_id, f"RQ-T-{factories.tag()}", type_id, employee_id, from_date, to_date)


def _exec(db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def test_rest_day_request_apply_and_revert(db, company, admin):
    slot = fs.time_slot(db, company)
    group = fs.roster_group(db, company, {1: slot})
    dept = factories.department(db, company)
    emp = factories.employee(db, company, department_id=dept)
    req = _request(db, company, "rest_day", emp, fs.day(0), fs.day(6))
    _exec(db, "INSERT req.req_rest_day (request_id, department_id, roster_group_id, is_payable) VALUES (?, ?, ?, 1)",
          req, dept, group)
    for d in (fs.day(1), fs.day(3)):
        _exec(db, "INSERT req.request_day (request_id, request_date) VALUES (?, ?)", req, d)

    db.call("sch.usp_request_apply_rest_day", company_id=company, actor_user_id=admin["user_id"], request_id=req)
    rows = db.conn.cursor().execute("SELECT rest_date, is_payable FROM sch.rest_day WHERE request_id = ? "
                                    "ORDER BY rest_date", req).fetchall()
    assert [(str(r.rest_date), r.is_payable) for r in rows] == [(str(fs.day(1)), True), (str(fs.day(3)), True)]

    db.call("sch.usp_request_revert_rest_day", company_id=company, actor_user_id=admin["user_id"], request_id=req)
    assert fs.scalar(db, "SELECT COUNT(*) FROM sch.rest_day WHERE employee_id = ?", emp) == 0

    other = factories.company(db)
    with pytest.raises(AppError) as e:
        db.call("sch.usp_request_apply_rest_day", company_id=other, actor_user_id=None, request_id=req)
    assert e.value.status == 404


def test_shift_swap_request_apply_and_revert(client, db, company, admin):
    h = admin["headers"]
    slot = fs.time_slot(db, company, "09:00", "17:00")
    late = fs.time_slot(db, company, "14:00", "22:00")
    a, b = factories.employee(db, company), factories.employee(db, company)
    mine = client.post("/api/scheduling/schedules", json={"employeeId": a, "workDate": str(fs.day(0)),
                                                         "timeSlotId": slot}, headers=h).json()["data"]
    theirs = client.post("/api/scheduling/schedules", json={"employeeId": b, "workDate": str(fs.day(0)),
                                                           "timeSlotId": late}, headers=h).json()["data"]
    req = _request(db, company, "shift_swap", a, fs.day(0), fs.day(0))
    _exec(db, "INSERT req.req_shift_swap (request_id, shift_date, from_schedule_id, time_slot_id, with_employee_id, "
              "to_schedule_id) VALUES (?, ?, ?, ?, ?, ?)", req, fs.day(0), int(mine["id"]), late, b, int(theirs["id"]))

    db.call("sch.usp_request_apply_shift_swap", company_id=company, actor_user_id=admin["user_id"], request_id=req)
    owner = lambda sid: fs.scalar(db, "SELECT employee_id FROM sch.schedule WHERE id = ?", int(sid))  # noqa: E731
    assert owner(mine["id"]) == b and owner(theirs["id"]) == a

    # Applying again finds the shifts moved: refused, so the approval would roll back.
    with pytest.raises(AppError) as e:
        db.call("sch.usp_request_apply_shift_swap", company_id=company, actor_user_id=admin["user_id"], request_id=req)
    assert e.value.status == 409

    db.call("sch.usp_request_revert_shift_swap", company_id=company, actor_user_id=admin["user_id"], request_id=req)
    assert owner(mine["id"]) == a and owner(theirs["id"]) == b
