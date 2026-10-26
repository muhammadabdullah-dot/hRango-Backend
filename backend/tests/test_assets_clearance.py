"""Asset Clearance Form: prefill, one open form per leaver, bulk approve and unapprove, self rule."""
import pytest

from app.core.errors import AppError
from tests import factories
from tests import factories_events as fe
from tests import factories_offboarding as fo


def _item(allocation: dict, condition: str = "good", status: str = "complete") -> dict:
    return {"assetAllocationId": allocation["id"], "conditionAtClearance": condition, "returnStatus": status,
            "reason": "Leaving", "comments": None}


def test_clearance_flow(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company, first_name="Bilal")
    a1, a2 = fo.asset(client, h), fo.asset(client, h)
    al1 = fo.allocate(client, h, a1["id"], emp, on="2024-02-01")
    al2 = fo.allocate(client, h, a2["id"], emp, on="2024-03-01")

    pre = client.get("/api/assets/clearance-forms/prefill", params={"employeeId": str(emp)}, headers=h)
    assert pre.status_code == 200, pre.text
    assert {i["assetAllocationId"] for i in pre.json()["data"]["items"]} == {al1["id"], al2["id"]}

    bad = client.post("/api/assets/clearance-forms", json={
        "employeeId": str(emp), "clearanceDate": "2024-12-31",
        "items": [_item(al1), {**_item(al2), "conditionAtClearance": "shiny"}]}, headers=h)
    assert bad.status_code == 422 and "items.1.conditionAtClearance" in bad.json()["fieldErrors"]
    foreign = fo.allocate(client, h, fo.asset(client, h)["id"], factories.employee(db, company))
    wrong = client.post("/api/assets/clearance-forms", json={
        "employeeId": str(emp), "clearanceDate": "2024-12-31", "items": [_item(foreign)]}, headers=h)
    assert wrong.status_code == 422 and "items.0.assetAllocationId" in wrong.json()["fieldErrors"]

    r = client.post("/api/assets/clearance-forms", json={
        "employeeId": str(emp), "clearanceDate": "2024-12-31", "items": [_item(al1, "damaged")]}, headers=h)
    assert r.status_code == 201, r.text
    form = r.json()["data"]
    assert form["status"] == "in_progress" and form["itemCount"] == 1 and form["employeeName"].startswith("Bilal")

    second = client.post("/api/assets/clearance-forms", json={"employeeId": str(emp), "clearanceDate": "2024-12-31"},
                         headers=h)
    assert second.status_code == 409 and second.json()["code"] == "CLEARANCE_OPEN"

    signed = factories.upload(client, h, name="Clearance signed.pdf", module="assets")
    r = client.put(f"/api/assets/clearance-forms/{form['id']}", json={
        "employeeId": str(emp), "clearanceDate": "2024-12-31", "rowVersion": form["rowVersion"],
        "fileId": int(signed["id"]), "items": [_item(al1, "damaged"), _item(al2, "good", "not_returned")]}, headers=h)
    assert r.status_code == 200, r.text
    form2 = r.json()["data"]
    assert len(form2["items"]) == 2
    assert form2["file"]["name"] == "Clearance signed.pdf" and client.get(form2["file"]["url"]).status_code == 200
    stale = client.patch("/api/assets/clearance-forms/approve",
                         json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]}, headers=h)
    assert stale.status_code == 409

    ok = client.patch("/api/assets/clearance-forms/approve",
                      json={"forms": [{"id": form["id"], "rowVersion": form2["rowVersion"]}]}, headers=h)
    assert ok.status_code == 200, ok.text
    approved = ok.json()["data"][0]
    assert approved["status"] == "approved" and approved["approvalDate"] is not None
    published = fe.events(db, company, "assets.clearance_approved", int(form["id"]))
    assert len(published) == 1 and published[0]["data"]["employeeId"] == str(emp)
    items = {(i["assetCode"], i["returnStatus"]) for i in published[0]["data"]["items"]}
    assert items == {(a1["code"], "complete"), (a2["code"], "not_returned")}
    assert client.get(f"/api/assets/company-assets/{a1['id']}", headers=h).json()["data"]["status"] == "damaged"
    assert client.get(f"/api/assets/company-assets/{a2['id']}", headers=h).json()["data"]["status"] == "lost"
    closed = client.get(f"/api/assets/allocations/{al1['id']}", headers=h).json()["data"]
    assert closed["deallocatedOn"] == "2024-12-31" and closed["assetClearanceId"] == form["id"]

    locked = client.put(f"/api/assets/clearance-forms/{form['id']}", json={
        "employeeId": str(emp), "clearanceDate": "2024-12-31", "rowVersion": approved["rowVersion"]}, headers=h)
    assert locked.status_code == 409 and locked.json()["code"] == "CLEARANCE_APPROVED"
    assert client.delete(f"/api/assets/clearance-forms/{form['id']}", params={"rowVersion": approved["rowVersion"]},
                         headers=h).status_code == 409

    back = client.patch("/api/assets/clearance-forms/unapprove",
                        json={"forms": [{"id": form["id"], "rowVersion": approved["rowVersion"]}]}, headers=h)
    assert back.status_code == 200, back.text
    assert back.json()["data"][0]["status"] == "in_progress"
    reopened = client.get(f"/api/assets/company-assets/{a2['id']}", headers=h).json()["data"]
    assert reopened["status"] == "active" and reopened["holderId"] == str(emp)

    listed = client.get("/api/assets/clearance-forms", params={"employeeId": str(emp)}, headers=h).json()
    assert listed["meta"]["total"] == 1
    assert client.delete(f"/api/assets/clearance-forms/{form['id']}",
                         params={"rowVersion": back.json()["data"][0]["rowVersion"]}, headers=h).status_code == 204


