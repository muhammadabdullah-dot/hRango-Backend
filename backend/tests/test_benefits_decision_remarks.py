"""Test Run (18-19 Nov 2026) row 12.21: a benefit election keeps the employee's note (remarks) and HR's remarks on
the decision (decisionRemarks) apart, so the employee's own words never show as HR's reason; rejecting needs a
reason."""
from datetime import date, timedelta
from pathlib import Path

from scripts.seed import batches
from tests import factories
from tests import factories_events as fe
from tests import factories_organisation as fo

API = "/api/benefits"
MIGRATION = Path(__file__).resolve().parents[1] / "db" / "migrations" / "0041_ben_election_decision_remarks.sql"


def _d(days: int) -> str:
    return (date.today() + timedelta(days=days)).isoformat()


def _setup(client, db, company, h) -> dict:
    plan = client.post(f"{API}/plans", headers=h, json={
        "category": "dental", "name": f"Dental {factories.tag()}", "planType": "PPO", "carrier": "Carrier",
        "startDate": _d(-30), "endDate": _d(330)}).json()["data"]
    year = client.post(f"{API}/plan-years", headers=h, json={
        "name": f"PY {factories.tag()}", "startDate": _d(-30), "endDate": _d(330), "planIds": [plan["id"]],
        "newHireStart": "immediately", "electionPeriod": 30, "electionUnit": "day"}).json()["data"]
    client.post(f"{API}/enrollment-windows", headers=h, json={
        "planYearId": year["id"], "name": f"Open {factories.tag()}", "effectiveDate": _d(0), "closesOn": _d(20),
        "planIds": [plan["id"]]})
    emp = factories.employee(db, company, first_name="Hira")
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    return {"plan": plan, "year": year, "emp": emp, "sh": staff["headers"]}


def _elect(client, s, note: str) -> dict:
    r = client.post(f"{API}/elections", headers=s["sh"], json={
        "employeeId": s["emp"], "planYearId": s["year"]["id"], "planIds": [s["plan"]["id"]], "remarks": note})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_reject_needs_a_reason_and_keeps_the_note(client, db, company, admin):
    h = admin["headers"]
    s = _setup(client, db, company, h)
    election = _elect(client, s, "Test election: please add the dental plan.")
    assert election["remarks"] == "Test election: please add the dental plan." and election["decisionRemarks"] is None

    for empty in (None, "", "   "):
        refused = client.post(f"{API}/elections/{election['id']}/reject", headers=h,
                              json={"remarks": empty, "rowVersion": election["rowVersion"]})
        assert refused.status_code == 422 and "remarks" in refused.json()["fieldErrors"], refused.text
    rejected = client.post(f"{API}/elections/{election['id']}/reject", headers=h,
                           json={"remarks": "Dental is offered from July only.", "rowVersion": election["rowVersion"]})
    assert rejected.status_code == 200, rejected.text
    data = rejected.json()["data"]
    assert data["status"] == "rejected"
    assert data["decisionRemarks"] == "Dental is offered from July only."
    assert data["remarks"] == "Test election: please add the dental plan."  # still the employee's own note
    mine = client.get(f"{API}/elections/{election['id']}", headers=s["sh"]).json()["data"]
    assert mine["decisionRemarks"] == "Dental is offered from July only."
    told = fe.notifications(db, company, s["emp"], "ben.election", int(election["id"]))
    assert told[-1]["body"] == "Dental is offered from July only."
    event = fe.events(db, company, "benefits.election_decided", int(election["id"]))[-1]["data"]
    assert event["decisionRemarks"] == "Dental is offered from July only." and event["remarks"].startswith("Test election")

    # Choosing again clears HR's old remarks with the old decision.
    again = client.put(f"{API}/elections/{election['id']}", headers=s["sh"], json={
        "employeeId": s["emp"], "planYearId": s["year"]["id"], "planIds": [s["plan"]["id"]],
        "remarks": "Second try.", "rowVersion": data["rowVersion"]})
    assert again.status_code == 200, again.text
    assert again.json()["data"]["status"] == "pending" and again.json()["data"]["decisionRemarks"] is None
    # Approving needs no remarks, and none means none: not the employee's note.
    approved = client.post(f"{API}/elections/{election['id']}/approve", headers=h,
                           json={"rowVersion": again.json()["data"]["rowVersion"]})
    assert approved.status_code == 200, approved.text
    assert approved.json()["data"]["decisionRemarks"] is None and approved.json()["data"]["remarks"] == "Second try."


def test_the_migration_separates_decisions_made_before(client, db, company, admin):
    """0041: HR's remarks of an old decision are the body of the notification the decision sent."""
    h = admin["headers"]
    s = _setup(client, db, company, h)
    election = _elect(client, s, "My own note.")
    approved = client.post(f"{API}/elections/{election['id']}/approve", headers=h,
                           json={"remarks": "Approved from July.", "rowVersion": election["rowVersion"]})
    assert approved.status_code == 200, approved.text
    eid = int(election["id"])
    # As the old procedure left it: HR's remarks over the note, nothing in decision_remarks.
    fo.execute(db, "UPDATE ben.election SET remarks = N'Approved from July.', decision_remarks = NULL WHERE id = ?", eid)
    cur = db.conn.cursor()
    try:
        for batch in batches(MIGRATION.read_text(encoding="utf-8")):
            cur.execute(batch)
    finally:
        cur.close()
    after = client.get(f"{API}/elections/{eid}", headers=h).json()["data"]
    assert after["decisionRemarks"] == "Approved from July." and after["remarks"] is None
