"""Plan limits (roadmap 1.3): the employee limit of the organisation's plan, across all its companies."""
from tests import factories
from tests.test_organisation import _general
from tests.test_platform import staff
from tests.test_platform_portal import OWNER_PASSWORD, org


def _plan(client, headers, limit):
    r = client.post("/api/platform/plans", headers=headers, json={
        "name": f"Small {factories.tag()}", "priceMonthly": 500, "priceAnnual": 5000, "employeeLimit": limit})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def _owner(client, body):
    r = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD})
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    return {"Authorization": f"Bearer {data['token']}"}, int(data["user"]["companyId"])


def _hire(client, headers, branch, **extra):
    return client.post("/api/employees", headers=headers, json={
        "firstName": "Plan", "lastName": f"Person {factories.tag()}", "branchId": branch, "joiningDate": "2026-01-05",
        **extra})


def test_the_plan_limit_counts_every_company_of_the_organisation(client, db):
    me = staff(db, client)
    small = _plan(client, me["headers"], 2)
    _, body = org(client, me["headers"], planId=int(small["id"]))
    owner, company = _owner(client, body)

    usage = client.get("/api/organisation/plan", headers=owner).json()["data"]
    assert usage["planName"] == small["name"] and usage["employeeLimit"] == 2 and usage["subscriptionStatus"] == "trial"
    used_before = usage["employeesUsed"]

    branch = factories.branch(db, company)
    hired = []
    for _ in range(2 - used_before):
        r = _hire(client, owner, branch)
        assert r.status_code == 201, r.text
        hired.append(r.json()["data"])

    full = _hire(client, owner, branch)
    assert full.status_code == 409 and full.json()["code"] == "PLAN_EMPLOYEE_LIMIT"
    assert "covers 2 employees" in full.json()["message"]

    # A second company of the same organisation shares the limit.
    second = client.post("/api/organisation/companies", headers=owner, json=_general(f"Second {factories.tag()}"))
    assert second.status_code == 201, second.text
    there = {**owner, "X-Company-Id": second.json()["data"]["id"]}
    other_branch = factories.branch(db, int(second.json()["data"]["id"]))
    assert _hire(client, there, other_branch).status_code == 409
    assert client.get("/api/organisation/plan", headers=there).json()["data"]["companyCount"] == 2

    # Switching someone off frees a place; switching them on again needs one.
    if hired:
        person = hired[0]
        off = client.patch(f"/api/employees/{person['id']}/deactivate", headers=owner,
                           json={"rowVersion": person["rowVersion"]})
        assert off.status_code == 200, off.text
        assert _hire(client, owner, branch).status_code == 201
        back = client.patch(f"/api/employees/{person['id']}/reactivate", headers=owner,
                            json={"rowVersion": off.json()["data"]["rowVersion"]})
        assert back.status_code == 409 and back.json()["code"] == "PLAN_EMPLOYEE_LIMIT"


def test_no_limit_without_a_plan_limit(client, db):
    me = staff(db, client)
    unlimited = client.post("/api/platform/plans", headers=me["headers"], json={
        "name": f"Unlimited {factories.tag()}", "priceMonthly": 900, "priceAnnual": 9000}).json()["data"]
    _, body = org(client, me["headers"], planId=int(unlimited["id"]))
    owner, company = _owner(client, body)
    branch = factories.branch(db, company)
    for _ in range(3):
        assert _hire(client, owner, branch).status_code == 201
    assert client.get("/api/organisation/plan", headers=owner).json()["data"]["employeeLimit"] is None


def test_a_company_outside_any_organisation_has_no_plan(client, db, company, admin):
    assert client.get("/api/organisation/plan", headers=admin["headers"]).json()["data"] is None
