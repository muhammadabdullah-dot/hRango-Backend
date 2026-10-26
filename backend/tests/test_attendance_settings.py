"""Attendance settings: basic and overtime switches, biometric devices and enrolment, IP restrictions,
geo fences and overtime policies. Each test uses a company of its own (settings are company-wide)."""
import pytest

from tests import factories


@pytest.fixture
def setup(db, client):
    company_id = factories.company(db)
    admin = factories.login_as(db, client, company_id, role_codes="company_admin")
    emp = factories.employee(db, company_id)
    staff = factories.login_as(db, client, company_id, role_codes="employee", employee_id=emp)
    return {"company": company_id, "h": admin["headers"], "staff": staff["headers"], "emp": emp}


def test_basic_settings(client, setup):
    h = setup["h"]
    r = client.get("/api/attendance/settings/basic", headers=h)
    assert r.status_code == 200, r.text
    first = r.json()["data"]
    assert first["dashboardPunch"] is False and first["lateGraceMinutes"] == 0 and first["rowVersion"] is None

    body = {**first, "dashboardPunch": True, "lateGraceMinutes": 5, "minimumWorkableMinutes": 240}
    saved = client.put("/api/attendance/settings/basic", json=body, headers=h)
    assert saved.status_code == 200, saved.text
    data = saved.json()["data"]
    assert data["dashboardPunch"] is True and data["lateGraceMinutes"] == 5 and data["rowVersion"]

    stale = client.put("/api/attendance/settings/basic", json=body, headers=h)  # still the first (empty) version
    assert stale.status_code == 409
    again = client.put("/api/attendance/settings/basic", json={**data, "ignorePunchType": True}, headers=h)
    assert again.status_code == 200 and again.json()["data"]["ignorePunchType"] is True

    bad = client.put("/api/attendance/settings/basic", json={**data, "minimumWorkableMinutes": -1}, headers=h)
    assert bad.status_code == 422

    assert client.get("/api/attendance/settings/basic", headers=setup["staff"]).status_code == 403
    assert client.put("/api/attendance/settings/basic", json=body, headers=setup["staff"]).status_code == 403


