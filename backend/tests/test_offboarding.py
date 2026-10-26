"""End of employment, the off-boarding checklist, completion, rehire and the resignation effect.
Each test uses its own company: active checklists apply to every record in a company."""
from datetime import date, timedelta

import pytest

from tests import factories
from tests import factories_events as fe
from tests import factories_offboarding as fo

TODAY = date.today()


@pytest.fixture()
def shop(db, client) -> dict:
    company_id = factories.company(db)
    admin = factories.login_as(db, client, company_id, role_codes="company_admin")
    return {"company": company_id, "admin": admin, "h": admin["headers"]}


def _eoe(client, h, employee_id: int, **fields):
    body = {"employeeId": str(employee_id), "reason": "termination", **fields}
    return client.post("/api/offboarding/end-of-employment", json=body, headers=h)


def test_checklist_settings(client, shop):
    h = shop["h"]
    body = {"name": "Off Boarding Checklist", "description": "Exit steps", "fields": [
        {"name": "Asset Clear", "fieldType": "date", "isRequired": True},
        {"name": "Notice Days Served", "fieldType": "number", "minValue": 0, "maxValue": 90},
        {"name": "Handover Notes", "fieldType": "string", "minLength": 5, "maxLength": 500, "minValue": 3}]}
    r = client.post("/api/offboarding/settings/checklists", json=body, headers=h)
    assert r.status_code == 201, r.text
    k = r.json()["data"]
    assert k["code"] == "ECL-00001" and [f["name"] for f in k["fields"]] == ["Asset Clear", "Notice Days Served",
                                                                             "Handover Notes"]
    assert k["fields"][2]["minValue"] is None and k["fields"][2]["minLength"] == 5

    bad = client.post("/api/offboarding/settings/checklists", json={"name": "Two", "fields": [
        {"name": "N", "fieldType": "number", "minValue": 10, "maxValue": 1}]}, headers=h)
    assert bad.status_code == 422 and "fields.0.maxValue" in bad.json()["fieldErrors"]
    typ = client.post("/api/offboarding/settings/checklists", json={"name": "Two", "fields": [
        {"name": "N", "fieldType": "colour"}]}, headers=h)
    assert typ.status_code == 422 and "fields.0.fieldType" in typ.json()["fieldErrors"]
    twice = client.post("/api/offboarding/settings/checklists", json={"name": "Two", "fields": [
        {"name": "N", "fieldType": "date"}, {"name": "N", "fieldType": "string"}]}, headers=h)
    assert twice.status_code == 422 and "fields.1.name" in twice.json()["fieldErrors"]
    dup = client.post("/api/offboarding/settings/checklists", json={"name": "Off Boarding Checklist"}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "CHECKLIST_DUPLICATE"

    keep = k["fields"][0]
    edited = client.put(f"/api/offboarding/settings/checklists/{k['id']}", json={
        "name": k["name"], "rowVersion": k["rowVersion"],
        "fields": [{"id": keep["id"], "name": "Assets Cleared On", "fieldType": "date", "isRequired": True},
                   {"name": "Exit Interview Done", "fieldType": "boolean"}]}, headers=h)
    assert edited.status_code == 200, edited.text
    fields = edited.json()["data"]["fields"]
    assert [f["name"] for f in fields] == ["Assets Cleared On", "Exit Interview Done"] and fields[0]["id"] == keep["id"]
    assert client.put(f"/api/offboarding/settings/checklists/{k['id']}", json={"name": "x", "rowVersion": k["rowVersion"]},
                      headers=h).status_code == 409

    active = client.get("/api/offboarding/end-of-employment/checklist-fields", headers=h).json()["data"]
    assert {f["name"] for f in active} == {"Assets Cleared On", "Exit Interview Done"}
    assert client.get("/api/offboarding/settings/checklists", params={"q": "ECL"}, headers=h).json()["meta"]["total"] == 1
    assert client.delete(f"/api/offboarding/settings/checklists/{k['id']}",
                         params={"rowVersion": edited.json()["data"]["rowVersion"]}, headers=h).status_code == 204


def test_end_of_employment_to_completion_and_rehire(client, db, shop):
    h, company = shop["h"], shop["company"]
    k = client.post("/api/offboarding/settings/checklists", json={"name": "Exit", "fields": [
        {"name": "Notice Days Served", "fieldType": "number", "isRequired": True, "minValue": 0, "maxValue": 90},
        {"name": "Exit Interview Done", "fieldType": "boolean"}]}, headers=h).json()["data"]
    days_field, interview_field = k["fields"][0]["id"], k["fields"][1]["id"]

    emp = factories.employee(db, company, first_name="Talha")
    fo.employment_period(db, emp, date(2020, 3, 1))
    asset = fo.asset(client, h)
    al = fo.allocate(client, h, asset["id"], emp)

    delegatee = factories.employee(db, company, first_name="Dua")
    factories.user(db, company, employee_id=delegatee, role_codes="employee")
    letter = factories.upload(client, h, name="Resignation letter.pdf", module="offboarding")

    missing = _eoe(client, h, emp, serveNotice=True)
    assert missing.status_code == 422 and "lastWorkingDate" in missing.json()["fieldErrors"]
    unknown = _eoe(client, h, emp, fileId=999999999)
    assert unknown.status_code == 422 and "fileId" in unknown.json()["fieldErrors"]
    r = _eoe(client, h, emp, reason="resignation", serveNotice=True, noticePeriodDays=30,
             lastWorkingDate=TODAY.isoformat(), needsFinalSettlement=True, needsAssetClearance=True,
             delegateeId=str(delegatee), fileId=int(letter["id"]))
    assert r.status_code == 201, r.text
    rec = r.json()["data"]
    assert rec["file"]["id"] == letter["id"] and rec["file"]["name"] == "Resignation letter.pdf"
    assert client.get(rec["file"]["url"]).content == factories.PDF_BYTES
    started = fe.events(db, company, "offboarding.started", int(rec["id"]))
    assert len(started) == 1 and started[0]["data"]["employeeId"] == str(emp)
    assert started[0]["data"]["reason"] == "resignation" and started[0]["data"]["delegateeId"] == str(delegatee)
    told = fe.notifications(db, company, delegatee, "sep.end_of_employment", int(rec["id"]))
    assert len(told) == 1 and told[0]["title"].startswith("You will take over the work of Talha")
    assert rec["status"] == "pending" and rec["finalSettlementStatus"] == "pending"
    assert rec["joiningDate"] == "2020-03-01" and rec["employeeName"].startswith("Talha")
    assert {w["item"] for w in rec["waitingFor"]} == {"final_settlement", "asset_clearance", "assets", "checklist"}

    again = _eoe(client, h, emp)
    assert again.status_code == 409 and again.json()["code"] == "END_OF_EMPLOYMENT_OPEN"

    early = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/complete",
                         json={"rowVersion": rec["rowVersion"]}, headers=h)
    assert early.status_code == 409 and early.json()["code"] == "END_OF_EMPLOYMENT_WAITING"
    assert "Assets still allocated" in early.json()["message"]

    wrong = client.put(f"/api/offboarding/end-of-employment/{rec['id']}/checklist", json={
        "rowVersion": rec["rowVersion"], "answers": [{"checklistFieldId": days_field, "answer": 120}]}, headers=h)
    assert wrong.status_code == 422 and f"answers.{days_field}" in wrong.json()["fieldErrors"]
    notbool = client.put(f"/api/offboarding/end-of-employment/{rec['id']}/checklist", json={
        "rowVersion": rec["rowVersion"], "answers": [{"checklistFieldId": interview_field, "answer": "maybe"}]}, headers=h)
    assert notbool.status_code == 422
    r = client.put(f"/api/offboarding/end-of-employment/{rec['id']}/checklist", json={
        "rowVersion": rec["rowVersion"], "answers": [{"checklistFieldId": days_field, "answer": 30},
                                                     {"checklistFieldId": interview_field, "answer": True}]}, headers=h)
    assert r.status_code == 200, r.text
    rec = r.json()["data"]
    assert {a["answer"] for a in rec["answers"]} == {"30", "true"}
    assert "checklist" not in {w["item"] for w in rec["waitingFor"]}

    # The clearance form links itself to the pending record; approving it returns the asset.
    form = client.post("/api/assets/clearance-forms", json={
        "employeeId": str(emp), "clearanceDate": TODAY.isoformat(),
        "items": [{"assetAllocationId": al["id"], "conditionAtClearance": "good", "returnStatus": "complete"}]},
        headers=h).json()["data"]
    assert form["endOfEmploymentId"] == rec["id"]
    client.patch("/api/assets/clearance-forms/approve",
                 json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]}, headers=h)
    rec = client.get(f"/api/offboarding/end-of-employment/{rec['id']}", headers=h).json()["data"]
    assert rec["clearanceStatus"] == "approved" and [w["item"] for w in rec["waitingFor"]] == ["final_settlement"]
    assert fo.employee_status(db, emp) != "left"

    fo.close_final_settlement(db, int(rec["id"]))
    done = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/complete",
                        json={"rowVersion": rec["rowVersion"]}, headers=h)
    assert done.status_code == 200, done.text
    rec = done.json()["data"]
    assert rec["status"] == "completed" and rec["completedAt"] and rec["waitingFor"] == []
    assert fo.employee_status(db, emp) == "left"
    completed = fe.events(db, company, "offboarding.completed", int(rec["id"]))
    assert len(completed) == 1 and completed[0]["data"]["status"] == "completed"
    left = fe.events(db, company, "employees.deactivated", emp)
    assert len(left) == 1 and left[0]["data"]["change"] == "left" and left[0]["data"]["status"] == "left"
    cur = db.conn.cursor()
    end_date, eoe_id = cur.execute("SELECT end_date, end_of_employment_id FROM hr.employment_period WHERE employee_id = ?",
                                   emp).fetchone()
    cur.close()
    assert end_date == TODAY and eoe_id == int(rec["id"])

    locked = client.put(f"/api/offboarding/end-of-employment/{rec['id']}", json={
        "employeeId": str(emp), "reason": "other", "rowVersion": rec["rowVersion"]}, headers=h)
    assert locked.status_code == 409 and locked.json()["code"] == "END_OF_EMPLOYMENT_COMPLETED"
    assert client.get("/api/offboarding/end-of-employment", params={"status": "completed"},
                      headers=h).json()["meta"]["total"] == 1

    too_soon = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/rehire",
                            json={"joiningDate": TODAY.isoformat(), "rowVersion": rec["rowVersion"]}, headers=h)
    assert too_soon.status_code == 422 and "joiningDate" in too_soon.json()["fieldErrors"]
    back = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/rehire",
                        json={"joiningDate": (TODAY + timedelta(days=10)).isoformat(),
                              "rowVersion": rec["rowVersion"]}, headers=h)
    assert back.status_code == 200, back.text
    assert back.json()["data"]["isRehired"] is True
    assert fo.employee_status(db, emp) == "active"
    assert len(fe.events(db, company, "offboarding.rehired", int(rec["id"]))) == 1
    back_on = fe.events(db, company, "employees.reactivated", emp)
    assert len(back_on) == 1 and back_on[0]["data"]["change"] == "rehire"
    twice = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/rehire",
                         json={"joiningDate": (TODAY + timedelta(days=20)).isoformat(),
                               "rowVersion": back.json()["data"]["rowVersion"]}, headers=h)
    assert twice.status_code == 409


