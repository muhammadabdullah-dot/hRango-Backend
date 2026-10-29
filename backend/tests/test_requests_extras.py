"""Requests extras the frontend waits for (frontend/docs/backend-dependencies.md R1-R4 and the overtime gaps):
writing the application with AI (503 for now), WFH cancellation with dates and times, the flowStep filter,
CSV exports, bulk overtime filing (all or nothing), bulk approve with details, and the overtime policy an
approval fell under."""
from datetime import date, timedelta

import pytest

from app.core.permissions import CODES
from tests import factories, factories_requests as fr

DAY = date.today() + timedelta(days=30)


@pytest.fixture
def org(db, client):
    return fr.org(db, client)


def _overtime(org, day: date = DAY, start: str = "18:00", end: str = "20:00", **details) -> dict:
    return {"fromDate": str(day), "reason": "Month end",
            "details": {"departmentId": org.department_id, "startTime": start, "endTime": end, **details}}


def _file_overtime(client, org, who, **kw) -> dict:
    r = client.post("/api/requests/overtime", json=_overtime(org, **kw), headers=who.headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def _approve(client, who, req: dict, **details) -> dict:
    r = client.post(f"/api/requests/approvals/{req['id']}/approve",
                    json={"rowVersion": req["rowVersion"], **({"details": details} if details else {})},
                    headers=who.headers)
    assert r.status_code == 200, r.text
    return r.json()["data"]


# ---------------------------------------------------------------- R1: generate the application text

def test_generate_application_is_unavailable_without_a_model(client, db, org):
    body = {"fromDate": str(DAY), "reason": "Family wedding", "details": {"leaveTypeId": 1}, "tone": "formal"}
    r = client.post("/api/requests/leave/application/generate", json=body, headers=org.staff.headers)
    assert r.status_code == 503 and r.json()["code"] == "AI_UNAVAILABLE"
    r = client.post("/api/requests/transfer/application/generate", json={"tone": "casual"}, headers=org.hr["headers"])
    assert r.status_code == 422
    # The type's create permission guards it.
    nobody = factories.login_as(db, client, org.company_id, role_codes="")
    r = client.post("/api/requests/leave/application/generate", json=body, headers=nobody["headers"])
    assert r.status_code == 403


# ---------------------------------------------------------------- R2: WFH cancellation with times

def test_wfh_cancellation_keeps_dates_and_times(client, db, org):
    slot = fr.time_slot(db, org.company_id)
    start = DAY + timedelta(days=40)
    days = [start, start + timedelta(days=1)]
    for d in days:
        fr.schedule(db, org.company_id, org.staff.employee_id, d, slot)
    r = client.post("/api/requests/work-from-home", headers=org.staff.headers,
                    json={"fromDate": str(start), "toDate": str(days[1]), "reason": "Renovation", "details": {}})
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    for who in (org.manager, org.fa):
        req = _approve(client, who, req)
    assert req["status"] == "approved"

    outside = client.post(f"/api/requests/work-from-home/{req['id']}/cancel", headers=org.staff.headers,
                          json={"reason": "Back", "rowVersion": req["rowVersion"],
                                "dates": [str(start - timedelta(days=5))]})
    assert outside.status_code == 422 and "dates" in outside.json()["fieldErrors"]
    backwards = client.post(f"/api/requests/work-from-home/{req['id']}/cancel", headers=org.staff.headers,
                            json={"reason": "Back", "rowVersion": req["rowVersion"], "startTime": "15:00",
                                  "endTime": "11:00"})
    assert backwards.status_code == 422 and "endTime" in backwards.json()["fieldErrors"]

    r = client.post(f"/api/requests/work-from-home/{req['id']}/cancel", headers=org.staff.headers,
                    json={"reason": "Back at the office", "rowVersion": req["rowVersion"], "dates": [str(days[1])],
                          "startTime": "13:00", "endTime": "17:00"})
    assert r.status_code == 200, r.text
    req = r.json()["data"]
    assert req["status"] == "cancelling"
    assert req["cancelDates"] == [str(days[1])]
    assert req["cancelStartTime"].startswith("13:00") and req["cancelEndTime"].startswith("17:00")
    # Today's behaviour otherwise: the cancellation flow cancels the whole request.
    for who in (org.manager, org.fa):
        req = _approve(client, who, req)
    assert req["status"] == "cancelled" and req["cancelDates"] == [str(days[1])]


def test_cancel_with_times_is_refused_for_other_types(client, db, org):
    ot = _file_overtime(client, org, org.staff)
    r = client.post(f"/api/requests/overtime/{ot['id']}/cancel", headers=org.staff.headers,
                    json={"reason": "No longer needed", "rowVersion": ot["rowVersion"], "startTime": "18:00"})
    assert r.status_code == 422 and "dates" in r.json()["fieldErrors"]

    # The Approvals route does not know the type from its URL: the procedure refuses it. Line managers do
    # not hold requests.approvals.cancel by default: a personal grant.
    fr.execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope) "
                   "SELECT ?, ?, id, N'grant', N'team' FROM auth.permission WHERE code = N'requests.approvals.cancel'",
               org.company_id, org.manager.user_id)
    for who in (org.manager, org.fa):
        ot = _approve(client, who, ot)
    r = client.post(f"/api/requests/approvals/{ot['id']}/cancel", headers=org.manager.headers,
                    json={"reason": "Not worked", "rowVersion": ot["rowVersion"], "dates": [str(DAY)]})
    assert r.status_code == 422 and "dates" in r.json()["fieldErrors"]
    r = client.post(f"/api/requests/approvals/{ot['id']}/cancel", headers=org.manager.headers,
                    json={"reason": "Not worked", "rowVersion": ot["rowVersion"]})
    assert r.status_code == 200, r.text
    assert r.json()["data"]["cancelDates"] is None


