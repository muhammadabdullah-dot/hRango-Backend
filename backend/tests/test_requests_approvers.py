"""The approver a request's flow names sees and decides it whatever their role's permissions for the
request type (ACC-13; Test Run 18-19 Nov 2026, rows 7B.41 and 7B.43: a Department Head on a promotion,
which is sensitive and so not in her role), the types they have approvals of (the web app's menus), the
links the inbox gets for a request (rows 6.18 and 15.36), and who decided a request as the lists show it
(row 7.38: the list named the employee's final authority, who had no part in it)."""
from datetime import date, timedelta

import pytest

from tests import factories, factories_requests as fr

DAY = date.today() + timedelta(days=40)


@pytest.fixture
def org(db, client):
    return fr.org(db, client)


def _promotion(client, db, org) -> dict:
    def ref(table):
        return fr._scalar(db, f"SET NOCOUNT ON; INSERT org.{table} (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)",
                          org.company_id, f"{table} {factories.tag()}")

    fr.execute(db, "INSERT hr.employee_salary (employee_id, effective_date, amount) VALUES (?, '2025-01-01', 80000)",
               org.staff.employee_id)
    r = client.post("/api/requests/promotion", headers=org.hr["headers"], json={
        "employeeId": org.staff.employee_id, "details": {
            "gradeId": ref("grade"), "designationId": ref("designation"), "jobTitleId": ref("job_title"),
            "newSalary": 95000, "effectiveDate": str(DAY)}})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_an_approver_without_the_types_permission_sees_and_decides_it(client, db, org):
    req = _promotion(client, db, org)
    mh = org.manager.headers
    # The line manager's role holds no Promotion permission (salary figures are sensitive) ...
    assert client.get("/api/requests/promotion", headers=mh).status_code == 403
    assert client.get(f"/api/requests/promotion/{req['id']}", headers=mh).status_code == 403
    # ... yet the flow names him: the summary, the Approvals list and the request itself are his.
    summary = client.get("/api/requests/approvals/summary", headers=mh)
    assert summary.status_code == 200, summary.text
    assert summary.json()["data"] == [
        {"requestType": "promotion", "requestTypeName": "Promotion", "total": 1, "waiting": 1}]
    listed = client.get("/api/requests/approvals", params={"type": "promotion", "status": "pending"}, headers=mh)
    assert [x["id"] for x in listed.json()["data"]] == [req["id"]]
    detail = client.get(f"/api/requests/approvals/{req['id']}", headers=mh)
    assert detail.status_code == 200 and {"approve", "reject"} <= set(detail.json()["data"]["actions"])

    # The inbox opens the promotion's Approvals with the request (no /requests/approvals/<id> page exists).
    told = fr.notifications(db, org.manager.user_id, int(req["id"]))
    assert [n["link"] for n in told] == [f"/requests/promotion?tab=approvals&request={req['id']}"]

    ok = client.post(f"/api/requests/approvals/{req['id']}/approve", headers=mh,
                     json={"rowVersion": detail.json()["data"]["rowVersion"], "remarks": "Ready for the next grade"})
    assert ok.status_code == 200, ok.text
    assert ok.json()["data"]["nextApproverName"].startswith("Farah")
    after = client.get("/api/requests/approvals/summary", headers=mh).json()["data"]
    assert after == [{"requestType": "promotion", "requestTypeName": "Promotion", "total": 1, "waiting": 0}]
    # The next approver is told the same way; someone the flow does not name has no approvals at all.
    assert [n["link"] for n in fr.notifications(db, org.fa.user_id, int(req["id"]))] == [
        f"/requests/promotion?tab=approvals&request={req['id']}"]
    assert client.get("/api/requests/approvals/summary", headers=org.staff2.headers).json()["data"] == []
    # Nor does the employee the promotion is for (their own requests are never their approvals).
    assert client.get("/api/requests/approvals/summary", headers=org.staff.headers).json()["data"] == []


def test_the_requester_is_told_with_a_link_to_their_request(client, db, org):
    r = client.post("/api/requests/travel", json=fr.travel_body(DAY), headers=org.staff.headers)
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    req = client.post(f"/api/requests/approvals/{req['id']}/approve", headers=org.manager.headers,
                      json={"rowVersion": req["rowVersion"]}).json()["data"]
    done = client.post(f"/api/requests/approvals/{req['id']}/approve", headers=org.fa.headers,
                       json={"rowVersion": req["rowVersion"]})
    assert done.status_code == 200 and done.json()["data"]["status"] == "approved"
    told = fr.notifications(db, org.staff.user_id, int(req["id"]))
    assert [n["type"] for n in told] == ["request_update"]
    assert told[0]["link"] == f"/requests/travel?request={req['id']}"


def test_lists_name_who_decided_not_the_final_authority(client, db, org):
    """Row 7.38: Work From Home's Approver column read the employee's final authority once a request was
    decided. The lists now carry who decided (decidedById / decidedByName), whatever the type."""
    def travel(who, start):
        r = client.post("/api/requests/travel", json=fr.travel_body(start), headers=who.headers)
        assert r.status_code == 201, r.text
        return r.json()["data"]

    # Rejected by the line manager: the final authority (Farah) never acted.
    first = travel(org.staff, DAY)
    assert first["decidedById"] is None and first["decidedByName"] is None
    rejected = client.post(f"/api/requests/approvals/{first['id']}/reject", headers=org.manager.headers,
                           json={"rowVersion": first["rowVersion"], "remarks": "Not this month"})
    assert rejected.status_code == 200, rejected.text
    # Approved at both steps: the last decision is the final authority's.
    second = travel(org.staff, DAY + timedelta(days=10))
    second = client.post(f"/api/requests/approvals/{second['id']}/approve", headers=org.manager.headers,
                         json={"rowVersion": second["rowVersion"]}).json()["data"]
    assert second["decidedByName"].startswith("Mansoor") and second["status"] == "pending"
    client.post(f"/api/requests/approvals/{second['id']}/approve", headers=org.fa.headers,
                json={"rowVersion": second["rowVersion"]})

    rows = {x["id"]: x for x in client.get("/api/requests/travel", params={"view": "all"},
                                           headers=org.hr["headers"]).json()["data"]}
    assert rows[first["id"]]["status"] == "rejected"
    assert rows[first["id"]]["decidedById"] == str(org.manager.employee_id)
    assert rows[first["id"]]["decidedByName"].startswith("Mansoor")
    assert rows[first["id"]]["finalAuthorityName"].startswith("Farah")
    assert rows[second["id"]]["status"] == "approved" and rows[second["id"]]["decidedByName"].startswith("Farah")
    # The Approvals list carries it too.
    mine = client.get("/api/requests/approvals", params={"type": "travel"}, headers=org.manager.headers).json()["data"]
    assert {x["id"]: x["decidedByName"].split()[0] for x in mine} == {first["id"]: "Mansoor", second["id"]: "Farah"}