def test_simple_record_completes_on_save_and_edits(client, db, shop):
    h, company = shop["h"], shop["company"]
    emp = factories.employee(db, company)
    # Nothing ticked, no notice: the employee leaves the day the record is made.
    done = _eoe(client, h, emp).json()["data"]
    assert done["status"] == "completed" and done["lastWorkingDate"] == TODAY.isoformat()
    assert fo.employee_status(db, emp) == "left"
    assert _eoe(client, h, emp).json()["code"] == "EMPLOYEE_LEFT"

    later = factories.employee(db, company)
    rec = _eoe(client, h, later, serveNotice=True, lastWorkingDate=(TODAY + timedelta(days=30)).isoformat(),
               needsFinalSettlement=True).json()["data"]
    assert rec["status"] == "pending" and {w["item"] for w in rec["waitingFor"]} == {"final_settlement",
                                                                                     "last_working_date"}
    edited = client.put(f"/api/offboarding/end-of-employment/{rec['id']}", json={
        "employeeId": str(later), "reason": "retirement", "serveNotice": True,
        "lastWorkingDate": (TODAY + timedelta(days=30)).isoformat(), "rowVersion": rec["rowVersion"]}, headers=h)
    assert edited.status_code == 200, edited.text
    assert edited.json()["data"]["finalSettlementId"] is None and edited.json()["data"]["reason"] == "retirement"
    stale = client.put(f"/api/offboarding/end-of-employment/{rec['id']}", json={
        "employeeId": str(later), "reason": "other", "rowVersion": rec["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    assert client.get("/api/offboarding/end-of-employment", params={"status": "pending"},
                      headers=h).json()["meta"]["total"] == 1
    assert client.delete(f"/api/offboarding/end-of-employment/{rec['id']}",
                         params={"rowVersion": edited.json()["data"]["rowVersion"]}, headers=h).status_code == 204
    assert client.delete(f"/api/offboarding/end-of-employment/{done['id']}", params={"rowVersion": done["rowVersion"]},
                         headers=h).status_code == 409


def test_unreturned_assets_keep_it_pending(client, db, shop):
    h, company = shop["h"], shop["company"]
    emp = factories.employee(db, company)
    fo.allocate(client, h, fo.asset(client, h)["id"], emp)
    rec = _eoe(client, h, emp, needsAssetClearance=True).json()["data"]
    # An approved clearance that leaves an asset out does not finish it.
    form = client.post("/api/assets/clearance-forms", json={"employeeId": str(emp), "clearanceDate": TODAY.isoformat()},
                       headers=h).json()["data"]
    client.patch("/api/assets/clearance-forms/approve",
                 json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]}, headers=h)
    rec = client.get(f"/api/offboarding/end-of-employment/{rec['id']}", headers=h).json()["data"]
    assert rec["status"] == "pending" and [w["item"] for w in rec["waitingFor"]] == ["assets"]
    r = client.patch(f"/api/offboarding/end-of-employment/{rec['id']}/complete", json={"rowVersion": rec["rowVersion"]},
                     headers=h)
    assert r.status_code == 409 and r.json()["code"] == "END_OF_EMPLOYMENT_WAITING"
    assert fo.employee_status(db, emp) == "active"