def test_overtime_settings(client, setup):
    h = setup["h"]
    cur = client.get("/api/attendance/settings/overtime", headers=h).json()["data"]
    r = client.put("/api/attendance/settings/overtime",
                   json={**cur, "overtimeOnCheckOut": True, "encashmentShiftMinutes": 480}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["data"]["overtimeOnCheckOut"] is True and r.json()["data"]["encashmentShiftMinutes"] == 480


def test_device_lifecycle_and_enrolment(client, db, setup):
    h, company_id = setup["h"], setup["company"]
    branch = factories.branch(db, company_id)
    r = client.post("/api/attendance/settings/devices",
                    json={"name": "Main gate", "serialNo": "ZK-001", "ipAddress": "10.0.0.20", "port": 4370,
                          "branchId": str(branch)}, headers=h)
    assert r.status_code == 201, r.text
    dev = r.json()["data"]
    assert dev["code"] == "MCH-00001" and dev["status"] == "active" and dev["enrolledCount"] == 0

    dup = client.post("/api/attendance/settings/devices", json={"name": "Main gate"}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "DEVICE_DUPLICATE"
    bad_ip = client.post("/api/attendance/settings/devices", json={"name": "X", "ipAddress": "10.0.0"}, headers=h)
    assert bad_ip.status_code == 422 and "ipAddress" in bad_ip.json()["fieldErrors"]
    other = client.post("/api/attendance/settings/devices", json={"name": "Back door"}, headers=h).json()["data"]
    assert other["code"] == "MCH-00002"

    emp2 = factories.employee(db, company_id)
    enrol = client.put(f"/api/attendance/settings/devices/{dev['id']}/enrolments",
                       json={"enrolments": [{"employeeId": setup["emp"], "deviceUserNo": "101"},
                                            {"employeeId": emp2, "deviceUserNo": "102"}],
                             "rowVersion": dev["rowVersion"]}, headers=h)
    assert enrol.status_code == 200, enrol.text
    dev = enrol.json()["data"]
    assert dev["enrolledCount"] == 2
    same_no = client.put(f"/api/attendance/settings/devices/{dev['id']}/enrolments",
                         json={"enrolments": [{"employeeId": setup["emp"], "deviceUserNo": "7"},
                                              {"employeeId": emp2, "deviceUserNo": "7"}],
                               "rowVersion": dev["rowVersion"]}, headers=h)
    assert same_no.status_code == 409
    listed = client.get(f"/api/attendance/settings/devices/{dev['id']}/enrolments", headers=h).json()["data"]
    assert sorted(e["deviceUserNo"] for e in listed) == ["101", "102"]

    pushed = client.post(f"/api/attendance/settings/devices/{dev['id']}/punches", json={"lines": [
        {"deviceUserNo": "101", "punchedAt": "2025-04-07T09:01:00", "punchType": "check_in"},
        {"deviceUserNo": "101", "punchedAt": "2025-04-07T09:01:00", "punchType": "check_in"},
        {"deviceUserNo": "999", "punchedAt": "2025-04-07T09:02:00", "punchType": "check_in"},
        {"deviceUserNo": "102", "punchedAt": "07/04/2025 9am", "punchType": "check_in"},
        {"deviceUserNo": "102", "punchedAt": "2025-04-07T17:00:00", "punchType": "lunch"}]}, headers=h)
    assert pushed.status_code == 200, pushed.text
    res = pushed.json()["data"]
    assert (res["created"], res["skipped"], res["failed"]) == (1, 1, 3)
    assert [e["line"] for e in res["errors"]] == [3, 4, 5]
    dev = client.get(f"/api/attendance/settings/devices/{dev['id']}", headers=h).json()["data"]
    assert dev["lastSyncedAt"] is not None

    upd = client.put(f"/api/attendance/settings/devices/{dev['id']}",
                     json={"name": "Main gate", "status": "inactive", "rowVersion": dev["rowVersion"]}, headers=h)
    assert upd.status_code == 200 and upd.json()["data"]["status"] == "inactive"
    stale = client.put(f"/api/attendance/settings/devices/{dev['id']}",
                       json={"name": "Main gate", "rowVersion": dev["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    in_use = client.delete(f"/api/attendance/settings/devices/{dev['id']}",
                           params={"rowVersion": upd.json()["data"]["rowVersion"]}, headers=h)
    assert in_use.status_code == 409 and in_use.json()["code"] == "DEVICE_IN_USE"
    assert client.delete(f"/api/attendance/settings/devices/{other['id']}", params={"rowVersion": other["rowVersion"]},
                         headers=h).status_code == 204
    page = client.get("/api/attendance/settings/devices", params={"q": "gate"}, headers=h).json()
    assert page["meta"]["total"] == 1

    assert client.get("/api/attendance/settings/devices", headers=setup["staff"]).status_code == 403


def test_ip_restrictions(client, db, setup):
    h = setup["h"]
    bad = client.post("/api/attendance/settings/ip-restrictions", json={"ipv4": "300.1.1.1"}, headers=h)
    assert bad.status_code == 422 and "ipv4" in bad.json()["fieldErrors"]
    none = client.post("/api/attendance/settings/ip-restrictions", json={}, headers=h)
    assert none.status_code == 422
    rng = client.post("/api/attendance/settings/ip-restrictions",
                      json={"rangeStart": "10.0.0.20", "rangeEnd": "10.0.0.10"}, headers=h)
    assert rng.status_code == 422 and "rangeEnd" in rng.json()["fieldErrors"]
    no_targets = client.post("/api/attendance/settings/ip-restrictions",
                             json={"ipv4": "192.168.2.0", "appliesToAll": False}, headers=h)
    assert no_targets.status_code == 422 and "targets" in no_targets.json()["fieldErrors"]

    r = client.post("/api/attendance/settings/ip-restrictions",
                    json={"ipv4": "192.168.2.0", "netmask": "255.255.255.0", "appliesToAll": False,
                          "targets": [{"targetType": "employee", "targetId": setup["emp"]},
                                      {"targetType": "religion", "targetValue": "Islam"}]}, headers=h)
    assert r.status_code == 201, r.text
    ipr = r.json()["data"]
    assert ipr["code"] == "IPR-00001" and ipr["addressCount"] == 256 and len(ipr["targets"]) == 2

    upd = client.put(f"/api/attendance/settings/ip-restrictions/{ipr['id']}",
                     json={"ipv4": "192.168.2.38/31", "isActive": False, "rowVersion": ipr["rowVersion"]}, headers=h)
    assert upd.status_code == 200, upd.text
    assert upd.json()["data"]["addressCount"] == 2 and upd.json()["data"]["targets"] == []
    lst = client.get("/api/attendance/settings/ip-restrictions", params={"isActive": "false"}, headers=h).json()
    assert lst["meta"]["total"] == 1 and lst["data"][0]["targets"] is None
    assert client.delete(f"/api/attendance/settings/ip-restrictions/{ipr['id']}",
                         params={"rowVersion": ipr["rowVersion"]}, headers=h).status_code == 409
    assert client.delete(f"/api/attendance/settings/ip-restrictions/{ipr['id']}",
                         params={"rowVersion": upd.json()["data"]["rowVersion"]}, headers=h).status_code == 204


def test_geo_fences(client, setup):
    h = setup["h"]
    poly = client.post("/api/attendance/settings/geo-fences",
                       json={"name": "Yard", "shape": "polygon", "polygonPoints": [{"lat": 1, "lng": 1}, {"lat": 2, "lng": 2}]},
                       headers=h)
    assert poly.status_code == 422 and "polygonPoints" in poly.json()["fieldErrors"]
    circle_no_centre = client.post("/api/attendance/settings/geo-fences",
                                   json={"name": "Yard", "shape": "circle", "radiusM": 100}, headers=h)
    assert circle_no_centre.status_code == 422

    r = client.post("/api/attendance/settings/geo-fences",
                    json={"name": "Head office", "shape": "circle", "centerLat": 24.8607, "centerLng": 67.0011,
                          "radiusM": 200, "isForShift": True}, headers=h)
    assert r.status_code == 201, r.text
    gf = r.json()["data"]
    assert gf["code"] == "GF-00001" and gf["radiusM"] == 200 and gf["polygonPoints"] is None

    dup = client.post("/api/attendance/settings/geo-fences",
                      json={"name": "Head office", "shape": "circle", "centerLat": 1, "centerLng": 1, "radiusM": 5},
                      headers=h)
    assert dup.status_code == 409

    pts = [{"lat": 24.0, "lng": 67.0}, {"lat": 24.0, "lng": 67.1}, {"lat": 24.1, "lng": 67.1}]
    upd = client.put(f"/api/attendance/settings/geo-fences/{gf['id']}",
                     json={"name": "Head office", "shape": "polygon", "polygonPoints": pts, "rowVersion": gf["rowVersion"],
                           "appliesToAll": False, "targets": [{"targetType": "branch", "targetId": 1}]}, headers=h)
    assert upd.status_code == 200, upd.text
    data = upd.json()["data"]
    assert data["shape"] == "polygon" and len(data["polygonPoints"]) == 3 and data["centerLat"] is None
    assert client.get("/api/attendance/settings/geo-fences", params={"isForShift": "false"},
                      headers=h).json()["meta"]["total"] == 1
    assert client.delete(f"/api/attendance/settings/geo-fences/{gf['id']}", params={"rowVersion": data["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"/api/attendance/settings/geo-fences/{gf['id']}", headers=h).status_code == 404


def test_overtime_policies(client, db, setup):
    h = setup["h"]
    from tests import factories_attendance as fa
    casual = fa.leave_type(db, setup["company"])
    overlap = client.post("/api/attendance/settings/overtime-policies", json={
        "name": "Daily", "period": "daily", "slabs": [
            {"minMinutes": 0, "maxMinutes": 120, "encashmentType": "full_day"},
            {"minMinutes": 100, "maxMinutes": 200, "encashmentType": "full_day"}]}, headers=h)
    assert overlap.status_code == 422 and "slabs" in overlap.json()["fieldErrors"]
    no_leave = client.post("/api/attendance/settings/overtime-policies", json={
        "name": "Daily", "period": "daily", "slabs": [{"minMinutes": 0, "maxMinutes": 60, "encashmentType": "leave"}]},
        headers=h)
    assert no_leave.status_code == 422

    r = client.post("/api/attendance/settings/overtime-policies", json={
        "name": "Daily", "period": "daily", "slabs": [
            {"minMinutes": 240, "maxMinutes": 479, "encashmentType": "leave", "leaveTypeId": casual},
            {"minMinutes": 480, "maxMinutes": 960, "encashmentType": "full_day"}]}, headers=h)
    assert r.status_code == 201, r.text
    pol = r.json()["data"]
    assert pol["slabCount"] == 2 and pol["slabs"][0]["leaveTypeId"] == str(casual)

    dup = client.post("/api/attendance/settings/overtime-policies", json={"name": "Daily", "period": "monthly"}, headers=h)
    assert dup.status_code == 409
    upd = client.put(f"/api/attendance/settings/overtime-policies/{pol['id']}",
                     json={"name": "Daily", "period": "monthly", "rowVersion": pol["rowVersion"], "slabs": []}, headers=h)
    assert upd.status_code == 200 and upd.json()["data"]["slabCount"] == 0
    stale = client.put(f"/api/attendance/settings/overtime-policies/{pol['id']}",
                       json={"name": "Daily", "period": "daily", "rowVersion": pol["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    assert client.get("/api/attendance/settings/overtime-policies", headers=h).json()["meta"]["total"] == 1
    assert client.delete(f"/api/attendance/settings/overtime-policies/{pol['id']}",
                         params={"rowVersion": upd.json()["data"]["rowVersion"]}, headers=h).status_code == 204
    assert client.get("/api/attendance/settings/overtime-policies", headers=setup["staff"]).status_code == 403
