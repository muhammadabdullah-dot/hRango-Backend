"""Performance: rating scales and forms, an appraisal cycle from draft to closed, self and manager reviews
with the weighted score, finalising with an increment, and the increment applied as payroll's salary revision."""
from datetime import date, timedelta

import pytest

from tests import factories
from tests import factories_performance as fp

TODAY = date.today()
START, END = date(TODAY.year, 1, 1), date(TODAY.year, 12, 31)


@pytest.fixture
def org(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    manager = fp.person(db, client, company, fp.MANAGER_PERFORMANCE, "team", first_name="Maryam")
    staff = fp.person(db, client, company, fp.STAFF_PERFORMANCE, "own", first_name="Rehan",
                      line_manager_id=manager["employee_id"])
    scale = fp.scale(client, admin["headers"])
    form = fp.form(client, admin["headers"], scale["id"])
    return {"company": company, "admin": admin, "h": admin["headers"], "manager": manager, "staff": staff,
            "scale": scale, "form": form}


def test_settings_rules(client, org):
    h, scale = org["h"], org["scale"]
    assert scale["minScore"] == 1 and scale["maxScore"] == 5 and [x["label"] for x in scale["levels"]][0] == "Unsatisfactory"
    same = client.post("/api/performance/rating-scales", headers=h, json={
        "name": "Broken", "levels": [{"score": 1, "label": "A"}, {"score": 1, "label": "B"}]})
    assert same.status_code == 422 and "levels" in same.json()["fieldErrors"]

    weights = client.post("/api/performance/forms", headers=h, json={
        "name": "Bad weights", "ratingScaleId": scale["id"], "goalsWeight": 10, "criteria": [{"name": "A", "weight": 50}]})
    assert weights.status_code == 422 and "criteria" in weights.json()["fieldErrors"]
    form = org["form"]
    assert [c["weight"] for c in form["criteria"]] == [50, 30] and form["goalsWeight"] == 20 and form["isLocked"] is False

    used = client.delete(f"/api/performance/rating-scales/{scale['id']}", headers=h,
                         params={"rowVersion": scale["rowVersion"]})
    assert used.status_code == 409 and used.json()["code"] == "SCALE_IN_USE"
    # Staff do not reach settings.
    assert client.get("/api/performance/forms", headers=org["staff"]["headers"]).status_code == 403


def test_appraisal_cycle_reviews_and_increment(client, db, org):
    company, h = org["company"], org["h"]
    staff, manager = org["staff"], org["manager"]
    fp.salary(db, staff["employee_id"], 100000, START - timedelta(days=200))
    # Goals that count: weighted achievement (1 x 100% + 1 x 50%) / 2 = 75% -> 4.00 on a 1-5 scale.
    g1 = fp.goal(client, staff["headers"], START + timedelta(days=60), progress=100)
    fp.goal(client, staff["headers"], START + timedelta(days=90), progress=50)

    cyc = fp.cycle(client, h, org["form"]["id"], START, END, selfReviewDueDate=(END - timedelta(days=20)).isoformat())
    assert cyc["status"] == "draft" and cyc["participants"] == 0
    early = client.post(f"/api/performance/cycles/{cyc['id']}/launch", headers=h, json={"rowVersion": cyc["rowVersion"]})
    assert early.status_code == 409 and early.json()["code"] == "NO_PARTICIPANTS"

    added = fp.ok(client.post(f"/api/performance/cycles/{cyc['id']}/participants", headers=h,
                              json={"employeeIds": [staff["employee_id"]]}))
    assert added["added"] == 1 and added["cycle"]["participants"] == 1
    again = fp.ok(client.post(f"/api/performance/cycles/{cyc['id']}/participants", headers=h,
                              json={"employeeIds": [staff["employee_id"]]}))
    assert again["added"] == 0
    launched = fp.ok(client.post(f"/api/performance/cycles/{cyc['id']}/launch", headers=h,
                                 json={"rowVersion": again["cycle"]["rowVersion"]}))
    assert launched["status"] == "active" and launched["selfReview"] == 1
    assert len(fp.events(db, company, "performance.cycle_launched")) == 1
    assert any(n["title"].startswith("Your appraisal is open") for n in fp.notifications(db, staff["user_id"]))
    # The form of a launched cycle is locked.
    locked = fp.ok(client.get(f"/api/performance/forms/{org['form']['id']}", headers=h))
    assert locked["isLocked"] is True

    mine = client.get("/api/performance/reviews", headers=staff["headers"]).json()["data"]
    assert len(mine) == 1 and mine[0]["status"] == "self_review"
    a = fp.ok(client.get(f"/api/performance/reviews/{mine[0]['id']}", headers=staff["headers"]))
    assert a["reviewerEmployeeId"] == str(manager["employee_id"]) and len(a["goals"]) == 2
    crit = {c["name"]: c["criterionId"] for c in a["ratings"]}

    # The manager cannot rate before the self review is in; staff cannot rate as a manager.
    assert client.put(f"/api/performance/reviews/{a['id']}/manager", headers=manager["headers"],
                      json={"ratings": [], "rowVersion": a["rowVersion"]}).status_code == 409
    assert client.put(f"/api/performance/reviews/{a['id']}/manager", headers=staff["headers"],
                      json={"ratings": [], "rowVersion": a["rowVersion"]}).status_code == 403

    out_of_scale = client.put(f"/api/performance/reviews/{a['id']}/self", headers=staff["headers"], json={
        "ratings": [{"criterionId": crit["Teamwork"], "rating": 7}], "rowVersion": a["rowVersion"]})
    assert out_of_scale.status_code == 422
    draft = fp.ok(client.put(f"/api/performance/reviews/{a['id']}/self", headers=staff["headers"], json={
        "ratings": [{"criterionId": crit["Quality of work"], "rating": 5}], "rowVersion": a["rowVersion"]}))
    assert draft["status"] == "self_review"
    incomplete = client.put(f"/api/performance/reviews/{a['id']}/self", headers=staff["headers"], json={
        "ratings": [], "submit": True, "rowVersion": draft["rowVersion"]})
    assert incomplete.status_code == 422 and "ratings" in incomplete.json()["fieldErrors"]
    # The manager does not see a self review still in draft.
    peek = fp.ok(client.get(f"/api/performance/reviews/{a['id']}", headers=manager["headers"]))
    assert all(r["selfRating"] is None for r in peek["ratings"])

    submitted = fp.ok(client.put(f"/api/performance/reviews/{a['id']}/self", headers=staff["headers"], json={
        "ratings": [{"criterionId": crit["Teamwork"], "rating": 4}], "comments": "A good year", "submit": True,
        "rowVersion": draft["rowVersion"]}))
    # Self: (50 x 5 + 30 x 4 + 20 x 4.00) / 100 = 4.50.
    assert submitted["status"] == "manager_review" and submitted["goalsScore"] == 4 and submitted["selfScore"] == 4.5
    review_events = fp.events(db, company, "performance.review_submitted")
    assert len(review_events) == 1 and '"stage":"self"' in review_events[0]["payload"]
    assert any(n["title"].startswith("Self review submitted") for n in fp.notifications(db, manager["user_id"]))

    rated = fp.ok(client.put(f"/api/performance/reviews/{a['id']}/manager", headers=manager["headers"], json={
        "ratings": [{"criterionId": crit["Quality of work"], "rating": 4}, {"criterionId": crit["Teamwork"], "rating": 3}],
        "comments": "Solid", "developmentNeeds": "Negotiation skills", "submit": True,
        "rowVersion": submitted["rowVersion"]}))
    # Manager: (50 x 4 + 30 x 3 + 20 x 4.00) / 100 = 3.70.
    assert rated["status"] == "reviewed" and rated["managerScore"] == 3.7 and rated["developmentNeeds"] == "Negotiation skills"
    # The employee does not see the manager's ratings before the appraisal is final.
    own = fp.ok(client.get(f"/api/performance/reviews/{a['id']}", headers=staff["headers"]))
    assert own["managerScore"] is None and all(r["managerRating"] is None for r in own["ratings"])

    # Finalising: staff and managers do not hold approve; an increment needs its figures.
    assert client.post(f"/api/performance/appraisals/{a['id']}/finalise", headers=manager["headers"],
                       json={"outcome": "no_change", "rowVersion": rated["rowVersion"]}).status_code == 403
    missing = client.post(f"/api/performance/appraisals/{a['id']}/finalise", headers=h,
                          json={"outcome": "increment", "rowVersion": rated["rowVersion"]})
    assert missing.status_code == 422 and "increment" in missing.json()["fieldErrors"]
    letter = factories.upload(client, h, "appraisal-letter.pdf", module="performance")
    effective = date(TODAY.year + 1, 1, 1)
    final = fp.ok(client.post(f"/api/performance/appraisals/{a['id']}/finalise", headers=h, json={
        "outcome": "increment", "finalComments": "Well done", "letterFileId": letter["id"],
        "increment": {"changeType": "percent", "changeValue": 10, "effectiveDate": effective.isoformat()},
        "rowVersion": rated["rowVersion"]}))
    assert final["status"] == "finalised" and final["finalScore"] == 3.7
    assert final["finalRatingLabel"] == "Exceeds expectations"
    assert final["letterFile"]["id"] == letter["id"] and "/download?token=" in final["letterFile"]["url"]
    assert final["increment"]["changeType"] == "percent" and final["increment"]["status"] == "proposed"
    assert len(fp.events(db, company, "performance.appraisal_finalised")) == 1
    assert len(fp.events(db, company, "performance.increment_proposed")) == 1
    assert any(n["title"].startswith("Your appraisal is final") for n in fp.notifications(db, staff["user_id"]))
    # Now the employee sees the outcome; the goals that counted are locked.
    own = fp.ok(client.get(f"/api/performance/reviews/{a['id']}", headers=staff["headers"]))
    assert own["managerScore"] == 3.7 and own["finalRatingLabel"] == "Exceeds expectations"
    g1_now = fp.ok(client.get(f"/api/performance/goals/{g1['id']}", headers=staff["headers"]))
    assert g1_now["isLocked"] is True
    blocked = client.post(f"/api/performance/goals/{g1['id']}/check-ins", headers=staff["headers"],
                          json={"progress": 90, "rowVersion": g1_now["rowVersion"]})
    assert blocked.status_code == 409 and blocked.json()["code"] == "GOAL_LOCKED"

    # The increment hand-off: payroll's salary revision is written when the increment is applied.
    incs = client.get("/api/performance/increments", headers=h, params={"cycleId": cyc["id"]}).json()["data"]
    assert len(incs) == 1 and incs[0]["currentSalary"] == 100000 and incs[0]["proposedSalary"] == 110000
    # Increments are sensitive: the employee does not see them.
    assert client.get("/api/performance/increments", headers=staff["headers"]).status_code == 403
    applied = fp.ok(client.post(f"/api/performance/increments/{incs[0]['id']}/apply", headers=h,
                                json={"rowVersion": incs[0]["rowVersion"]}))
    assert applied["status"] == "applied" and applied["employeeSalaryId"]
    sal = fp.rows(db, "SELECT amount, previous_amount, change_type, change_value, effective_date, source "
                      "FROM hr.employee_salary WHERE id = ?", int(applied["employeeSalaryId"]))[0]
    assert float(sal["amount"]) == 110000 and float(sal["previous_amount"]) == 100000
    assert sal["change_type"] == "percent" and sal["effective_date"] == effective and sal["source"] == "revision"
    assert len(fp.events(db, company, "performance.increment_applied")) == 1
    twice = client.post(f"/api/performance/increments/{incs[0]['id']}/apply", headers=h,
                        json={"rowVersion": applied["rowVersion"]})
    assert twice.status_code == 409

    closed = fp.ok(client.post(f"/api/performance/cycles/{cyc['id']}/close", headers=h,
                               json={"rowVersion": fp.ok(client.get(f"/api/performance/cycles/{cyc['id']}",
                                                                    headers=h))["rowVersion"]}))
    assert closed["status"] == "closed" and closed["finalised"] == 1

    overview = fp.ok(client.get("/api/performance/overview", headers=staff["headers"]))
    assert overview["appraisals"][0]["finalRatingLabel"] == "Exceeds expectations"


def test_cycle_rules_and_scope(client, db, org):
    company, h = org["company"], org["h"]
    staff, manager = org["staff"], org["manager"]
    outsider = fp.person(db, client, company, fp.STAFF_PERFORMANCE, "own", first_name="Omer")
    cyc = fp.cycle(client, h, org["form"]["id"], START, END)
    dup = client.post("/api/performance/cycles", headers=h, json={
        "name": cyc["name"], "appraisalFormId": org["form"]["id"], "startDate": START.isoformat(), "endDate": END.isoformat()})
    assert dup.status_code == 409 and dup.json()["code"] == "CYCLE_DUPLICATE"
    stale = client.put(f"/api/performance/cycles/{cyc['id']}", headers=h, json={
        "name": "Renamed", "appraisalFormId": org["form"]["id"], "startDate": START.isoformat(),
        "endDate": END.isoformat(), "rowVersion": "0000000000000001"})
    assert stale.status_code == 409

    fp.ok(client.post(f"/api/performance/cycles/{cyc['id']}/participants", headers=h,
                      json={"employeeIds": [staff["employee_id"], outsider["employee_id"]]}))
    cyc = fp.ok(client.get(f"/api/performance/cycles/{cyc['id']}", headers=h))
    cyc = fp.ok(client.post(f"/api/performance/cycles/{cyc['id']}/launch", headers=h, json={"rowVersion": cyc["rowVersion"]}))
    moved = client.put(f"/api/performance/cycles/{cyc['id']}", headers=h, json={
        "name": cyc["name"], "appraisalFormId": org["form"]["id"], "startDate": START.isoformat(),
        "endDate": (END + timedelta(days=1)).isoformat(), "rowVersion": cyc["rowVersion"]})
    assert moved.status_code == 409 and moved.json()["code"] == "CYCLE_LAUNCHED"
    assert client.delete(f"/api/performance/cycles/{cyc['id']}", headers=h,
                         params={"rowVersion": cyc["rowVersion"]}).status_code == 409

    # The manager sees their report's appraisal only; staff see only their own.
    team_tab = client.get("/api/performance/reviews", headers=manager["headers"], params={"tab": "team"}).json()["data"]
    assert [r["employeeId"] for r in team_tab] == [str(staff["employee_id"])]
    all_tab = client.get("/api/performance/reviews", headers=manager["headers"], params={"tab": "all"}).json()["data"]
    assert [r["employeeId"] for r in all_tab] == [str(staff["employee_id"])]
    theirs = client.get("/api/performance/reviews", headers=h, params={"tab": "all"}).json()["data"]
    outsider_appraisal = next(r for r in theirs if r["employeeId"] == str(outsider["employee_id"]))
    assert client.get(f"/api/performance/reviews/{outsider_appraisal['id']}", headers=staff["headers"]).status_code == 404
    # Nobody writes someone else's self review.
    assert client.put(f"/api/performance/reviews/{outsider_appraisal['id']}/self", headers=h, json={
        "ratings": [], "rowVersion": outsider_appraisal["rowVersion"]}).status_code == 403

    # Closing waits for every appraisal; an untouched one can be removed.
    refused = client.post(f"/api/performance/cycles/{cyc['id']}/close", headers=h, json={"rowVersion": cyc["rowVersion"]})
    assert refused.status_code == 409 and refused.json()["code"] == "APPRAISALS_OPEN"
    assert client.delete(f"/api/performance/appraisals/{outsider_appraisal['id']}", headers=h,
                         params={"rowVersion": outsider_appraisal["rowVersion"]}).status_code == 204