def test_permissions_and_scope(client, db, shop):
    h, company = shop["h"], shop["company"]
    manager = factories.employee(db, company)
    report = factories.employee(db, company, line_manager_id=manager)
    stranger = factories.employee(db, company)
    mine = _eoe(client, h, report, serveNotice=True,
                lastWorkingDate=(TODAY + timedelta(days=30)).isoformat()).json()["data"]
    theirs = _eoe(client, h, stranger, serveNotice=True,
                  lastWorkingDate=(TODAY + timedelta(days=30)).isoformat()).json()["data"]

    boss = factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)
    team = client.get("/api/offboarding/end-of-employment", headers=boss["headers"]).json()
    assert [x["id"] for x in team["data"]] == [mine["id"]]
    assert client.get(f"/api/offboarding/end-of-employment/{theirs['id']}", headers=boss["headers"]).status_code == 404
    assert _eoe(client, boss["headers"], report).status_code == 403

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=report)
    sh = staff["headers"]
    assert [x["id"] for x in client.get("/api/offboarding/end-of-employment", headers=sh).json()["data"]] == [mine["id"]]
    assert _eoe(client, sh, stranger).status_code == 403    # staff leave through a resignation request
    assert client.get("/api/offboarding/settings/checklists", headers=sh).status_code == 403
    assert client.patch(f"/api/offboarding/end-of-employment/{mine['id']}/rehire",
                        json={"joiningDate": "2030-01-01", "rowVersion": mine["rowVersion"]}, headers=sh).status_code == 403

    officer = factories.login_as(db, client, company, role_codes="hr_officer", employee_id=stranger)
    own = client.put(f"/api/offboarding/end-of-employment/{theirs['id']}", json={
        "employeeId": str(stranger), "reason": "other", "rowVersion": theirs["rowVersion"]}, headers=officer["headers"])
    assert own.status_code == 403

    other_admin = factories.login_as(db, client, factories.company(db), role_codes="company_admin")
    assert client.get(f"/api/offboarding/end-of-employment/{mine['id']}",
                      headers=other_admin["headers"]).status_code == 404


