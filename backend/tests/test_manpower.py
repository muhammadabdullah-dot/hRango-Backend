"""Manpower planning: E-Budget Settings, plans with priced lines, e-budget approval into open positions,
validation, permissions, department scope and row versions."""
from tests import factories
from tests import factories_events as fe
from tests import factories_manpower as mpf

API = "/api/manpower"


def test_budget_durations_keep_one_current(client, db, company, admin):
    h = admin["headers"]
    first = mpf.duration(client, h, "2030-01-01", "2030-12-31", current=True)
    second = mpf.duration(client, h, "2031-01-01", "2031-12-31", current=True)
    assert second["isCurrent"] is True
    stale_first = first
    first = client.get(f"{API}/budget-durations/{first['id']}", headers=h).json()["data"]
    assert first["isCurrent"] is False and first["rowVersion"] != stale_first["rowVersion"]
    current = client.get(f"{API}/budget-durations", params={"isCurrent": "true", "pageSize": 100}, headers=h).json()
    assert [d["id"] for d in current["data"]] == [second["id"]]

    dup = client.post(f"{API}/budget-durations", json={"name": first["name"], "startDate": "2030-01-01",
                                                        "endDate": "2030-12-31"}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "BUDGET_DURATION_DUPLICATE"
    backwards = client.post(f"{API}/budget-durations", json={"name": f"Bad {factories.tag()}", "startDate": "2030-12-31",
                                                              "endDate": "2030-01-01"}, headers=h)
    assert backwards.status_code == 422 and "endDate" in backwards.json()["fieldErrors"]

    # Making the first current again moves the flag back; a stale row version is refused.
    edited = client.put(f"{API}/budget-durations/{first['id']}",
                        json={"name": first["name"], "startDate": "2030-01-01", "endDate": "2030-12-31",
                              "isCurrent": True, "rowVersion": first["rowVersion"]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["isCurrent"] is True
    assert client.get(f"{API}/budget-durations/{second['id']}", headers=h).json()["data"]["isCurrent"] is False
    stale = client.put(f"{API}/budget-durations/{first['id']}",
                       json={"name": "x", "startDate": "2030-01-01", "endDate": "2030-12-31",
                             "rowVersion": stale_first["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    no_rv = client.delete(f"{API}/budget-durations/{second['id']}", headers=h)
    assert no_rv.status_code == 422
    second = client.get(f"{API}/budget-durations/{second['id']}", headers=h).json()["data"]
    assert client.delete(f"{API}/budget-durations/{second['id']}", params={"rowVersion": second["rowVersion"]},
                         headers=h).status_code == 204


def test_positions_bands_and_import(client, db, company, admin):
    h = admin["headers"]
    title_name = f"Accountant {factories.tag()}"
    jt = mpf.job_title(db, company, title_name)
    branch = factories.branch(db, company)
    group = mpf.employee_group(db, company)
    dept = factories.department(db, company)
    sub = factories.department(db, company, parent_id=dept)

    pos = mpf.position(client, h, jt, branch, group, dept, 90000, 120000, subDepartmentId=str(sub))
    assert pos["code"].startswith("POS-") and pos["jobTitleName"] == title_name
    assert (pos["minSalary"], pos["maxSalary"]) == (90000, 120000)
    assert pos["subDepartmentId"] == str(sub)

    other_sub = factories.department(db, company)
    wrong = client.post(f"{API}/positions", json={"jobTitleId": jt, "branchId": branch, "employeeGroupId": group,
                                                  "departmentId": dept, "subDepartmentId": other_sub,
                                                  "minSalary": 1, "maxSalary": 2}, headers=h)
    assert wrong.status_code == 422 and "subDepartmentId" in wrong.json()["fieldErrors"]
    upside_down = client.post(f"{API}/positions", json={"jobTitleId": jt, "branchId": branch, "employeeGroupId": group,
                                                        "minSalary": 5, "maxSalary": 2}, headers=h)
    assert upside_down.status_code == 422 and "maxSalary" in upside_down.json()["fieldErrors"]
    dup = client.post(f"{API}/positions", json={"code": pos["code"], "jobTitleId": jt, "branchId": branch,
                                                "employeeGroupId": group, "minSalary": 1, "maxSalary": 2}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "POSITION_DUPLICATE"

    # A band for later keeps today's band in force; the history lists both.
    ranges = client.post(f"{API}/positions/{pos['id']}/salary-ranges",
                         json={"effectiveDate": "2099-01-01", "minSalary": 95000, "maxSalary": 130000}, headers=h)
    assert ranges.status_code == 201 and [r["maxSalary"] for r in ranges.json()["data"]] == [130000, 120000]
    assert client.get(f"{API}/positions/{pos['id']}", headers=h).json()["data"]["maxSalary"] == 120000

    edited = client.put(f"{API}/positions/{pos['id']}",
                        json={"code": pos["code"], "jobTitleId": jt, "branchId": branch, "employeeGroupId": group,
                              "departmentId": dept, "status": "inactive", "minSalary": 100000, "maxSalary": 125000,
                              "rowVersion": pos["rowVersion"]}, headers=h)
    assert edited.status_code == 200
    assert edited.json()["data"]["status"] == "inactive" and edited.json()["data"]["maxSalary"] == 125000
    stale = client.put(f"{API}/positions/{pos['id']}",
                       json={"jobTitleId": jt, "branchId": branch, "employeeGroupId": group, "minSalary": 1,
                             "maxSalary": 2, "rowVersion": pos["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    branch_name = client.get(f"{API}/positions/{pos['id']}", headers=h).json()["data"]["branchName"]
    group_name = edited.json()["data"]["employeeGroupName"]
    code = f"IMP-{factories.tag()}"
    rows = [
        {"code": code, "positionTitle": title_name, "station": branch_name, "employeeGroup": group_name,
         "minSalary": "50,000", "maxSalary": 70000},
        {"positionTitle": title_name, "station": branch_name, "employeeGroup": group_name, "reportsTo": code,
         "minSalary": 40000, "maxSalary": 60000},
        {"positionTitle": "No such title", "station": branch_name, "employeeGroup": group_name,
         "minSalary": 1, "maxSalary": 2},
        {"code": code, "positionTitle": title_name, "station": branch_name, "employeeGroup": group_name,
         "minSalary": 1, "maxSalary": 2},
    ]
    result = client.post(f"{API}/positions/import", json={"rows": rows}, headers=h)
    assert result.status_code == 200, result.text
    data = result.json()["data"]
    assert data["created"] == 2
    assert [(e["rowNo"], e["field"]) for e in data["errors"]] == [(3, "positionTitle"), (4, "code")]
    imported = client.get(f"{API}/positions", params={"q": code}, headers=h).json()["data"]
    assert len(imported) == 1 and imported[0]["minSalary"] == 50000
    child = client.get(f"{API}/positions", params={"jobTitleId": jt, "pageSize": 100}, headers=h).json()["data"]
    assert any(p["reportsToCode"] == code for p in child)

    titles = client.get(f"{API}/position-titles", params={"q": title_name}, headers=h).json()["data"]
    assert titles[0]["positionCount"] == 3


def _plan_setup(client, db, company, admin):
    h = admin["headers"]
    duration = mpf.duration(client, h, "2032-01-01", "2032-12-31")
    branch = factories.branch(db, company)
    group = mpf.employee_group(db, company)
    dept_a = factories.department(db, company, name=f"Finance {factories.tag()}")
    jt_a = mpf.job_title(db, company)
    jt_b = mpf.job_title(db, company)
    pos = mpf.position(client, h, jt_a, branch, group, dept_a, 100000, 150000)
    person = factories.employee(db, company, branch_id=branch, department_id=dept_a)
    mpf.employee_details(db, person, job_title_id=jt_b)
    mpf.salary(db, person, 80000)
    return {"duration": duration, "branch": branch, "dept": dept_a, "position": pos, "person": person,
            "jt_a": jt_a, "jt_b": jt_b}


def _plan_body(s: dict, **extra) -> dict:
    return {"title": f"Plan {factories.tag()}", "budgetDurationId": s["duration"]["id"], "departmentId": s["dept"],
            "branchId": s["branch"], "lines": [
                {"kind": "new_position", "positionId": s["position"]["id"], "headcount": 2,
                 "startDate": "2032-01-01", "endDate": "2032-06-30", "totalAllowance": 10000},
                {"kind": "existing_employee", "employeeId": s["person"], "startDate": "2032-01-01",
                 "endDate": "2032-12-31", "totalAllowance": 5000},
            ], **extra}


def test_plan_totals_budgets_and_approval_flow(client, db, company, admin):
    h = admin["headers"]
    s = _plan_setup(client, db, company, admin)

    outside = _plan_body(s)
    outside["lines"][0]["endDate"] = "2033-01-31"
    bad = client.post(f"{API}/plans", json=outside, headers=h)
    assert bad.status_code == 422 and "lines[0].endDate" in bad.json()["fieldErrors"]
    empty = client.post(f"{API}/plans", json={**_plan_body(s), "lines": []}, headers=h)
    assert empty.status_code == 422 and "lines" in empty.json()["fieldErrors"]

    # A planner submits the plan with its files; the administrator decides the budgets.
    planner = factories.login_as(db, client, company, role_codes="company_admin")
    sheet = factories.upload(client, planner["headers"], name="Headcount plan.xlsx", content=b"PK\x03\x04plan",
                             module="manpower")
    foreign = factories.upload(client, factories.login_as(db, client, factories.company(db),
                                                          role_codes="company_admin")["headers"], module="manpower")
    wrong = client.post(f"{API}/plans", json={**_plan_body(s), "fileIds": [int(foreign["id"])]}, headers=planner["headers"])
    assert wrong.status_code == 422 and "fileIds" in wrong.json()["fieldErrors"]
    r = client.post(f"{API}/plans", json={**_plan_body(s), "fileIds": [int(sheet["id"])]}, headers=planner["headers"])
    assert r.status_code == 201, r.text
    plan = r.json()["data"]
    assert [x["name"] for x in plan["files"]] == ["Headcount plan.xlsx"]
    assert client.get(plan["files"][0]["url"]).content == b"PK\x03\x04plan"
    new_line, old_line = plan["lines"]
    # New position: (max 150,000 + allowance 10,000) x 2 a month, for 6 months.
    assert (new_line["maxSalary"], new_line["totalSalary"], new_line["months"], new_line["annualGross"]) == \
        (150000, 320000, 6, 1920000)
    # Existing employee: salary from hr.employee_salary 80,000 + 5,000, for 12 months.
    assert (old_line["monthlySalary"], old_line["totalSalary"], old_line["annualGross"]) == (80000, 85000, 1020000)
    assert (plan["monthlyAmount"], plan["annualAmount"]) == (405000, 2940000)
    assert plan["status"] == "pending" and plan["hasNewPositions"] and plan["hasExistingPositions"]
    budgets = {b["jobTitleId"]: b for b in plan["budgets"]}
    assert len(budgets) == 2
    seat_budget, people_budget = budgets[str(s["jt_a"])], budgets[str(s["jt_b"])]
    assert (seat_budget["amount"], seat_budget["totalPositions"]) == (1920000, 2)
    assert (people_budget["amount"], people_budget["totalPositions"]) == (1020000, 0)

    listed = client.get(f"{API}/plans", params={"q": plan["title"], "mode": "existing"}, headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["annualAmount"] == 2940000

    pending = client.get(f"{API}/budget-approvals", params={"q": plan["title"], "pageSize": 100}, headers=h).json()
    assert {b["id"] for b in pending["data"]} == {seat_budget["id"], people_budget["id"]}

    # Approve the seats: open positions are released and the plan locks.
    stale = client.post(f"{API}/budgets/{seat_budget['id']}/approve", json={"rowVersion": "00" * 8}, headers=h)
    assert stale.status_code == 409
    ok = client.post(f"{API}/budgets/{seat_budget['id']}/approve", json={"rowVersion": seat_budget["rowVersion"]},
                     headers=h)
    assert ok.status_code == 200 and ok.json()["data"]["status"] == "approved"
    assert ok.json()["data"]["openPositionCount"] == 1
    decided = fe.events(db, company, "manpower.budget_decided", int(seat_budget["id"]))
    assert len(decided) == 1 and decided[0]["data"]["status"] == "approved" and decided[0]["data"]["openPositions"] == 1
    opened = [e for e in fe.events(db, company, "manpower.position_opened") if e["data"]["budgetId"] == seat_budget["id"]]
    assert len(opened) == 1 and opened[0]["data"]["totalPositions"] == 2 and opened[0]["data"].get("reopened") is None
    told = fe.user_notifications(db, company, planner["user_id"], "mp.e_budget")
    assert [n["title"] for n in told] == [f"Budget approved: {seat_budget['title']}"]
    again = client.post(f"{API}/budgets/{seat_budget['id']}/approve", json={"rowVersion": ok.json()["data"]["rowVersion"]},
                        headers=h)
    assert again.status_code == 409 and again.json()["code"] == "BUDGET_ALREADY_DECIDED"
    stale = client.post(f"{API}/budgets/{seat_budget['id']}/reject", json={"rowVersion": seat_budget["rowVersion"]},
                        headers=h)  # the rowVersion read before the decision
    assert stale.status_code == 409 and stale.json()["code"] == "BUDGET_ALREADY_DECIDED"

    detail = client.get(f"{API}/plans/{plan['id']}", headers=h).json()["data"]
    assert detail["isLocked"] and detail["status"] == "pending"
    locked = client.put(f"{API}/plans/{plan['id']}", json={**_plan_body(s), "rowVersion": detail["rowVersion"]},
                        headers=h)
    assert locked.status_code == 409 and locked.json()["code"] == "PLAN_LOCKED"
    assert client.delete(f"{API}/budgets/{seat_budget['id']}", params={"rowVersion": ok.json()["data"]["rowVersion"]},
                         headers=h).status_code == 409

    # Reject the people budget: the plan is rejected. Editing it sends it back; approving it approves the plan.
    rejected = client.post(f"{API}/budgets/{people_budget['id']}/reject",
                           json={"rowVersion": people_budget["rowVersion"], "remarks": "Too much"}, headers=h)
    assert rejected.json()["data"]["status"] == "rejected" and rejected.json()["data"]["remarks"] == "Too much"
    told = fe.user_notifications(db, company, planner["user_id"], "mp.e_budget")
    assert told[-1]["title"].startswith("Budget rejected:") and told[-1]["body"] == "Too much"
    assert client.get(f"{API}/plans/{plan['id']}", headers=h).json()["data"]["status"] == "rejected"
    rb = rejected.json()["data"]
    edited = client.put(f"{API}/budgets/{rb['id']}",
                        json={"budgetDurationId": rb["budgetDurationId"], "jobTitleId": rb["jobTitleId"],
                              "departmentId": rb["departmentId"], "amount": 900000, "totalPositions": 0,
                              "startDate": "2032-01-01", "endDate": "2032-12-31", "rowVersion": rb["rowVersion"]},
                        headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["status"] == "pending"
    assert client.get(f"{API}/plans/{plan['id']}", headers=h).json()["data"]["status"] == "pending"
    approved = client.post(f"{API}/budgets/{rb['id']}/approve", json={"rowVersion": edited.json()["data"]["rowVersion"]},
                           headers=h)
    assert approved.status_code == 200
    assert client.get(f"{API}/plans/{plan['id']}", headers=h).json()["data"]["status"] == "approved"

    # Open positions: the two seats, edited with a JD file, closed and reopened.
    opens = client.get(f"{API}/open-positions", params={"jobTitleId": s["jt_a"]}, headers=h).json()["data"]
    assert len(opens) == 1
    op = opens[0]
    assert (op["totalPositions"], op["approvedPositions"], op["status"]) == (2, 2, "active")
    assert op["positionCode"] == s["position"]["code"]
    assert client.get(f"{API}/open-positions/{op['id']}/jd", headers=h).status_code == 404
    jd = int(factories.upload(client, h, name="JD - Accountant.pdf", module="manpower")["id"])
    upd = client.put(f"{API}/open-positions/{op['id']}",
                     json={"totalPositions": 1, "endDate": "2032-05-31", "jdFileId": jd, "rowVersion": op["rowVersion"]},
                     headers=h)
    assert upd.status_code == 200 and upd.json()["data"]["jdFile"]["name"] == "JD - Accountant.pdf"
    assert client.get(upd.json()["data"]["jdFile"]["url"]).content == factories.PDF_BYTES
    jd_file = client.get(f"{API}/open-positions/{op['id']}/jd", headers=h).json()["data"]
    assert jd_file["name"] == "JD - Accountant.pdf" and client.get(jd_file["url"]).status_code == 200
    closed = client.post(f"{API}/open-positions/{op['id']}/close", json={"rowVersion": upd.json()["data"]["rowVersion"]},
                         headers=h)
    assert closed.json()["data"]["status"] == "closed"
    twice = client.post(f"{API}/open-positions/{op['id']}/close", json={"rowVersion": closed.json()["data"]["rowVersion"]},
                        headers=h)
    assert twice.status_code == 409
    reopened = client.post(f"{API}/open-positions/{op['id']}/reopen",
                           json={"rowVersion": closed.json()["data"]["rowVersion"]}, headers=h)
    assert reopened.json()["data"]["status"] == "active"
    assert len(fe.events(db, company, "manpower.position_closed", int(op["id"]))) == 1
    reopen_events = fe.events(db, company, "manpower.position_opened", int(op["id"]))
    assert [e["data"].get("reopened") for e in reopen_events] == [None, True]

    # A plan with approved budgets cannot be deleted; its duration cannot either.
    assert client.delete(f"{API}/plans/{plan['id']}", params={"rowVersion": detail["rowVersion"]},
                         headers=h).status_code == 409
    d = client.get(f"{API}/budget-durations/{s['duration']['id']}", headers=h).json()["data"]
    used = client.delete(f"{API}/budget-durations/{d['id']}", params={"rowVersion": d["rowVersion"]}, headers=h)
    assert used.status_code == 409 and used.json()["code"] == "DURATION_IN_USE"



def test_plan_edit_and_delete_before_approval(client, db, company, admin):
    h = admin["headers"]
    s = _plan_setup(client, db, company, admin)
    plan = client.post(f"{API}/plans", json=_plan_body(s), headers=h).json()["data"]
    body = _plan_body(s, title=plan["title"], rowVersion=plan["rowVersion"])
    body["lines"] = body["lines"][:1]
    edited = client.put(f"{API}/plans/{plan['id']}", json=body, headers=h)
    assert edited.status_code == 200
    data = edited.json()["data"]
    assert len(data["lines"]) == 1 and len(data["budgets"]) == 1 and data["annualAmount"] == 1920000
    stale = client.put(f"{API}/plans/{plan['id']}", json=body, headers=h)
    assert stale.status_code == 409
    manual = client.post(f"{API}/budgets", json={"budgetDurationId": s["duration"]["id"], "jobTitleId": s["jt_a"],
                                                 "departmentId": s["dept"], "amount": 50000, "totalPositions": 1,
                                                 "startDate": "2032-02-01", "endDate": "2032-03-31"}, headers=h)
    assert manual.status_code == 201 and manual.json()["data"]["manpowerPlanId"] is None
    outside = client.post(f"{API}/budgets", json={"budgetDurationId": s["duration"]["id"], "title": "x", "amount": 1,
                                                  "startDate": "2031-02-01", "endDate": "2032-03-31"}, headers=h)
    assert outside.status_code == 422
    approved = client.post(f"{API}/budgets/{manual.json()['data']['id']}/approve",
                           json={"rowVersion": manual.json()["data"]["rowVersion"]}, headers=h).json()["data"]
    assert approved["openPositionCount"] == 1
    assert client.delete(f"{API}/plans/{plan['id']}", params={"rowVersion": data["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"{API}/plans/{plan['id']}", headers=h).status_code == 404


def test_permissions(client, db, company):
    staff = factories.login_as(db, client, company, role_codes="employee",
                               employee_id=factories.employee(db, company))
    for url in ("/plans", "/budgets", "/budget-approvals", "/open-positions", "/budget-durations", "/positions"):
        assert client.get(f"{API}{url}", headers=staff["headers"]).status_code == 403, url

    recruiter = factories.login_as(db, client, company, role_codes="recruiter")
    rh = recruiter["headers"]
    assert client.get(f"{API}/positions", headers=rh).status_code == 200  # planners read positions
    assert client.get(f"{API}/budget-durations", headers=rh).status_code == 200
    refused = client.post(f"{API}/budget-durations", json={"name": "x", "startDate": "2030-01-01",
                                                            "endDate": "2030-12-31"}, headers=rh)
    assert refused.status_code == 403
    assert client.post(f"{API}/positions/import", json={"rows": [{}]}, headers=rh).status_code == 403


def test_department_scope(client, db, company, admin):
    h = admin["headers"]
    s = _plan_setup(client, db, company, admin)
    other_dept = factories.department(db, company)
    mine = client.post(f"{API}/budgets", json={"budgetDurationId": s["duration"]["id"], "title": "Mine",
                                               "departmentId": s["dept"], "amount": 1000, "startDate": "2032-01-01",
                                               "endDate": "2032-01-31"}, headers=h).json()["data"]
    theirs = client.post(f"{API}/budgets", json={"budgetDurationId": s["duration"]["id"], "title": "Theirs",
                                                 "departmentId": other_dept, "amount": 1000,
                                                 "startDate": "2032-01-01", "endDate": "2032-01-31"},
                         headers=h).json()["data"]

    head_emp = factories.employee(db, company, department_id=s["dept"])
    head = factories.login_as(db, client, company, role_codes="department_head", employee_id=head_emp)
    hh = head["headers"]
    seen = {b["id"] for b in client.get(f"{API}/budget-approvals", params={"pageSize": 100}, headers=hh).json()["data"]}
    assert mine["id"] in seen and theirs["id"] not in seen
    assert client.get(f"{API}/budgets/{theirs['id']}", headers=hh).status_code == 404
    assert client.post(f"{API}/budgets/{theirs['id']}/approve", json={"rowVersion": theirs["rowVersion"]},
                       headers=hh).status_code == 404
    ok = client.post(f"{API}/budgets/{mine['id']}/approve", json={"rowVersion": mine["rowVersion"]}, headers=hh)
    assert ok.status_code == 200 and ok.json()["data"]["decidedByName"]
    # A department head reads but does not edit budgets.
    assert client.post(f"{API}/budgets", json={"budgetDurationId": s["duration"]["id"], "title": "x", "amount": 1,
                                               "startDate": "2032-01-01", "endDate": "2032-01-31"},
                       headers=hh).status_code == 403


def test_other_company_cannot_see(client, db, company, admin):
    s = _plan_setup(client, db, company, admin)
    plan = client.post(f"{API}/plans", json=_plan_body(s), headers=admin["headers"]).json()["data"]
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    assert client.get(f"{API}/plans/{plan['id']}", headers=other_admin["headers"]).status_code == 404
    assert client.get(f"{API}/positions/{s['position']['id']}", headers=other_admin["headers"]).status_code == 404
    using_theirs = client.post(f"{API}/plans", json={**_plan_body(s), "budgetDurationId": s["duration"]["id"]},
                               headers=other_admin["headers"])
    assert using_theirs.status_code == 422