# ---------------------------------------------------------------- R3: flowStep filter

def test_flow_step_filter(client, org):
    ot = _file_overtime(client, org, org.staff)
    assert ot["nextApproverKind"] == "line_manager"

    def ids(url, who):
        r = client.get(url, headers=who["headers"] if isinstance(who, dict) else who.headers)
        assert r.status_code == 200, r.text
        return {x["id"] for x in r.json()["data"]}

    assert ot["id"] in ids("/api/requests/overtime?view=all&flowStep=line_manager", org.hr)
    assert ot["id"] not in ids("/api/requests/overtime?view=all&flowStep=hr_manager", org.hr)
    assert ot["id"] in ids("/api/requests/approvals?type=overtime&flowStep=line_manager", org.manager)
    assert ot["id"] not in ids("/api/requests/approvals?type=overtime&flowStep=final_authority", org.manager)
    r = client.get("/api/requests/overtime?view=all&flowStep=nobody", headers=org.hr["headers"])
    assert r.status_code == 422 and "flowStep" in r.json()["fieldErrors"]
    assert client.get("/api/requests/approvals?flowStep=nobody", headers=org.manager.headers).status_code == 422


# ---------------------------------------------------------------- R4: CSV exports

def test_exports_are_csv(client, org):
    assert {f"requests.overtime.{a}" for a in ("view", "create", "cancel", "export")} <= set(CODES)
    _file_overtime(client, org, org.staff)
    r = client.get("/api/requests/overtime/export?view=all", headers=org.hr["headers"])
    assert r.status_code == 200, r.text
    assert r.headers["content-type"].startswith("text/csv")
    assert r.headers["content-disposition"] == f'attachment; filename="overtime-{date.today().isoformat()}.csv"'
    lines = r.text.strip().splitlines()
    assert lines[0].startswith("Code,") and "Overtime date" in lines[0] and len(lines) == 2

    spec = client.get("/openapi.json").json()["paths"]
    exports = [p for p in spec if p.startswith("/api/requests/") and p.endswith("/export")]
    assert len(exports) >= 16
    for p in exports:
        assert list(spec[p]["get"]["responses"]["200"]["content"]) == ["text/csv"], p


# ---------------------------------------------------------------- overtime: bulk filing, bulk approve, policy

def _bulk(org, employees, day: date = DAY, **extra) -> dict:
    return {"employeeIds": employees, "overtimeType": "mandatory", "fromDate": str(day), "reason": "Stock count",
            "details": {"departmentId": org.department_id, "startTime": "18:00", "endTime": "20:00"}, **extra}