def test_resignation_effect(client, db, shop):
    h, company, actor = shop["h"], shop["company"], shop["admin"]["user_id"]
    emp = factories.employee(db, company)
    rd = TODAY - timedelta(days=5)
    req = fo.resignation_request(db, company, emp, rd, notice_period_days=30, serve_notice=True, reason="Further study")
    fo.apply_resignation(db, company, actor, req)
    fo.apply_resignation(db, company, actor, req)   # applying twice changes nothing

    rows = client.get("/api/offboarding/end-of-employment", params={"employeeId": str(emp)}, headers=h).json()
    assert rows["meta"]["total"] == 1
    rec = client.get(f"/api/offboarding/end-of-employment/{rows['data'][0]['id']}", headers=h).json()["data"]
    assert rec["reason"] == "resignation" and rec["resignationRequestId"] == str(req)
    assert rec["lastWorkingDate"] == (rd + timedelta(days=30)).isoformat() and rec["noticePeriodDays"] == 30
    assert rec["needsFinalSettlement"] and rec["needsAssetClearance"] and rec["finalSettlementStatus"] == "pending"
    assert rec["description"] == "Further study" and rec["status"] == "pending"
    started = fe.events(db, company, "offboarding.started", int(rec["id"]))
    assert len(started) == 1 and started[0]["data"]["resignationRequestId"] == str(req)

    # A cancelled resignation removes the untouched record.
    fo.revert_resignation(db, company, actor, req)
    assert client.get(f"/api/offboarding/end-of-employment/{rec['id']}", headers=h).status_code == 404

    # When HR has already started one, the approved resignation is linked to it.
    started = _eoe(client, h, emp, serveNotice=True, lastWorkingDate=(TODAY + timedelta(days=9)).isoformat()).json()["data"]
    req2 = fo.resignation_request(db, company, emp, TODAY, last_working_date=TODAY + timedelta(days=9))
    fo.apply_resignation(db, company, actor, req2)
    linked = client.get(f"/api/offboarding/end-of-employment/{started['id']}", headers=h).json()["data"]
    assert linked["resignationRequestId"] == str(req2) and linked["reason"] == "termination"

    # A third resignation while one is linked blocks that approval.
    req3 = fo.resignation_request(db, company, emp, TODAY)
    with pytest.raises(Exception) as err:
        fo.apply_resignation(db, company, actor, req3)
    assert getattr(err.value, "status", None) == 409
