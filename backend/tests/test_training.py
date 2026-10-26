"""Training: programs and materials, sessions with capacity, nominations and approvals by scope, attendance,
completion against the attendance minimum, certificates (uploaded files), feedback, cancelling a session."""
from datetime import date, timedelta

import pytest

from tests import factories
from tests import factories_performance as fp

TODAY = date.today()


@pytest.fixture
def org(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    manager = fp.person(db, client, company, fp.MANAGER_TRAINING, "team", first_name="Maryam")
    staff = [fp.person(db, client, company, fp.STAFF_TRAINING, "own", first_name=n,
                       line_manager_id=manager["employee_id"]) for n in ("Ali", "Bilal", "Sana")]
    program = fp.program(client, admin["headers"], issuesCertificate=True, certificateValidityMonths=24)
    return {"company": company, "h": admin["headers"], "manager": manager, "staff": staff, "program": program}


def test_programs_and_materials(client, org):
    h, program = org["h"], org["program"]
    assert program["issuesCertificate"] is True and program["materials"] == [] and program["sessions"] == 0
    dup = client.post("/api/training/programs", headers=h, json={"title": program["title"]})
    assert dup.status_code == 409 and dup.json()["code"] == "PROGRAM_DUPLICATE"
    external = client.post("/api/training/programs", headers=h, json={"title": "Outside", "providerType": "external"})
    assert external.status_code == 422 and "providerName" in external.json()["fieldErrors"]

    deck = factories.upload(client, h, "slides.pdf", module="training")
    with_material = fp.ok(client.post(f"/api/training/programs/{program['id']}/materials", headers=h,
                                      json={"fileId": deck["id"], "label": "Slides"}), 201)
    material = with_material["materials"][0]
    assert material["fileId"] == deck["id"] and material["label"] == "Slides" and "/download?token=" in material["url"]
    again = client.post(f"/api/training/programs/{program['id']}/materials", headers=h, json={"fileId": deck["id"]})
    assert again.status_code == 409
    missing = client.post(f"/api/training/programs/{program['id']}/materials", headers=h, json={"fileId": 999999999})
    assert missing.status_code == 422 and "fileId" in missing.json()["fieldErrors"]
    # Staff read programs (and their materials) but cannot change them.
    staff_h = org["staff"][0]["headers"]
    assert fp.ok(client.get(f"/api/training/programs/{program['id']}", headers=staff_h))["materials"][0]["url"]
    assert client.post("/api/training/programs", headers=staff_h, json={"title": "Mine"}).status_code == 403
    assert client.delete(f"/api/training/programs/{program['id']}/materials/{material['id']}",
                         headers=h).status_code == 204


def test_capacity_nominations_and_scope(client, db, org):
    company, h, manager = org["company"], org["h"], org["manager"]
    ali, bilal, sana = org["staff"]
    s = fp.session(client, h, org["program"]["id"], TODAY + timedelta(days=10), TODAY + timedelta(days=11), capacity=2)
    assert s["status"] == "scheduled" and s["seatsLeft"] == 2 and s["title"] == org["program"]["title"]
    assert len(fp.events(db, company, "training.session_scheduled")) == 1

    enrolled = fp.ok(client.post("/api/training/enrolments", headers=h, json={
        "trainingSessionId": s["id"], "employeeIds": [ali["employee_id"], bilal["employee_id"]]}), 201)
    assert {e["status"] for e in enrolled} == {"enrolled"} and {e["nominationSource"] for e in enrolled} == {"hr"}
    assert len(fp.events(db, company, "training.enrolled")) == 2
    assert any(n["title"].startswith("You are enrolled") for n in fp.notifications(db, ali["user_id"]))
    full = client.post("/api/training/enrolments", headers=h, json={"trainingSessionId": s["id"],
                                                                     "employeeIds": [sana["employee_id"]]})
    assert full.status_code == 409 and full.json()["code"] == "SESSION_FULL"

    # Sana nominates herself: it waits for approval, and cannot be approved while the session is full.
    req = fp.ok(client.post("/api/training/enrolments", headers=sana["headers"], json={"trainingSessionId": s["id"]}), 201)[0]
    assert req["status"] == "requested" and req["nominationSource"] == "self"
    assert len(fp.events(db, company, "training.nominated")) == 1
    dup = client.post("/api/training/enrolments", headers=sana["headers"], json={"trainingSessionId": s["id"]})
    assert dup.status_code == 409 and dup.json()["code"] == "ALREADY_NOMINATED"
    no_seat = client.post(f"/api/training/enrolments/{req['id']}/approve", headers=manager["headers"],
                          json={"rowVersion": req["rowVersion"]})
    assert no_seat.status_code == 409 and no_seat.json()["code"] == "SESSION_FULL"
    # Staff cannot approve, even their own nomination.
    assert client.post(f"/api/training/enrolments/{req['id']}/approve", headers=sana["headers"],
                       json={"rowVersion": req["rowVersion"]}).status_code == 403

    # Bilal withdraws; the seat goes to Sana when her manager approves.
    b = next(e for e in enrolled if e["employeeId"] == str(bilal["employee_id"]))
    out = fp.ok(client.post(f"/api/training/enrolments/{b['id']}/withdraw", headers=bilal["headers"],
                            json={"rowVersion": b["rowVersion"]}))
    assert out["status"] == "withdrawn"
    approved = fp.ok(client.post(f"/api/training/enrolments/{req['id']}/approve", headers=manager["headers"],
                                 json={"rowVersion": req["rowVersion"]}))
    assert approved["status"] == "enrolled"
    assert fp.ok(client.get(f"/api/training/sessions/{s['id']}", headers=h))["seatsLeft"] == 0

    # Scope: staff see their own enrolments; the manager sees the team.
    mine = client.get("/api/training/enrolments", headers=sana["headers"], params={"tab": "my"}).json()["data"]
    assert [e["id"] for e in mine] == [req["id"]]
    a = next(e for e in enrolled if e["employeeId"] == str(ali["employee_id"]))
    assert client.get(f"/api/training/enrolments/{a['id']}", headers=sana["headers"]).status_code == 404
    team = client.get("/api/training/enrolments", headers=manager["headers"], params={"tab": "team"}).json()["data"]
    assert {e["employeeId"] for e in team} == {str(ali["employee_id"]), str(bilal["employee_id"]),
                                                str(sana["employee_id"])}
    # Staff cannot nominate a colleague; managers nominate (and wait for approval).
    other = client.post("/api/training/enrolments", headers=sana["headers"], json={
        "trainingSessionId": s["id"], "employeeIds": [ali["employee_id"]]})
    assert other.status_code == 422 and "employeeIds" in other.json()["fieldErrors"]

    stale = client.put(f"/api/training/sessions/{s['id']}", headers=h, json={
        "trainingProgramId": org["program"]["id"], "startDate": s["startDate"], "endDate": s["endDate"],
        "deliveryMode": "classroom", "venue": "Hall", "trainerType": "external", "trainerName": "X", "capacity": 5,
        "rowVersion": "0000000000000001"})
    assert stale.status_code == 409
    current = fp.ok(client.get(f"/api/training/sessions/{s['id']}", headers=h))
    shrink = client.put(f"/api/training/sessions/{s['id']}", headers=h, json={
        "trainingProgramId": org["program"]["id"], "startDate": s["startDate"], "endDate": s["endDate"],
        "deliveryMode": "classroom", "venue": "Hall", "trainerType": "external", "trainerName": "X", "capacity": 1,
        "rowVersion": current["rowVersion"]})
    assert shrink.status_code == 409 and shrink.json()["code"] == "CAPACITY_BELOW_ENROLLED"
    moved = fp.ok(client.put(f"/api/training/sessions/{s['id']}", headers=h, json={
        "trainingProgramId": org["program"]["id"], "startDate": (TODAY + timedelta(days=12)).isoformat(),
        "endDate": (TODAY + timedelta(days=13)).isoformat(), "deliveryMode": "classroom", "venue": "Hall",
        "trainerType": "external", "trainerName": "X", "capacity": 2, "rowVersion": current["rowVersion"]}))
    assert moved["startDate"] == (TODAY + timedelta(days=12)).isoformat()
    assert len(fp.events(db, company, "training.session_rescheduled")) == 1
    assert any(n["title"].startswith("Training session changed") for n in fp.notifications(db, sana["user_id"]))

    # Self-nomination can be switched off.
    settings = fp.ok(client.get("/api/training/settings", headers=h))
    fp.ok(client.put("/api/training/settings", headers=h, json={"minAttendancePercent": 80,
                                                                "allowSelfNomination": False,
                                                                "rowVersion": settings["rowVersion"]}))
    s2 = fp.session(client, h, org["program"]["id"], TODAY + timedelta(days=20), TODAY + timedelta(days=20))
    assert client.post("/api/training/enrolments", headers=bilal["headers"],
                       json={"trainingSessionId": s2["id"]}).status_code == 403

    # Cancelling a session cancels its seats and tells the people on it.
    cancelled = fp.ok(client.post(f"/api/training/sessions/{s['id']}/cancel", headers=h,
                                  json={"reason": "Trainer unavailable", "rowVersion": moved["rowVersion"]}))
    assert cancelled["status"] == "cancelled" and cancelled["seatsTaken"] == 0
    assert any(n["title"].startswith("Training session cancelled") for n in fp.notifications(db, ali["user_id"]))
    assert len(fp.events(db, company, "training.session_cancelled")) == 1


def test_attendance_completion_certificate_and_feedback(client, db, org):
    company, h = org["company"], org["h"]
    ali, bilal, _ = org["staff"]
    start = TODAY - timedelta(days=2)
    s = fp.session(client, h, org["program"]["id"], start, TODAY)
    assert s["sessionDays"] == 3
    rows = fp.ok(client.post("/api/training/enrolments", headers=h, json={
        "trainingSessionId": s["id"], "employeeIds": [ali["employee_id"], bilal["employee_id"]]}), 201)
    e = {r["employeeId"]: r for r in rows}
    ea, eb = e[str(ali["employee_id"])], e[str(bilal["employee_id"])]

    for i in range(3):
        day = start + timedelta(days=i)
        att = fp.ok(client.put(f"/api/training/sessions/{s['id']}/attendance", headers=h, json={
            "attendanceDate": day.isoformat(),
            "marks": [{"enrolmentId": ea["id"], "status": "present"},
                      {"enrolmentId": eb["id"], "status": "present" if i == 0 else "absent"}]}))
    by_person = {p["enrolmentId"]: p for p in att["participants"]}
    assert by_person[ea["id"]]["presentDays"] == 3 and by_person[eb["id"]]["presentDays"] == 1
    assert len(by_person[ea["id"]]["days"]) == 3
    future = client.put(f"/api/training/sessions/{s['id']}/attendance", headers=h, json={
        "attendanceDate": (TODAY + timedelta(days=1)).isoformat(), "marks": [{"enrolmentId": ea["id"], "status": "present"}]})
    assert future.status_code == 422 and "attendanceDate" in future.json()["fieldErrors"]
    assert client.put(f"/api/training/sessions/{s['id']}/attendance", headers=ali["headers"], json={
        "attendanceDate": TODAY.isoformat(), "marks": [{"enrolmentId": ea["id"], "status": "present"}]}).status_code == 403

    # Feedback waits until the training is over for the participant.
    early = client.put(f"/api/training/enrolments/{ea['id']}/feedback", headers=ali["headers"], json={"overallRating": 5})
    assert early.status_code == 409 and early.json()["code"] == "FEEDBACK_EARLY"

    ea = fp.ok(client.get(f"/api/training/enrolments/{ea['id']}", headers=h))
    done = fp.ok(client.post(f"/api/training/enrolments/{ea['id']}/complete", headers=h,
                             json={"score": 88, "remarks": "Passed the assessment", "rowVersion": ea["rowVersion"]}))
    assert done["status"] == "completed" and done["attendancePercent"] == 100 and done["score"] == 88
    assert len(done["attendance"]) == 3
    assert len(fp.events(db, company, "training.completed")) == 1
    eb = fp.ok(client.get(f"/api/training/enrolments/{eb['id']}", headers=h))
    short = client.post(f"/api/training/enrolments/{eb['id']}/complete", headers=h, json={"rowVersion": eb["rowVersion"]})
    assert short.status_code == 409 and short.json()["code"] == "ATTENDANCE_SHORT"
    no_cert = client.put(f"/api/training/enrolments/{eb['id']}/certificate", headers=h, json={
        "fileId": 1, "issuedDate": TODAY.isoformat(), "rowVersion": eb["rowVersion"]})
    assert no_cert.status_code == 409 and no_cert.json()["code"] == "NOT_COMPLETED"

    cert_file = factories.upload(client, h, "certificate.pdf", module="training")
    cert = fp.ok(client.put(f"/api/training/enrolments/{ea['id']}/certificate", headers=h, json={
        "fileId": cert_file["id"], "certificateNo": "TRN-0001", "issuedDate": TODAY.isoformat(),
        "rowVersion": done["rowVersion"]}))
    assert cert["certificate"]["id"] == cert_file["id"] and cert["certificate"]["name"] == "certificate.pdf"
    assert cert["certificateNo"] == "TRN-0001"
    expiry = date.fromisoformat(cert["certificateExpiryDate"])
    assert (expiry.year - TODAY.year) * 12 + expiry.month - TODAY.month == 24
    assert len(fp.events(db, company, "training.certificate_issued")) == 1
    # The participant sees their certificate through a signed link that works without signing in.
    own = fp.ok(client.get(f"/api/training/enrolments/{ea['id']}", headers=ali["headers"]))
    download = client.get(own["certificate"]["url"])
    assert download.status_code == 200 and download.content.startswith(b"%PDF")

    # Only the participant gives feedback on their training.
    assert client.put(f"/api/training/enrolments/{ea['id']}/feedback", headers=h,
                      json={"overallRating": 3}).status_code == 403
    fb = fp.ok(client.put(f"/api/training/enrolments/{ea['id']}/feedback", headers=ali["headers"],
                          json={"overallRating": 5, "trainerRating": 4, "comments": "Very useful"}))
    assert fb["feedback"]["overallRating"] == 5 and fb["feedbackRating"] == 5
    assert len(fp.events(db, company, "training.feedback_submitted")) == 1

    # Closing the session settles the rest by attendance.
    current = fp.ok(client.get(f"/api/training/sessions/{s['id']}", headers=h))
    closed = fp.ok(client.post(f"/api/training/sessions/{s['id']}/complete", headers=h,
                               json={"rowVersion": current["rowVersion"]}))
    assert closed["status"] == "completed" and closed["averageRating"] == 5 and closed["feedbackCount"] == 1
    assert fp.ok(client.get(f"/api/training/enrolments/{eb['id']}", headers=h))["status"] == "not_completed"
    late = client.put(f"/api/training/sessions/{s['id']}/attendance", headers=h, json={
        "attendanceDate": TODAY.isoformat(), "marks": [{"enrolmentId": eb["id"], "status": "present"}]})
    assert late.status_code == 409
    feedback = client.get("/api/training/feedback", headers=h, params={"sessionId": s["id"]}).json()["data"]
    assert [f["comments"] for f in feedback] == ["Very useful"]
    assert client.delete(f"/api/training/sessions/{s['id']}", headers=h,
                         params={"rowVersion": closed["rowVersion"]}).status_code == 409