def test_bulk_overtime_files_everyone_or_nobody(client, org):
    people = [org.staff.employee_id, org.staff2.employee_id]
    r = client.post("/api/requests/overtime/bulk", json=_bulk(org, people), headers=org.hr["headers"])
    assert r.status_code == 201, r.text
    out = r.json()["data"]
    assert out["count"] == 2 and out["overtimeType"] == "mandatory"
    assert sorted(int(x["employeeId"]) for x in out["requests"]) == sorted(people)
    for x in out["requests"]:
        assert x["details"]["isBulk"] is True and x["details"]["bulkId"] == out["bulkId"]
        assert x["details"]["overtimeType"] == "mandatory" and x["details"]["departmentName"]
        assert x["details"]["appliedMinutes"] == 120 and x["status"] == "pending"

    single = _file_overtime(client, org, org.other, day=DAY + timedelta(days=1))
    assert single["details"]["isBulk"] is False and single["details"]["bulkId"] is None
    listed = client.get("/api/requests/overtime?view=all&bulk=true&pageSize=100", headers=org.hr["headers"]).json()
    assert {x["id"] for x in out["requests"]} <= {x["id"] for x in listed["data"]}
    assert single["id"] not in {x["id"] for x in listed["data"]}
    others = client.get("/api/requests/overtime?view=all&bulk=false&pageSize=100", headers=org.hr["headers"]).json()
    assert single["id"] in {x["id"] for x in others["data"]}

    # Staff already has overtime that day: nobody is filed, and the refusal names them.
    r = client.post("/api/requests/overtime/bulk", json=_bulk(org, [org.other.employee_id, org.staff.employee_id]),
                    headers=org.hr["headers"])
    assert r.status_code == 422 and r.json()["code"] == "BULK_REFUSED"
    assert list(r.json()["fieldErrors"]) == [f"employeeIds.{org.staff.employee_id}"]
    mine = client.get(f"/api/requests/overtime?view=all&employeeId={org.other.employee_id}&from={DAY}&to={DAY}",
                      headers=org.hr["headers"]).json()
    assert mine["meta"]["total"] == 0

    bad = client.post("/api/requests/overtime/bulk", headers=org.hr["headers"],
                      json=_bulk(org, people, toDate=str(DAY + timedelta(days=1))))
    assert bad.status_code == 422 and "toDate" in bad.json()["fieldErrors"]
    # Filing for others needs the create permission to reach them.
    r = client.post("/api/requests/overtime/bulk", json=_bulk(org, [org.other.employee_id], day=DAY + timedelta(3)),
                    headers=org.staff.headers)
    assert r.status_code == 422 and f"employeeIds.{org.other.employee_id}" in r.json()["fieldErrors"]


def test_bulk_approve_with_details_records_the_policy(client, org):
    policy = client.post("/api/attendance/settings/overtime-policies", headers=org.admin["headers"], json={
        "name": f"Daily {org.company_id}", "period": "daily",
        "slabs": [{"minMinutes": 30, "maxMinutes": 90, "encashmentType": "full_day"},
                  {"minMinutes": 91, "maxMinutes": 240, "encashmentType": "full_day"}]})
    assert policy.status_code == 201, policy.text
    policy = policy.json()["data"]
    assert policy["usageCount"] == 0

    a = _file_overtime(client, org, org.staff)
    b = _file_overtime(client, org, org.staff2)
    for who, approved in ((org.manager, 60), (org.fa, None)):
        items = []
        for req in (a, b):
            req = client.get(f"/api/requests/approvals/{req['id']}", headers=who.headers).json()["data"]
            item = {"id": req["id"], "rowVersion": req["rowVersion"]}
            if req["id"] == a["id"] and approved:
                item["details"] = {"approvedMinutes": approved}
            items.append(item)
        r = client.post("/api/requests/approvals/bulk-approve", json={"items": items}, headers=who.headers)
        assert r.status_code == 200, r.text
        assert all(x["ok"] for x in r.json()["data"]), r.text

    a = client.get(f"/api/requests/overtime/{a['id']}", headers=org.staff.headers).json()["data"]
    b = client.get(f"/api/requests/overtime/{b['id']}", headers=org.staff2.headers).json()["data"]
    assert a["status"] == "approved" and a["details"]["approvedMinutes"] == 60
    assert a["details"]["overtimePolicyId"] == policy["id"] and a["details"]["slabMinMinutes"] == 30
    assert a["details"]["encashmentType"] == "full_day" and a["details"]["overtimePolicyName"] == policy["name"]
    # Left out, the approved minutes are the applied ones.
    assert b["details"]["approvedMinutes"] == 120 and b["details"]["slabMinMinutes"] == 91

    got = client.get(f"/api/attendance/settings/overtime-policies/{policy['id']}", headers=org.admin["headers"])
    assert got.json()["data"]["usageCount"] == 2
    listed = client.get("/api/attendance/settings/overtime-policies", headers=org.admin["headers"]).json()["data"]
    assert next(p for p in listed if p["id"] == policy["id"])["usageCount"] == 2
    r = client.delete(f"/api/attendance/settings/overtime-policies/{policy['id']}",
                      params={"rowVersion": got.json()["data"]["rowVersion"]}, headers=org.admin["headers"])
    assert r.status_code == 409 and r.json()["code"] == "IN_USE"

    # Too many approved minutes in a bulk item are refused for that item only.
    c = _file_overtime(client, org, org.other, day=DAY + timedelta(days=2))
    c = client.get(f"/api/requests/approvals/{c['id']}", headers=org.other_manager.headers).json()["data"]
    r = client.post("/api/requests/approvals/bulk-approve", headers=org.other_manager.headers,
                    json={"items": [{"id": c["id"], "rowVersion": c["rowVersion"],
                                     "details": {"approvedMinutes": 500}}]})
    assert r.status_code == 200 and r.json()["data"][0]["ok"] is False
