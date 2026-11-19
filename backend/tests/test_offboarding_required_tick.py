"""Test Run (18-19 Nov 2026) row 13.37: a required Yes/No (tick box) checklist item holds up an end of employment
until it is ticked; an unticked box is saved as "false", which used to count as answered."""
from datetime import date

from tests import factories
from tests import factories_offboarding as fo


def test_a_required_tick_box_must_be_ticked(client, db):
    company = factories.company(db)
    h = factories.login_as(db, client, company, role_codes="company_admin")["headers"]
    k = client.post("/api/offboarding/settings/checklists", headers=h, json={"name": "Exit", "fields": [
        {"name": "Exit interview held", "fieldType": "boolean", "isRequired": True},
        {"name": "Laptop bag returned", "fieldType": "boolean"}]})
    assert k.status_code == 201, k.text
    held, bag = (f["id"] for f in k.json()["data"]["fields"])

    emp = factories.employee(db, company, first_name="Danish")
    fo.employment_period(db, emp, date(2021, 9, 13))
    r = client.post("/api/offboarding/end-of-employment", headers=h,
                    json={"employeeId": str(emp), "reason": "resignation"})
    assert r.status_code == 201, r.text
    rec = r.json()["data"]
    assert rec["status"] == "pending" and [w["item"] for w in rec["waitingFor"]] == ["checklist"]

    def save(answers: dict) -> dict:
        nonlocal rec
        out = client.put(f"/api/offboarding/end-of-employment/{rec['id']}/checklist", headers=h, json={
            "rowVersion": rec["rowVersion"],
            "answers": [{"checklistFieldId": f, "answer": a} for f, a in answers.items()]})
        assert out.status_code == 200, out.text
        rec = out.json()["data"]
        return rec

    # Both boxes left unticked: saved as false, and the record still waits for the required one.
    save({held: False, bag: False})
    assert {a["answer"] for a in rec["answers"]} == {"false"}
    assert rec["status"] == "pending" and [w["item"] for w in rec["waitingFor"]] == ["checklist"]
    early = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/complete", headers=h,
                         json={"rowVersion": rec["rowVersion"]})
    assert early.status_code == 409 and early.json()["code"] == "END_OF_EMPLOYMENT_WAITING"
    assert "Required checklist answers" in early.json()["message"]

    # The optional box may stay unticked; ticking the required one lets the record complete.
    save({held: True, bag: False})
    assert rec["status"] == "completed" and rec["waitingFor"] == []
    assert fo.employee_status(db, emp) == "left"
