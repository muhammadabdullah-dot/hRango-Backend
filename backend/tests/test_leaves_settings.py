"""Leaves settings: general settings, leave types, leave policies and enrolment."""
import pytest

from tests import factories
from tests import factories_leaves as fl


@pytest.fixture
def org(db, client):
    company = factories.company(db)
    fl.execute(db, "UPDATE org.company SET fiscal_year_start_month = 1 WHERE id = ?", company)  # calendar leave year
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    return company, admin["headers"]


def test_general_settings(client, org):
    _, h = org
    r = client.get("/api/leaves/settings", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["data"] == {"finalApprovalBy": "hr_manager", "approveOnStatus": "approved", "postDeadline": False,
                                "rowVersion": None}

    saved = client.put("/api/leaves/settings", headers=h, json={
        "finalApprovalBy": "line_manager", "approveOnStatus": "pending", "postDeadline": True})
    assert saved.status_code == 200, saved.text
    data = saved.json()["data"]
    assert data["finalApprovalBy"] == "line_manager" and data["postDeadline"] is True and data["rowVersion"]

    stale = client.put("/api/leaves/settings", headers=h, json={
        "finalApprovalBy": "hr_manager", "approveOnStatus": "approved", "postDeadline": False})
    assert stale.status_code == 409

    bad = client.put("/api/leaves/settings", headers=h, json={
        "finalApprovalBy": "nobody", "approveOnStatus": "approved", "rowVersion": data["rowVersion"]})
    assert bad.status_code == 422 and "finalApprovalBy" in bad.json()["fieldErrors"]

    again = client.put("/api/leaves/settings", headers=h, json={
        "finalApprovalBy": "department_head", "approveOnStatus": "approved", "rowVersion": data["rowVersion"]})
    assert again.status_code == 200 and again.json()["data"]["finalApprovalBy"] == "department_head"


def test_leave_type_lifecycle(client, db, org):
    company, h = org
    t = fl.leave_type(client, h, allowEncashment=True, encashmentMin=2, encashmentMax=5, allowBackDate=False,
                      backDateLimitDays=9, isShortLeave=True,
                      shortSlabs=[{"name": "Two hours", "balance": 0.25, "valueType": "percentage", "value": 25}])
    assert isinstance(t["id"], str) and t["encashmentMax"] == 5 and t["backDateLimitDays"] is None
    assert t["shortSlabs"] == [{"name": "Two hours", "balance": 0.25, "valueType": "percentage", "value": 25.0}]
    assert t["inUse"] == 0 and t["tenure"] == "yearly"

    dup = client.post("/api/leaves/types", headers=h, json={**fl.LEAVE_TYPE, "title": "Another",
                                                            "shortCode": t["shortCode"].lower()})
    assert dup.status_code == 409 and dup.json()["code"] == "LEAVE_TYPE_DUPLICATE"
    assert "shortCode" in dup.json()["fieldErrors"]

    no_slabs = client.post("/api/leaves/types", headers=h, json={**fl.LEAVE_TYPE, "title": "Exp", "shortCode": "EXP",
                                                                 "balanceBasis": "experience"})
    assert no_slabs.status_code == 422 and "experienceSlabs" in no_slabs.json()["fieldErrors"]
    limits = client.post("/api/leaves/types", headers=h, json={**fl.LEAVE_TYPE, "title": "Enc", "shortCode": "ENC",
                                                               "allowEncashment": True, "encashmentMin": 6,
                                                               "encashmentMax": 2})
    assert limits.status_code == 422 and "encashmentMax" in limits.json()["fieldErrors"]
    gender = client.post("/api/leaves/types", headers=h, json={**fl.LEAVE_TYPE, "title": "G", "shortCode": "G",
                                                               "gender": "other"})
    assert gender.status_code == 422 and "gender" in gender.json()["fieldErrors"]

    page = client.get("/api/leaves/types", params={"q": t["title"]}, headers=h).json()
    assert page["meta"]["total"] == 1 and page["data"][0]["id"] == t["id"]

    body = {**fl.LEAVE_TYPE, "title": t["title"], "shortCode": t["shortCode"], "allowance": 12,
            "balanceBasis": "experience", "experienceSlabs": [{"minMonths": 0, "maxMonths": 11, "balance": 8},
                                                               {"minMonths": 12, "balance": 14}],
            "rowVersion": t["rowVersion"]}
    edited = client.put(f"/api/leaves/types/{t['id']}", headers=h, json=body)
    assert edited.status_code == 200, edited.text
    assert [s["balance"] for s in edited.json()["data"]["experienceSlabs"]] == [8, 14]
    assert client.put(f"/api/leaves/types/{t['id']}", headers=h, json=body).status_code == 409

    fields = {r["field_name"] for r in fl.rows(
        db, "SELECT field_name FROM core.audit_log WHERE entity_type = N'lv.leave_type' AND entity_id = ? "
            "AND action_name = N'update'", int(t["id"]))}
    assert {"allowance", "balance_basis", "experience_slabs"} <= fields

    overlap = client.put(f"/api/leaves/types/{t['id']}", headers=h, json={
        **body, "rowVersion": edited.json()["data"]["rowVersion"],
        "experienceSlabs": [{"minMonths": 0, "maxMonths": 12, "balance": 8}, {"minMonths": 12, "balance": 14}]})
    assert overlap.status_code == 422 and "experienceSlabs" in overlap.json()["fieldErrors"]

    # In use (a policy gives it): cannot be deleted.
    fl.company_policy(client, h, [t["id"]])
    rv = client.get(f"/api/leaves/types/{t['id']}", headers=h).json()["data"]["rowVersion"]
    assert client.delete(f"/api/leaves/types/{t['id']}", params={"rowVersion": rv}, headers=h).status_code == 409

    free = fl.leave_type(client, h)
    assert client.delete(f"/api/leaves/types/{free['id']}", params={"rowVersion": free["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"/api/leaves/types/{free['id']}", headers=h).status_code == 404


def test_types_refused_without_permission_and_other_company(client, db, org):
    company, h = org
    t = fl.leave_type(client, h)
    emp = factories.employee(db, company)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    assert client.post("/api/leaves/types", json=fl.LEAVE_TYPE, headers=staff["headers"]).status_code == 403
    assert client.get("/api/leaves/types", headers=staff["headers"]).status_code == 403

    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    assert client.get(f"/api/leaves/types/{t['id']}", headers=other_admin["headers"]).status_code == 404


def test_policies_and_enrolment(client, db, org):
    company, h = org
    a, b = fl.leave_type(client, h, allowance=10), fl.leave_type(client, h, allowance=5)
    p = fl.company_policy(client, h, [a["id"], b["id"]], [12, None])
    assert p["totalLeaves"] == 17 and p["policyLevel"] == "company"
    assert {t["effectiveAllowance"] for t in p["types"]} == {12, 5}

    second = client.post("/api/leaves/policies", headers=h, json={
        "title": "Second", "policyKind": "distribution", "policyLevel": "company", "types": [{"leaveTypeId": a["id"]}]})
    assert second.status_code == 409 and "policyLevel" in second.json()["fieldErrors"]
    no_types = client.post("/api/leaves/policies", headers=h, json={
        "title": "Empty", "policyKind": "distribution", "policyLevel": "employee", "types": []})
    assert no_types.status_code == 422 and "types" in no_types.json()["fieldErrors"]

    e1, e2 = factories.employee(db, company), factories.employee(db, company)
    emp_level = client.post("/api/leaves/policies", headers=h, json={
        "title": "Managers", "policyKind": "distribution", "policyLevel": "employee",
        "types": [{"leaveTypeId": a["id"], "allowance": 20}]}).json()["data"]
    enrolled = client.post(f"/api/leaves/policies/{emp_level['id']}/employees", headers=h,
                           json={"employeeIds": [e1, e2]})
    assert enrolled.status_code == 200, enrolled.text
    assert enrolled.json()["data"]["enrolledCount"] == 2
    listed = client.get(f"/api/leaves/policies/{emp_level['id']}/employees", headers=h).json()
    assert {x["employeeId"] for x in listed["data"]} == {str(e1), str(e2)}

    # The employee-level policy outranks the company one: e1 gets 20 days of a and none of b.
    cover = fl.rows(db, "SELECT leave_type_id, allowance FROM lv.fn_leave_coverage(?) WHERE employee_id = ?",
                    company, e1)
    assert [(str(c["leave_type_id"]), float(c["allowance"])) for c in cover] == [(a["id"], 20.0)]

    rival = client.post("/api/leaves/policies", headers=h, json={
        "title": "Rival", "policyKind": "distribution", "policyLevel": "employee",
        "types": [{"leaveTypeId": b["id"]}]}).json()["data"]
    clash = client.post(f"/api/leaves/policies/{rival['id']}/employees", headers=h, json={"employeeIds": [e1]})
    assert clash.status_code == 409 and clash.json()["code"] == "LEAVE_POLICY_ALREADY_ENROLLED"
    company_level = client.post(f"/api/leaves/policies/{p['id']}/employees", headers=h, json={"employeeIds": [e1]})
    assert company_level.status_code == 422

    to_company = client.put(f"/api/leaves/policies/{emp_level['id']}", headers=h, json={
        "title": "Managers", "policyKind": "distribution", "policyLevel": "company",
        "types": [{"leaveTypeId": a["id"]}], "isActive": False, "rowVersion": enrolled.json()["data"]["rowVersion"]})
    assert to_company.status_code == 409

    assert client.delete(f"/api/leaves/policies/{emp_level['id']}/employees/{e2}", headers=h).status_code == 204
    assert client.delete(f"/api/leaves/policies/{emp_level['id']}/employees/{e2}", headers=h).status_code == 404

    half = client.post("/api/leaves/policies", headers=h, json={
        "title": "Half days", "policyKind": "half_short", "policyLevel": "company", "allowHalfDay": True,
        "types": [{"leaveTypeId": a["id"]}]})
    assert half.status_code == 201 and half.json()["data"]["types"] == [] and half.json()["data"]["allowHalfDay"]

    rv = client.get(f"/api/leaves/policies/{rival['id']}", headers=h).json()["data"]["rowVersion"]
    assert client.delete(f"/api/leaves/policies/{rival['id']}", params={"rowVersion": rv}, headers=h).status_code == 204