def test_unapprove_refused_after_reallocation(client, db, company, admin):
    h = admin["headers"]
    emp, nxt = factories.employee(db, company), factories.employee(db, company)
    a = fo.asset(client, h)
    al = fo.allocate(client, h, a["id"], emp)
    form = client.post("/api/assets/clearance-forms", json={"employeeId": str(emp), "clearanceDate": "2024-06-30",
                                                            "items": [_item(al)]}, headers=h).json()["data"]
    approved = client.patch("/api/assets/clearance-forms/approve",
                            json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]},
                            headers=h).json()["data"][0]
    fo.allocate(client, h, a["id"], nxt, on="2024-07-01")
    r = client.patch("/api/assets/clearance-forms/unapprove",
                     json={"forms": [{"id": form["id"], "rowVersion": approved["rowVersion"]}]}, headers=h)
    assert r.status_code == 409


def test_unapprove_ignores_an_earlier_allocation_on_the_same_day(client, db, company, admin):
    """Only allocations made after the one the form closed block unapprove, not an earlier one on the same date."""
    h = admin["headers"]
    prev, emp = factories.employee(db, company), factories.employee(db, company)
    a = fo.asset(client, h)
    first = fo.allocate(client, h, a["id"], prev, on="2024-03-04")
    back = client.patch(f"/api/assets/allocations/{first['id']}/deallocate",
                        json={"deallocatedOn": "2024-03-04", "rowVersion": first["rowVersion"]}, headers=h)
    assert back.status_code == 200, back.text
    al = fo.allocate(client, h, a["id"], emp, on="2024-03-04")
    form = client.post("/api/assets/clearance-forms", json={"employeeId": str(emp), "clearanceDate": "2024-06-30",
                                                            "items": [_item(al)]}, headers=h).json()["data"]
    approved = client.patch("/api/assets/clearance-forms/approve",
                            json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]},
                            headers=h).json()["data"][0]
    r = client.patch("/api/assets/clearance-forms/unapprove",
                     json={"forms": [{"id": form["id"], "rowVersion": approved["rowVersion"]}]}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["data"][0]["status"] == "in_progress"


def test_empty_bulk_names_the_forms_field(client, db, company, admin):
    for proc in ("sep.usp_asset_clearance_approve", "sep.usp_asset_clearance_unapprove"):
        with pytest.raises(AppError) as e:
            db.call(proc, company_id=company, actor_user_id=admin["user_id"], forms="[]")
        assert e.value.status == 422 and "forms" in e.value.field_errors
    r = client.patch("/api/assets/clearance-forms/approve", json={"forms": []}, headers=admin["headers"])
    assert r.status_code == 422 and "forms" in r.json()["fieldErrors"]


def test_clearance_self_rule_and_scope(client, db, company, admin):
    h = admin["headers"]
    officer_emp = factories.employee(db, company)
    officer = factories.login_as(db, client, company, role_codes="hr_officer", employee_id=officer_emp)
    al = fo.allocate(client, h, fo.asset(client, h)["id"], officer_emp)
    own = client.post("/api/assets/clearance-forms", json={"employeeId": str(officer_emp), "clearanceDate": "2024-06-30",
                                                           "items": [_item(al)]}, headers=officer["headers"])
    assert own.status_code == 403

    # Someone else makes it; the officer still cannot approve their own form.
    form = client.post("/api/assets/clearance-forms", json={"employeeId": str(officer_emp), "clearanceDate": "2024-06-30",
                                                            "items": [_item(al)]}, headers=h).json()["data"]
    mine = client.patch("/api/assets/clearance-forms/approve",
                        json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]},
                        headers=officer["headers"])
    assert mine.status_code == 403

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    assert client.get(f"/api/assets/clearance-forms/{form['id']}", headers=staff["headers"]).status_code == 404
    assert client.patch("/api/assets/clearance-forms/approve",
                        json={"forms": [{"id": form["id"], "rowVersion": form["rowVersion"]}]},
                        headers=staff["headers"]).status_code == 403
