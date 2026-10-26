"""Performance: goals (My Performance), their progress and check-ins, scope by tab, the overview, KPIs."""
from datetime import date, timedelta

import pytest

from tests import factories
from tests import factories_performance as fp

TODAY = date.today()


@pytest.fixture
def team(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    manager = fp.person(db, client, company, fp.MANAGER_PERFORMANCE, "team", first_name="Maryam")
    staff = fp.person(db, client, company, fp.STAFF_PERFORMANCE, "own", first_name="Rehan",
                      line_manager_id=manager["employee_id"])
    outsider = fp.person(db, client, company, fp.STAFF_PERFORMANCE, "own", first_name="Omer")
    return {"company": company, "admin": admin["headers"], "manager": manager, "staff": staff, "outsider": outsider}


def test_goal_lifecycle_progress_and_completion(client, db, team):
    h, company = team["staff"]["headers"], team["company"]
    g = fp.goal(client, h, TODAY + timedelta(days=30), title="Close 20 deals", targetValue=20, weight=2)
    assert g["employeeId"] == str(team["staff"]["employee_id"]) and g["status"] == "not_started"
    assert g["progress"] == 0 and g["weight"] == 2 and g["checkIns"] == [] and g["isLocked"] is False

    # Progress follows actual / target.
    upd = fp.ok(client.post(f"/api/performance/goals/{g['id']}/check-ins", headers=h,
                            json={"actualValue": 5, "comments": "First week", "rowVersion": g["rowVersion"]}))
    assert upd["progress"] == 25 and upd["status"] == "in_progress" and upd["actualValue"] == 5
    assert [c["comments"] for c in upd["checkIns"]] == ["First week"]

    # A stale row version is refused.
    stale = client.post(f"/api/performance/goals/{g['id']}/check-ins", headers=h,
                        json={"actualValue": 6, "rowVersion": g["rowVersion"]})
    assert stale.status_code == 409

    # Reaching the target completes the goal and publishes the event once.
    done = fp.ok(client.post(f"/api/performance/goals/{g['id']}/check-ins", headers=h,
                             json={"actualValue": 22, "rowVersion": upd["rowVersion"]}))
    assert done["progress"] == 100 and done["status"] == "completed" and done["completedAt"]
    assert len(done["checkIns"]) == 2
    events = fp.events(db, company, "performance.goal_completed")
    assert len(events) == 1 and events[0]["entity_id"] == int(g["id"])

    # Edit through PUT: status wins over progress when the goal is cancelled.
    put = fp.ok(client.put(f"/api/performance/goals/{g['id']}", headers=h, json={
        "title": "Close 20 deals", "dueDate": (TODAY + timedelta(days=30)).isoformat(), "progress": 40,
        "status": "cancelled", "rowVersion": done["rowVersion"]}))
    assert put["status"] == "cancelled" and put["completedAt"] is None and put["progress"] == 40

    bad = client.post("/api/performance/goals", headers=h, json={"title": "Backwards", "startDate": TODAY.isoformat(),
                                                                 "dueDate": (TODAY - timedelta(days=1)).isoformat()})
    assert bad.status_code == 422 and "dueDate" in bad.json()["fieldErrors"]

    # Staff hold no delete; the manager does, for their team.
    assert client.delete(f"/api/performance/goals/{g['id']}", headers=h,
                         params={"rowVersion": put["rowVersion"]}).status_code == 403
    assert client.delete(f"/api/performance/goals/{g['id']}", headers=team["manager"]["headers"],
                         params={"rowVersion": put["rowVersion"]}).status_code == 204
    assert client.get(f"/api/performance/goals/{g['id']}", headers=h).status_code == 404


def test_goal_scope_by_tab(client, db, team):
    staff, manager, outsider = team["staff"], team["manager"], team["outsider"]
    mine = fp.goal(client, staff["headers"], TODAY + timedelta(days=10))
    late = fp.goal(client, staff["headers"], TODAY - timedelta(days=3), title="Late report")
    theirs = fp.goal(client, outsider["headers"], TODAY + timedelta(days=10))
    # The manager sets a goal for a report.
    set_for = fp.goal(client, manager["headers"], TODAY + timedelta(days=60), employeeId=staff["employee_id"])
    assert set_for["employeeId"] == str(staff["employee_id"])
    # Staff cannot set goals for someone else.
    other = client.post("/api/performance/goals", headers=staff["headers"], json={
        "title": "Not mine", "dueDate": TODAY.isoformat(), "employeeId": outsider["employee_id"]})
    assert other.status_code == 422 and "employeeId" in other.json()["fieldErrors"]

    def ids(headers, **params):
        r = client.get("/api/performance/goals", headers=headers, params=params)
        assert r.status_code == 200, r.text
        return {g["id"] for g in r.json()["data"]}

    assert ids(staff["headers"]) == {mine["id"], late["id"], set_for["id"]}
    assert ids(manager["headers"], tab="team") == {mine["id"], late["id"], set_for["id"]}
    assert ids(manager["headers"], tab="my") == set()
    assert ids(team["admin"]) >= {mine["id"], theirs["id"]}
    assert ids(staff["headers"], overdue="true") == {late["id"]}
    assert client.get(f"/api/performance/goals/{theirs['id']}", headers=manager["headers"]).status_code == 404

    overview = fp.ok(client.get("/api/performance/overview", headers=staff["headers"]))
    assert overview["employeeId"] == str(staff["employee_id"])
    assert overview["goals"]["total"] == 3 and overview["goals"]["overdue"] == 1
    assert overview["upcomingGoals"][0]["id"] == late["id"]
    assert client.get("/api/performance/overview", headers=staff["headers"],
                      params={"employeeId": outsider["employee_id"]}).status_code == 404
    team_view = fp.ok(client.get("/api/performance/overview", headers=manager["headers"],
                                 params={"employeeId": staff["employee_id"]}))
    assert team_view["goals"]["total"] == 3


def test_kpi_library(client, db, team):
    h = team["admin"]
    k = fp.ok(client.post("/api/performance/kpis", headers=h, json={
        "name": "On-time delivery", "keyResultArea": "Delivery", "measureType": "percentage", "targetValue": 95,
        "unit": "%", "defaultWeight": 25}), 201)
    assert k["keyResultArea"] == "Delivery" and k["inUse"] == 0
    dup = client.post("/api/performance/kpis", headers=h, json={"name": "On-time delivery"})
    assert dup.status_code == 409 and dup.json()["code"] == "KPI_DUPLICATE"
    # Staff read the library but cannot change it.
    assert client.get("/api/performance/kpis", headers=team["staff"]["headers"]).status_code == 200
    assert client.post("/api/performance/kpis", headers=team["staff"]["headers"], json={"name": "Mine"}).status_code == 403

    fp.goal(client, team["staff"]["headers"], TODAY + timedelta(days=5), kpiId=k["id"])
    used = fp.ok(client.get(f"/api/performance/kpis/{k['id']}", headers=h))
    assert used["inUse"] == 1
    refused = client.delete(f"/api/performance/kpis/{k['id']}", headers=h, params={"rowVersion": used["rowVersion"]})
    assert refused.status_code == 409 and refused.json()["code"] == "KPI_IN_USE"
