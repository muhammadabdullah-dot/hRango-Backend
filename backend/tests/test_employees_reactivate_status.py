"""Test Run (18-19 Nov 2026) row 3.22: Reactivate gives back the status a person had when they were switched off
(on probation, serving notice), not always "active"; people switched off before that was kept get a sensible one."""
from datetime import date, timedelta
from pathlib import Path

from scripts.seed import batches
from tests import factories
from tests import factories_organisation as fo

MIGRATION = Path(__file__).resolve().parents[1] / "db" / "migrations" / "0040_hr_employee_status_before_inactive.sql"


def _employee(db, company, status: str, probation_end: date | None = None, confirmed: date | None = None) -> int:
    emp = factories.employee(db, company)
    fo.execute(db, "UPDATE hr.employee SET status = ? WHERE id = ?", status, emp)
    fo.execute(db, "INSERT hr.employment_period (employee_id, joining_date, probation_end_date, confirmation_date) "
                   "VALUES (?, ?, ?, ?)", emp, date.today() - timedelta(days=60), probation_end, confirmed)
    return emp


def _switch(client, h, emp: int, action: str) -> dict:
    current = client.get(f"/api/employees/{emp}", headers=h).json()["data"]
    r = client.patch(f"/api/employees/{emp}/{action}", headers=h, json={"rowVersion": current["rowVersion"]})
    assert r.status_code == 200, r.text
    return r.json()["data"]


def test_reactivate_restores_the_status_before(client, db, company, admin):
    h = admin["headers"]
    for status in ("probation", "notice", "active"):
        emp = _employee(db, company, status, probation_end=date.today() + timedelta(days=90))
        assert _switch(client, h, emp, "deactivate")["status"] == "inactive"
        assert fo.employee_fields(db, emp, "status_before_inactive") == (status,)
        back = _switch(client, h, emp, "reactivate")
        assert back["status"] == status, status
        assert fo.employee_fields(db, emp, "status_before_inactive") == (None,)
        # The history says what it went back to.
        log = fo.scalar(db, "SELECT TOP 1 new_value FROM core.audit_log WHERE entity_type = N'hr.employee' "
                            "AND entity_id = ? AND action_name = N'reactivate' ORDER BY id DESC", emp)
        assert log == status


def test_people_switched_off_before_get_a_sensible_status(client, db, company, admin):
    """Nothing kept (switched off before 0040): on probation while it has not ended and nobody confirmed them."""
    h = admin["headers"]
    still_on_probation = _employee(db, company, "inactive", probation_end=date.today() + timedelta(days=30))
    probation_over = _employee(db, company, "inactive", probation_end=date.today() - timedelta(days=1))
    confirmed = _employee(db, company, "inactive", probation_end=date.today() + timedelta(days=30),
                          confirmed=date.today() - timedelta(days=5))
    assert _switch(client, h, still_on_probation, "reactivate")["status"] == "probation"
    assert _switch(client, h, probation_over, "reactivate")["status"] == "active"
    assert _switch(client, h, confirmed, "reactivate")["status"] == "active"


def test_the_migration_fills_in_who_was_switched_off_before(client, db, company, admin):
    """0040 takes the status from the switch-off's audit row, or works it out like the procedure does."""
    noticed = _employee(db, company, "inactive")
    fo.execute(db, "INSERT core.audit_log (company_id, entity_type, entity_id, field_name, old_value, new_value, "
                   "action_name, performed_at) VALUES (?, N'hr.employee', ?, N'status', N'notice', N'inactive', "
                   "N'deactivate', SYSUTCDATETIME())", company, noticed)
    probation = _employee(db, company, "inactive", probation_end=date.today() + timedelta(days=30))
    plain = _employee(db, company, "inactive")
    cur = db.conn.cursor()
    try:
        for batch in batches(MIGRATION.read_text(encoding="utf-8")):
            cur.execute(batch)
    finally:
        cur.close()
    assert fo.employee_fields(db, noticed, "status_before_inactive") == ("notice",)
    assert fo.employee_fields(db, probation, "status_before_inactive") == ("probation",)
    assert fo.employee_fields(db, plain, "status_before_inactive") == ("active",)
    assert _switch(client, admin["headers"], noticed, "reactivate")["status"] == "notice"
