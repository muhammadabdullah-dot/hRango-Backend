"""The request engine: submit, two-step flow, reject, cancel, row versions, permissions, scope,
delegation, restrictions, flows and the owning module's effect hook. Travel is used where the
type does not matter: no module owns its effect."""
from datetime import date, timedelta

import pytest

from tests import factories, factories_requests as fr

DAY = date.today() + timedelta(days=40)


@pytest.fixture
def org(db, client):
    return fr.org(db, client)


def submit_travel(client, who, start=DAY, **extra):
    r = client.post("/api/requests/travel", json=fr.travel_body(start, **extra), headers=who.headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def approve(client, who, req, **body):
    return client.post(f"/api/requests/approvals/{req['id']}/approve",
                       json={"rowVersion": req["rowVersion"], **body}, headers=who.headers)


def test_two_step_flow(client, org):
    req = submit_travel(client, org.staff)
    assert req["status"] == "pending" and req["code"].startswith("RQ-TRV-")
    assert req["nextApproverName"].startswith("Mansoor") and req["details"]["legs"][0]["toPlace"] == "Karachi"
    assert [s["actionTaken"] for s in req["steps"]] == ["submitted", "pending"]

    mine = client.get("/api/requests/travel", params={"view": "my"}, headers=org.staff.headers).json()
    assert mine["meta"]["total"] == 1 and mine["counts"]["pending"] == 1

    waiting = client.get("/api/requests/approvals", params={"status": "pending"}, headers=org.manager.headers).json()
    assert [r["id"] for r in waiting["data"]] == [req["id"]] and waiting["data"][0]["isWaiting"] is True

    # The final authority is not the approver yet.
    early = approve(client, org.fa, req)
    assert early.status_code == 403

    step1 = approve(client, org.manager, req, remarks="Fine by me")
    assert step1.status_code == 200, step1.text
    step1 = step1.json()["data"]
    assert step1["status"] == "pending" and step1["nextApproverName"].startswith("Farah")
    assert "approve" not in step1["actions"]

    done = approve(client, org.fa, step1)
    assert done.status_code == 200, done.text
    done = done.json()["data"]
    assert done["status"] == "approved" and done["nextApproverName"] is None
    assert [s["actionTaken"] for s in done["steps"]] == ["submitted", "approved", "approved"]
    assert done["steps"][1]["actedByName"].startswith("Mansoor") and done["steps"][1]["remarks"] == "Fine by me"


def test_reject_needs_a_reason_and_ends_the_request(client, org):
    req = submit_travel(client, org.staff)
    no_reason = client.post(f"/api/requests/approvals/{req['id']}/reject", json={"rowVersion": req["rowVersion"]},
                            headers=org.manager.headers)
    assert no_reason.status_code == 422 and "remarks" in no_reason.json()["fieldErrors"]
    r = client.post(f"/api/requests/approvals/{req['id']}/reject",
                    json={"rowVersion": req["rowVersion"], "remarks": "Not this month"}, headers=org.manager.headers)
    assert r.status_code == 200 and r.json()["data"]["status"] == "rejected"
    again = approve(client, org.fa, r.json()["data"])
    assert again.status_code == 403


def test_row_version_conflict(client, org):
    req = submit_travel(client, org.staff)
    edited = client.put(f"/api/requests/travel/{req['id']}",
                        json={**fr.travel_body(DAY, days=3), "rowVersion": req["rowVersion"]}, headers=org.staff.headers)
    assert edited.status_code == 200, edited.text
    assert edited.json()["data"]["toDate"] == str(DAY + timedelta(days=2))
    stale = approve(client, org.manager, req)
    assert stale.status_code == 409
    assert approve(client, org.manager, edited.json()["data"]).status_code == 200
    # Once an approver has acted, the requester can no longer edit.
    current = client.get(f"/api/requests/travel/{req['id']}", headers=org.staff.headers).json()["data"]
    late = client.put(f"/api/requests/travel/{req['id']}",
                      json={**fr.travel_body(DAY), "rowVersion": current["rowVersion"]}, headers=org.staff.headers)
    assert late.status_code == 409


def test_withdraw_delete_and_cancel_an_approved_request(client, org):
    pending = submit_travel(client, org.staff)
    r = client.post(f"/api/requests/travel/{pending['id']}/cancel",
                    json={"reason": "Trip moved", "rowVersion": pending["rowVersion"]}, headers=org.staff.headers)
    assert r.status_code == 200 and r.json()["data"]["status"] == "cancelled"

    gone = submit_travel(client, org.staff, start=DAY + timedelta(days=10))
    assert client.delete(f"/api/requests/travel/{gone['id']}", params={"rowVersion": gone["rowVersion"]},
                         headers=org.staff.headers).status_code == 204
    assert client.get(f"/api/requests/travel/{gone['id']}", headers=org.staff.headers).status_code == 404

    req = submit_travel(client, org.staff, start=DAY + timedelta(days=20))
    req = approve(client, org.manager, req).json()["data"]
    req = approve(client, org.fa, req).json()["data"]
    assert req["status"] == "approved"
    assert client.delete(f"/api/requests/travel/{req['id']}", params={"rowVersion": req["rowVersion"]},
                         headers=org.staff.headers).status_code == 409

    r = client.post(f"/api/requests/travel/{req['id']}/cancel", json={"reason": "", "rowVersion": req["rowVersion"]},
                    headers=org.staff.headers)
    assert r.status_code == 422
    r = client.post(f"/api/requests/travel/{req['id']}/cancel",
                    json={"reason": "Client cancelled", "rowVersion": req["rowVersion"]}, headers=org.staff.headers)
    assert r.status_code == 200, r.text
    req = r.json()["data"]
    assert req["status"] == "cancelling" and req["nextApproverName"].startswith("Mansoor")

    box = client.get("/api/requests/approvals", params={"box": "cancellations", "status": "pending"},
                     headers=org.manager.headers).json()
    assert [x["id"] for x in box["data"]] == [req["id"]]
    # Rejecting the cancellation leaves the request approved; asking again and approving cancels it.
    kept = client.post(f"/api/requests/approvals/{req['id']}/reject",
                       json={"rowVersion": req["rowVersion"], "remarks": "Keep it"}, headers=org.manager.headers)
    assert kept.json()["data"]["status"] == "approved"
    req = client.post(f"/api/requests/travel/{req['id']}/cancel",
                      json={"reason": "Really cancelled", "rowVersion": kept.json()["data"]["rowVersion"]},
                      headers=org.staff.headers).json()["data"]
    req = approve(client, org.manager, req).json()["data"]
    req = approve(client, org.fa, req).json()["data"]
    assert req["status"] == "cancelled"
    assert [s["actionTaken"] for s in req["steps"] if s["purpose"] == "cancellation"][-3:] == [
        "cancel_requested", "approved", "approved"]


def test_permissions_and_admin_only_types(client, org):
    req = submit_travel(client, org.staff)
    # Staff hold no approve permission: the Approvals buttons are closed to them.
    assert approve(client, org.staff2, req).status_code == 403
    # A request for someone else needs a create scope that reaches them.
    r = client.post("/api/requests/travel", json={**fr.travel_body(DAY), "employeeId": str(org.staff2.employee_id)},
                    headers=org.staff.headers)
    assert r.status_code == 403
    # Promotion is filed by HR for an employee, never for oneself.
    body = {"details": {"gradeId": 1, "designationId": 1, "jobTitleId": 1, "newSalary": 100000}}
    assert client.post("/api/requests/promotion", json=body, headers=org.staff.headers).status_code == 403
    # Settings are closed to staff.
    assert client.get("/api/requests/settings/flows", headers=org.staff.headers).status_code == 403


def test_scope_line_manager_sees_only_their_team(client, org):
    mine = submit_travel(client, org.staff)
    theirs = submit_travel(client, org.other)
    seen = client.get("/api/requests/travel", params={"view": "all"}, headers=org.manager.headers).json()
    assert [r["id"] for r in seen["data"]] == [mine["id"]]
    subs = client.get("/api/requests/travel", params={"view": "subordinates"}, headers=org.manager.headers).json()
    assert [r["id"] for r in subs["data"]] == [mine["id"]]
    assert client.get(f"/api/requests/travel/{theirs['id']}", headers=org.manager.headers).status_code == 404
    everyone = client.get("/api/requests/travel", params={"view": "all"}, headers=org.hr["headers"]).json()
    assert {r["id"] for r in everyone["data"]} == {mine["id"], theirs["id"]}
    # HR files for an employee ("All Requests").
    r = client.post("/api/requests/travel", json={**fr.travel_body(DAY + timedelta(days=5)),
                                                   "employeeId": str(org.staff2.employee_id)}, headers=org.hr["headers"])
    assert r.status_code == 201 and r.json()["data"]["employeeId"] == str(org.staff2.employee_id)


def test_delegation(client, org):
    h = org.admin["headers"]
    same = client.post("/api/requests/settings/delegations",
                       json={"delegatorId": org.manager.employee_id, "delegateeId": org.manager.employee_id,
                             "requestType": "travel"}, headers=h)
    assert same.status_code == 422
    d = client.post("/api/requests/settings/delegations",
                    json={"delegatorId": org.manager.employee_id, "delegateeId": org.other_manager.employee_id,
                          "requestType": "travel", "description": "On leave"}, headers=h)
    assert d.status_code == 201, d.text
    d = d.json()["data"]
    dup = client.post("/api/requests/settings/delegations",
                      json={"delegatorId": org.manager.employee_id, "delegateeId": org.fa.employee_id,
                            "requestType": "travel"}, headers=h)
    assert dup.status_code == 409

    req = submit_travel(client, org.staff)
    box = client.get("/api/requests/approvals", params={"box": "delegates", "status": "pending"},
                     headers=org.other_manager.headers).json()
    assert [r["id"] for r in box["data"]] == [req["id"]] and box["data"][0]["delegatorName"].startswith("Mansoor")
    r = approve(client, org.other_manager, req)
    assert r.status_code == 200, r.text
    step = r.json()["data"]["steps"][1]
    assert step["isDelegate"] is True and step["actedByName"].startswith("Omar") and step["approverName"].startswith("Mansoor")

    off = client.patch(f"/api/requests/settings/delegations/{d['id']}",
                       json={"isActive": False, "rowVersion": d["rowVersion"]}, headers=h)
    assert off.status_code == 200 and off.json()["data"]["isActive"] is False
    req2 = submit_travel(client, org.staff2)
    assert approve(client, org.other_manager, req2).status_code == 403


def test_restriction_blocks_a_type_for_its_dates(client, org):
    h = org.admin["headers"]
    past = client.post("/api/requests/settings/restrictions",
                       json={"requestType": "travel", "startDate": str(date.today()), "endDate": str(DAY)}, headers=h)
    assert past.status_code == 422
    r = client.post("/api/requests/settings/restrictions",
                    json={"requestType": "travel", "startDate": str(DAY), "endDate": str(DAY + timedelta(days=3)),
                          "description": "Audit week"}, headers=h)
    assert r.status_code == 201, r.text
    overlap = client.post("/api/requests/settings/restrictions",
                          json={"requestType": "travel", "startDate": str(DAY + timedelta(days=1)),
                                "endDate": str(DAY + timedelta(days=9))}, headers=h)
    assert overlap.status_code == 409
    blocked = client.post("/api/requests/travel", json=fr.travel_body(DAY + timedelta(days=2)), headers=org.staff.headers)
    assert blocked.status_code == 422 and blocked.json()["code"] == "REQUEST_RESTRICTED"
    assert client.post("/api/requests/travel", json=fr.travel_body(DAY + timedelta(days=10)),
                       headers=org.staff.headers).status_code == 201
    listed = client.get("/api/requests/settings/restrictions", params={"requestType": "travel"}, headers=h).json()
    assert listed["meta"]["total"] == 1
    row = listed["data"][0]
    assert client.delete(f"/api/requests/settings/restrictions/{row['id']}", params={"rowVersion": row["rowVersion"]},
                         headers=h).status_code == 204
    assert client.post("/api/requests/travel", json=fr.travel_body(DAY + timedelta(days=2)),
                       headers=org.staff.headers).status_code == 201


def test_flow_editor_and_custom_flow(client, db, org):
    h = org.admin["headers"]
    base = {"requestType": "travel", "name": "Travel flow", "scopeType": "company"}
    bad = client.post("/api/requests/settings/flows", json={**base, "nodes": [
        {"stepNo": 1, "isCondition": True, "expression": "salary > 3"},
        {"stepNo": 2, "approverKind": "line_manager"}]}, headers=h)
    assert bad.status_code == 422 and "nodes[0].expression" in bad.json()["fieldErrors"]
    loop = client.post("/api/requests/settings/flows", json={**base, "nodes": [
        {"stepNo": 1, "approverKind": "line_manager"}, {"stepNo": 2, "approverKind": "hr_manager", "next": 1}]},
        headers=h)
    assert loop.status_code == 422

    # More than three days: the line manager, then the HR Manager authority; otherwise the line manager only.
    flow = client.post("/api/requests/settings/flows", json={**base, "nodes": [
        {"stepNo": 1, "isCondition": True, "expression": "days > 3", "ifTrue": 2, "ifFalse": 4},
        {"stepNo": 2, "approverKind": "line_manager"},
        {"stepNo": 3, "approverKind": "hr_manager", "next": 5},
        {"stepNo": 4, "approverKind": "line_manager", "isObserver": False},
        {"stepNo": 5, "approverKind": "final_authority", "isObserver": True}]}, headers=h)
    assert flow.status_code == 201, flow.text
    flow = flow.json()["data"]
    assert [n["stepNo"] for n in flow["nodes"]] == [1, 2, 3, 4, 5] and flow["nodes"][0]["ifTrue"] == 2

    auth = client.post("/api/requests/settings/authorities",
                       json={"authority": "hr_manager", "employeeId": org.other_manager.employee_id}, headers=h)
    assert auth.status_code == 201, auth.text
    assert client.post("/api/requests/settings/authorities",
                       json={"authority": "hr_manager", "employeeId": org.fa.employee_id}, headers=h).status_code == 409

    long_trip = submit_travel(client, org.staff, days=5)
    r = approve(client, org.manager, long_trip).json()["data"]
    assert r["status"] == "pending" and r["nextApproverName"].startswith("Omar")
    r = approve(client, org.other_manager, r).json()["data"]
    # Node 3 goes on to node 5: the final authority is only informed, and the request is approved.
    assert r["status"] == "approved"
    assert [s["actionTaken"] for s in r["steps"]] == ["submitted", "approved", "approved", "informed"]

    short_trip = submit_travel(client, org.staff2, start=DAY + timedelta(days=30), days=1)
    r = approve(client, org.manager, short_trip).json()["data"]
    assert r["status"] == "approved"

    # Editing saves a new version; the old one stops being listed.
    edited = client.put(f"/api/requests/settings/flows/{flow['id']}",
                        json={**base, "rowVersion": flow["rowVersion"], "nodes": [
                            {"stepNo": 1, "approverKind": "final_authority"}]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["id"] != flow["id"]
    stale = client.put(f"/api/requests/settings/flows/{flow['id']}",
                       json={**base, "rowVersion": flow["rowVersion"], "nodes": [
                           {"stepNo": 1, "approverKind": "line_manager"}]}, headers=h)
    assert stale.status_code == 409
    flows = client.get("/api/requests/settings/flows", params={"requestType": "travel"}, headers=h).json()
    assert [f["id"] for f in flows["data"]] == [edited.json()["data"]["id"]]
    r = submit_travel(client, org.other, start=DAY + timedelta(days=50))
    assert r["nextApproverName"].startswith("Farah")


def test_effect_hook_runs_on_final_approval_and_can_block_it(client, db, org):
    body = {"fromDate": str(DAY), "reason": "Bank visit",
            "details": {"windowDate": str(DAY), "startTime": "11:00", "endTime": "13:00"}}
    stub = "INSERT core.audit_log (entity_type, entity_id, action_name, performed_at) " \
           "VALUES (N'test.effect', @request_id, N'apply', SYSUTCDATETIME());"
    with fr.StubProcedure(db, "att.usp_request_apply_time_window", stub):
        req = client.post("/api/requests/official-visit", json=body, headers=org.staff.headers)
        assert req.status_code == 201, req.text
        req = req.json()["data"]
        assert req["details"]["windowKind"] == "official_visit" and req["details"]["durationMinutes"] == 120
        req = approve(client, org.manager, req).json()["data"]
        assert fr.marks(db, int(req["id"])) == 0
        req = approve(client, org.fa, req).json()["data"]
        assert req["status"] == "approved" and fr.marks(db, int(req["id"])) == 1

    blocker = "THROW 50409, N'windowDate|DAY_FROZEN|Attendance for this day is frozen.', 1;"
    with fr.StubProcedure(db, "att.usp_request_apply_time_window", blocker):
        req = client.post("/api/requests/official-visit", json={**body, "fromDate": str(DAY + timedelta(days=1)),
                                                                "details": {**body["details"],
                                                                            "windowDate": str(DAY + timedelta(days=1))}},
                          headers=org.staff.headers).json()["data"]
        req = approve(client, org.manager, req).json()["data"]
        r = approve(client, org.fa, req)
        assert r.status_code == 409 and r.json()["code"] == "DAY_FROZEN"
        still = client.get(f"/api/requests/approvals/{req['id']}", headers=org.fa.headers).json()["data"]
        assert still["status"] == "pending" and "approve" in still["actions"]


def test_forward_consent_and_bulk(client, org):
    a = submit_travel(client, org.staff)
    r = client.post(f"/api/requests/approvals/{a['id']}/forward",
                    json={"employeeId": org.other_manager.employee_id, "remarks": "Please check",
                          "rowVersion": a["rowVersion"]}, headers=org.manager.headers)
    assert r.status_code == 200, r.text
    a = r.json()["data"]
    assert a["nextApproverName"].startswith("Omar") and a["steps"][1]["actionTaken"] == "forwarded"

    # A consent step (Can Disagree): the person is asked for consent; either answer moves the flow on.
    h = org.admin["headers"]
    flow = client.post("/api/requests/settings/flows", json={
        "requestType": "travel", "name": "With consent", "scopeType": "employee", "scopeId": org.staff2.employee_id,
        "nodes": [{"stepNo": 1, "approverKind": "employee", "employeeId": org.other.employee_id, "canDisagree": True},
                  {"stepNo": 2, "approverKind": "line_manager"}]}, headers=h)
    assert flow.status_code == 201, flow.text
    b = submit_travel(client, org.staff2, start=DAY + timedelta(days=5))
    box = client.get("/api/requests/approvals", params={"box": "consents"}, headers=org.other.headers)
    assert box.status_code == 200 and [x["id"] for x in box.json()["data"]] == [b["id"]]
    wrong = approve(client, org.other, b)
    assert wrong.status_code == 422  # a consent step is agreed to, not approved
    r = client.post(f"/api/requests/approvals/{b['id']}/consent",
                    json={"agree": False, "remarks": "Busy that week", "rowVersion": b["rowVersion"]},
                    headers=org.other.headers)
    assert r.status_code == 200, r.text
    b = r.json()["data"]
    assert b["status"] == "pending" and b["steps"][1]["actionTaken"] == "disagreed"

    c = submit_travel(client, org.staff, start=DAY + timedelta(days=60))
    stale = {"id": c["id"], "rowVersion": "0000000000000000"}
    res = client.post("/api/requests/approvals/bulk-approve",
                      json={"items": [{"id": b["id"], "rowVersion": b["rowVersion"]}, stale]},
                      headers=org.manager.headers)
    assert res.status_code == 200, res.text
    out = {x["id"]: x for x in res.json()["data"]}
    assert out[b["id"]]["ok"] is True and out[b["id"]]["status"] == "approved"
    assert out[c["id"]]["ok"] is False and out[c["id"]]["code"] == "CONFLICT"


def test_types_and_attachments(client, db, org):
    types = client.get("/api/requests/types", headers=org.staff.headers).json()["data"]
    codes = {t["code"]: t for t in types}
    assert codes["relaxation"]["kind"] == "time_window" and codes["promotion"]["isAdminOnly"] is True
    assert codes["expense"]["kind"] == "expense" and codes["air_ticket"]["kind"] == "air_ticket"
    assert codes["requisition"]["kind"] == "requisition"

    # Attachments are uploaded files, attached by id; the response gives a signed link, never a path.
    ticket = factories.upload(client, org.staff.headers, name="ticket.pdf", module="requests")
    req = submit_travel(client, org.staff, attachments=[int(ticket["id"])])
    assert [(a["fileId"], a["name"]) for a in req["attachments"]] == [(ticket["id"], "ticket.pdf")]
    got = client.get(req["attachments"][0]["url"])
    assert got.status_code == 200 and got.content == factories.PDF_BYTES

    # A file of another company is refused, on submit and when attaching later.
    stranger = fr.org(db, client)
    theirs = factories.upload(client, stranger.staff.headers, name="theirs.pdf")
    r = client.post("/api/requests/travel", headers=org.staff.headers,
                    json=fr.travel_body(DAY + timedelta(days=70), attachments=[int(theirs["id"])]))
    assert r.status_code == 422 and "attachments" in r.json()["fieldErrors"]
    r = client.post(f"/api/requests/travel/{req['id']}/attachments", json={"fileId": theirs["id"]},
                    headers=org.staff.headers)
    assert r.status_code == 422 and "fileId" in r.json()["fieldErrors"]

    hotel = factories.upload(client, org.staff.headers, name="hotel.png", content=factories.PNG_BYTES)
    a = client.post(f"/api/requests/travel/{req['id']}/attachments", json={"fileId": hotel["id"], "label": "Hotel"},
                    headers=org.staff.headers)
    assert a.status_code == 201, a.text
    assert a.json()["data"]["name"] == "hotel.png" and a.json()["data"]["url"].startswith(f"/api/files/{hotel['id']}/")
    assert client.post(f"/api/requests/travel/{req['id']}/attachments", json={"fileId": hotel["id"]},
                       headers=org.staff.headers).status_code == 409
    # An attached file cannot be deleted from the file store while the request uses it.
    assert client.delete(f"/api/files/{hotel['id']}", headers=org.staff.headers).status_code == 409
    assert client.delete(f"/api/requests/travel/{req['id']}/attachments/{a.json()['data']['id']}",
                         headers=org.staff.headers).status_code == 204
    assert client.delete(f"/api/files/{hotel['id']}", headers=org.staff.headers).status_code == 204
    csv = client.get("/api/requests/travel/export", params={"view": "my"}, headers=org.staff.headers)
    assert csv.status_code == 403  # staff hold no export permission
    csv = client.get("/api/requests/travel/export", params={"view": "all"}, headers=org.hr["headers"])
    assert csv.status_code == 200 and req["code"] in csv.text


def test_approval_detail_offers_only_the_approvers_decisions(client, org):
    """The Approvals detail gives the approver the decisions their step allows, never the requester's
    edit, delete or cancel; the request type's own screen keeps them for the requester."""
    req = submit_travel(client, org.staff)
    seen = client.get(f"/api/requests/approvals/{req['id']}", headers=org.manager.headers)
    assert seen.status_code == 200, seen.text
    assert seen.json()["data"]["actions"] == ["view", "approve", "reject", "forward"]
    own = client.get(f"/api/requests/travel/{req['id']}", headers=org.staff.headers).json()["data"]
    assert {"edit", "delete", "cancel"} <= set(own["actions"]) and "approve" not in own["actions"]
    # After deciding, the approver has nothing left to do on it.
    done = approve(client, org.manager, req).json()["data"]
    assert done["actions"] == ["view"]


def test_details_keep_empty_fields_of_their_lists(client, org):
    """Travel legs, stays and loan guarantors are lists inside the details: empty fields come as null."""
    body = fr.travel_body(DAY)
    body["details"]["stays"] = [{"stayType": "hotel", "address": "Mall Road", "city": "Karachi",
                                 "fromDate": str(DAY), "toDate": str(DAY + timedelta(days=1)), "nights": 1,
                                 "phone": "0300", "email": "a@b.c"}]
    r = client.post("/api/requests/travel", json=body, headers=org.staff.headers)
    assert r.status_code == 201, r.text
    leg = r.json()["data"]["details"]["legs"][0]
    assert "distanceKm" in leg and leg["distanceKm"] is None and "stayRequired" in leg
    assert r.json()["data"]["details"]["stays"][0]["city"] == "Karachi"


def test_delegation_delete_and_restriction_edit(client, org):
    h = org.admin["headers"]
    d = client.post("/api/requests/settings/delegations",
                    json={"delegatorId": org.manager.employee_id, "delegateeId": org.other_manager.employee_id,
                          "requestType": "travel"}, headers=h).json()["data"]
    off = client.patch(f"/api/requests/settings/delegations/{d['id']}",
                       json={"isActive": False, "rowVersion": d["rowVersion"]}, headers=h).json()["data"]
    stale = client.delete(f"/api/requests/settings/delegations/{d['id']}", params={"rowVersion": d["rowVersion"]},
                          headers=h)
    assert stale.status_code == 409
    assert client.delete(f"/api/requests/settings/delegations/{d['id']}", params={"rowVersion": off["rowVersion"]},
                         headers=org.staff.headers).status_code == 403
    assert client.delete(f"/api/requests/settings/delegations/{d['id']}", params={"rowVersion": off["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"/api/requests/settings/delegations/{d['id']}", headers=h).status_code == 404

    first = client.post("/api/requests/settings/restrictions",
                        json={"requestType": "travel", "startDate": str(DAY), "endDate": str(DAY + timedelta(days=3))},
                        headers=h).json()["data"]
    later = client.post("/api/requests/settings/restrictions",
                        json={"requestType": "travel", "startDate": str(DAY + timedelta(days=10)),
                              "endDate": str(DAY + timedelta(days=12))}, headers=h).json()["data"]
    body = {"requestType": "travel", "startDate": str(DAY), "endDate": str(DAY + timedelta(days=5)),
            "description": "Audit fortnight"}
    edited = client.put(f"/api/requests/settings/restrictions/{first['id']}",
                        json={**body, "rowVersion": first["rowVersion"]}, headers=h)
    assert edited.status_code == 200, edited.text
    edited = edited.json()["data"]
    assert edited["endDate"] == str(DAY + timedelta(days=5)) and edited["description"] == "Audit fortnight"
    assert client.put(f"/api/requests/settings/restrictions/{first['id']}",
                      json={**body, "rowVersion": first["rowVersion"]}, headers=h).status_code == 409
    overlap = client.put(f"/api/requests/settings/restrictions/{first['id']}",
                         json={**body, "endDate": str(DAY + timedelta(days=11)), "rowVersion": edited["rowVersion"]},
                         headers=h)
    assert overlap.status_code == 409 and overlap.json()["code"] == "RESTRICTION_OVERLAP"
    assert later["id"] != first["id"]
    blocked = client.post("/api/requests/travel", json=fr.travel_body(DAY + timedelta(days=5)), headers=org.staff.headers)
    assert blocked.status_code == 422 and blocked.json()["code"] == "REQUEST_RESTRICTED"


def test_colleague_options_for_a_shift_swap(client, org):
    r = client.get("/api/requests/options/colleagues", params={"q": "Saad"}, headers=org.staff.headers)
    assert r.status_code == 200, r.text
    rows = r.json()["data"]
    assert [x["id"] for x in rows] == [str(org.staff2.employee_id)]
    assert set(rows[0]) == {"id", "code", "name", "departmentId", "departmentName", "branchId", "branchName"}
    everyone = client.get("/api/requests/options/colleagues", params={"pageSize": 100}, headers=org.staff.headers).json()
    ids = [x["id"] for x in everyone["data"]]
    assert str(org.staff.employee_id) not in ids and str(org.other.employee_id) in ids
    assert everyone["meta"]["total"] == len(ids)
    # HR filing for someone names the requester to leave out.
    for_staff = client.get("/api/requests/options/colleagues", params={"employeeId": org.staff2.employee_id,
                                                                        "pageSize": 100}, headers=org.hr["headers"])
    assert for_staff.status_code == 200
    assert str(org.staff2.employee_id) not in [x["id"] for x in for_staff.json()["data"]]
