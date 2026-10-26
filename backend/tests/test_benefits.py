"""Benefits: plan years with their plans, benefit plans, enrollment windows, employee elections and their
approval, the Employees tab, plan files, health benefits and perks; validation, permissions, scope and
row versions."""
from datetime import date, timedelta

from tests import factories
from tests import factories_events as fe
from tests import factories_manpower as mpf

API = "/api/benefits"
TODAY = date.today()


def _d(days: int) -> str:
    return (TODAY + timedelta(days=days)).isoformat()


def _plan(client, h, category: str = "medical", **extra) -> dict:
    body = {"category": category, "name": f"{category.title()} {factories.tag()}", "planType": "PPO",
            "carrier": "Carrier", "startDate": _d(-30), "endDate": _d(330), **extra}
    r = client.post(f"{API}/plans", json=body, headers=h)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def _year(client, h, plan_ids: list[str], **extra) -> dict:
    body = {"name": f"PY {factories.tag()}", "startDate": _d(-30), "endDate": _d(330), "planIds": plan_ids,
            "newHireStart": "immediately", "electionPeriod": 30, "electionUnit": "day", **extra}
    r = client.post(f"{API}/plan-years", json=body, headers=h)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_plans_and_plan_years(client, db, company, admin):
    h = admin["headers"]
    medical = _plan(client, h, "medical")
    dental = _plan(client, h, "dental", planTypeRef="D-1")
    dup = client.post(f"{API}/plans", json={"category": "vision", "name": medical["name"], "startDate": _d(0),
                                             "endDate": _d(10)}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "BENEFIT_PLAN_DUPLICATE"
    bad_cat = client.post(f"{API}/plans", json={"category": "pets", "name": "x", "startDate": _d(0),
                                                 "endDate": _d(10)}, headers=h)
    assert bad_cat.status_code == 422
    copy = client.post(f"{API}/plans/{medical['id']}/duplicate", headers=h)
    assert copy.status_code == 201 and copy.json()["data"]["name"] == f"{medical['name']} (copy)"
    copy2 = client.post(f"{API}/plans/{medical['id']}/duplicate", headers=h).json()["data"]
    assert copy2["name"] == f"{medical['name']} (copy 2)"

    year = _year(client, h, [medical["id"], dental["id"]])
    assert year["status"] == "active" and sorted(year["planIds"]) == sorted([medical["id"], dental["id"]])
    assert year["planCount"] == 2
    upcoming = _year(client, h, [], startDate=_d(400), endDate=_d(700))
    assert upcoming["status"] == "upcoming"
    listed = client.get(f"{API}/plan-years", params={"status": "upcoming", "q": upcoming["name"]}, headers=h).json()
    assert listed["meta"]["total"] == 1

    waiting = client.post(f"{API}/plan-years", json={"name": f"W {factories.tag()}", "startDate": _d(0),
                                                      "endDate": _d(10), "newHireStart": "waiting_period"}, headers=h)
    assert waiting.status_code == 422 and "waitingPeriodDays" in waiting.json()["fieldErrors"]
    dup_year = client.post(f"{API}/plan-years", json={"name": year["name"], "startDate": _d(0), "endDate": _d(10)},
                           headers=h)
    assert dup_year.status_code == 409 and dup_year.json()["code"] == "PLAN_YEAR_DUPLICATE"

    edited = client.put(f"{API}/plan-years/{year['id']}",
                        json={"name": year["name"], "startDate": _d(-30), "endDate": _d(330),
                              "planIds": [medical["id"]], "newHireStart": "waiting_period", "waitingPeriodDays": 60,
                              "electionPeriod": 2, "electionUnit": "week", "rowVersion": year["rowVersion"]}, headers=h)
    assert edited.status_code == 200
    assert edited.json()["data"]["planIds"] == [medical["id"]] and edited.json()["data"]["waitingPeriodDays"] == 60
    stale = client.put(f"{API}/plan-years/{year['id']}", json={"name": "x", "startDate": _d(0), "endDate": _d(10),
                                                               "rowVersion": year["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    offered = client.get(f"{API}/plans", params={"planYearId": year["id"]}, headers=h).json()["data"]
    assert [p["id"] for p in offered] == [medical["id"]]
    assert client.delete(f"{API}/plans/{copy2['id']}", params={"rowVersion": copy2["rowVersion"]},
                         headers=h).status_code == 204
    up = client.get(f"{API}/plan-years/{upcoming['id']}", headers=h).json()["data"]
    assert client.delete(f"{API}/plan-years/{up['id']}", params={"rowVersion": up["rowVersion"]},
                         headers=h).status_code == 204


def test_windows_elections_and_employees(client, db, company, admin):
    h = admin["headers"]
    medical, life, vision = _plan(client, h, "medical"), _plan(client, h, "life"), _plan(client, h, "vision")
    year = _year(client, h, [medical["id"], life["id"]])
    dept = factories.department(db, company)
    emp = factories.employee(db, company, department_id=dept, first_name="Sana")
    other = factories.employee(db, company, department_id=dept)
    mpf.employee_details(db, other, date_of_birth=date(1990, 5, 1), marital_status="Married")
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    sh = staff["headers"]

    not_offered = client.post(f"{API}/enrollment-windows",
                              json={"planYearId": year["id"], "name": "Open", "effectiveDate": _d(0),
                                    "closesOn": _d(20), "planIds": [vision["id"]]}, headers=h)
    assert not_offered.status_code == 422 and "planIds" in not_offered.json()["fieldErrors"]
    outside = client.post(f"{API}/enrollment-windows",
                          json={"planYearId": year["id"], "name": "Open", "effectiveDate": _d(500),
                                "closesOn": _d(20), "planIds": [medical["id"]]}, headers=h)
    assert outside.status_code == 422 and "effectiveDate" in outside.json()["fieldErrors"]
    window = client.post(f"{API}/enrollment-windows",
                         json={"planYearId": year["id"], "name": f"Open {factories.tag()}", "effectiveDate": _d(0),
                               "closesOn": _d(20), "planIds": [medical["id"], life["id"]],
                               "employeeIds": [emp, other]}, headers=h)
    assert window.status_code == 201, window.text
    w = window.json()["data"]
    assert w["status"] == "open" and sorted(w["employeeIds"]) == sorted([str(emp), str(other)])
    closed = client.post(f"{API}/enrollment-windows",
                         json={"planYearId": year["id"], "name": "Old", "kind": "life_event", "effectiveDate": _d(-20),
                               "closesOn": _d(-1), "planIds": [medical["id"]]}, headers=h).json()["data"]
    assert closed["status"] == "closed"

    # The employee elects for themselves in the open window, but not for a colleague, nor a plan not offered.
    for_other = client.post(f"{API}/elections", json={"employeeId": other, "planYearId": year["id"],
                                                      "planIds": [medical["id"]]}, headers=sh)
    assert for_other.status_code == 422 and "employeeId" in for_other.json()["fieldErrors"]
    wrong_plan = client.post(f"{API}/elections", json={"employeeId": emp, "planYearId": year["id"],
                                                       "planIds": [vision["id"]]}, headers=sh)
    assert wrong_plan.status_code == 422 and "planIds" in wrong_plan.json()["fieldErrors"]
    in_closed = client.post(f"{API}/elections", json={"employeeId": emp, "planYearId": year["id"],
                                                      "enrollmentWindowId": closed["id"], "planIds": [medical["id"]]},
                            headers=sh)
    assert in_closed.status_code == 422 and in_closed.json()["code"] == "WINDOW_CLOSED"
    mine = client.post(f"{API}/elections", json={"employeeId": emp, "planYearId": year["id"],
                                                 "planIds": [medical["id"], life["id"]]}, headers=sh)
    assert mine.status_code == 201, mine.text
    election = mine.json()["data"]
    assert election["status"] == "pending" and election["enrollmentWindowId"] == w["id"]
    assert len(election["planIds"]) == 2
    again = client.post(f"{API}/elections", json={"employeeId": emp, "planYearId": year["id"],
                                                  "planIds": [medical["id"]]}, headers=sh)
    assert again.status_code == 409 and again.json()["code"] == "ELECTION_DUPLICATE"
    assert client.post(f"{API}/elections/{election['id']}/approve", json={"rowVersion": election["rowVersion"]},
                       headers=sh).status_code == 403
    own = client.get(f"{API}/elections", headers=sh).json()
    assert [e["id"] for e in own["data"]] == [election["id"]]

    # HR records a waiver for the colleague and approves the employee's election.
    waived = client.post(f"{API}/elections", json={"employeeId": other, "planYearId": year["id"], "waive": True},
                         headers=h)
    assert waived.status_code == 201 and waived.json()["data"]["status"] == "waived"
    approved = client.post(f"{API}/elections/{election['id']}/approve",
                           json={"rowVersion": election["rowVersion"], "remarks": "OK"}, headers=h)
    assert approved.status_code == 200 and approved.json()["data"]["status"] == "approved"
    decided = fe.events(db, company, "benefits.election_decided", int(election["id"]))
    assert len(decided) == 1 and decided[0]["data"]["status"] == "approved"
    assert {p["id"] for p in decided[0]["data"]["plans"]} == {medical["id"], life["id"]}
    told = fe.notifications(db, company, emp, "ben.election", int(election["id"]))
    assert len(told) == 1 and told[0]["title"].endswith("were approved") and told[0]["body"] == "OK"
    twice = client.post(f"{API}/elections/{election['id']}/approve",
                        json={"rowVersion": approved.json()["data"]["rowVersion"]}, headers=h)
    assert twice.status_code == 409 and twice.json()["code"] == "ELECTION_DECIDED"
    locked = client.put(f"{API}/elections/{election['id']}",
                        json={"employeeId": emp, "planYearId": year["id"], "planIds": [medical["id"]],
                              "rowVersion": approved.json()["data"]["rowVersion"]}, headers=h)
    assert locked.status_code == 409 and locked.json()["code"] == "ELECTION_LOCKED"

    plan_row = client.get(f"{API}/plans/{medical['id']}", headers=h).json()["data"]
    assert plan_row["enrolled"] == 1
    assert client.delete(f"{API}/plans/{medical['id']}", params={"rowVersion": plan_row["rowVersion"]},
                         headers=h).status_code == 409
    yr = client.get(f"{API}/plan-years/{year['id']}", headers=h).json()["data"]
    assert yr["approved"] >= 1 and yr["windowCount"] == 2
    assert client.delete(f"{API}/plan-years/{yr['id']}", params={"rowVersion": yr["rowVersion"]},
                         headers=h).status_code == 409

    people = client.get(f"{API}/employees", params={"planYearId": year["id"], "q": "Sana", "pageSize": 100},
                        headers=h).json()["data"]
    me = next(p for p in people if p["id"] == str(emp))
    assert me["electionStatus"] == "approved" and me["missing"] == ["date_of_birth", "marital_status"]
    missing = client.get(f"{API}/employees", params={"missingOnly": "true", "pageSize": 100}, headers=h).json()["data"]
    assert str(other) not in {p["id"] for p in missing}

    summary = client.get(f"{API}/summary", headers=h).json()["data"]
    assert summary["planYears"] >= 1 and summary["enrollmentWindows"] >= 1

    win = client.get(f"{API}/enrollment-windows/{w['id']}", headers=h).json()["data"]
    assert win["electionCount"] == 2
    assert client.delete(f"{API}/enrollment-windows/{w['id']}", params={"rowVersion": win["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"{API}/elections/{election['id']}", headers=h).json()["data"]["enrollmentWindowId"] is None


def test_company_wide_records_need_company_scope(client, db, company):
    staff = factories.login_as(db, client, company, role_codes="employee",
                               employee_id=factories.employee(db, company))
    sh = staff["headers"]
    # The Employee role holds benefits.plan_years.create with own scope only.
    r = client.post(f"{API}/plan-years", json={"name": "Mine", "startDate": _d(0), "endDate": _d(10)}, headers=sh)
    assert r.status_code == 403
    # Staff read the plans and plan years they can enrol in.
    assert client.get(f"{API}/plans", headers=sh).status_code == 200
    assert client.get(f"{API}/plan-years", headers=sh).status_code == 200


def test_plan_files(client, db, company, admin):
    h = admin["headers"]
    plan = _plan(client, h, "dental")
    f = int(factories.upload(client, h, name="Dental brochure.pdf", module="benefits")["id"])
    added = client.post(f"{API}/plans/{plan['id']}/files", json={"fileId": f}, headers=h)
    assert added.status_code == 201 and added.json()["data"]["fileName"] == "Dental brochure.pdf"
    assert added.json()["data"]["file"]["id"] == str(f)
    assert client.get(added.json()["data"]["file"]["url"]).content == factories.PDF_BYTES
    assert fe._rows(db, "SELECT company_id FROM core.attachment WHERE id = ?", int(added.json()["data"]["id"])) == \
        [{"company_id": company}]
    other = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    foreign = factories.upload(client, other, module="benefits")
    theirs = client.post(f"{API}/plans/{plan['id']}/files", json={"fileId": int(foreign["id"])}, headers=h)
    assert theirs.status_code == 422 and "fileId" in theirs.json()["fieldErrors"]
    dup = client.post(f"{API}/plans/{plan['id']}/files", json={"fileId": f}, headers=h)
    assert dup.status_code == 409
    missing = client.post(f"{API}/plans/{plan['id']}/files", json={"fileId": 999999999}, headers=h)
    assert missing.status_code == 422
    files = client.get(f"{API}/files", params={"planId": plan["id"]}, headers=h).json()
    assert files["meta"]["total"] == 1 and files["data"][0]["file"]["name"] == "Dental brochure.pdf"
    assert client.get(f"{API}/plans/{plan['id']}", headers=h).json()["data"]["fileCount"] == 1
    row = files["data"][0]
    assert client.delete(f"{API}/files/{row['id']}", params={"rowVersion": row["rowVersion"]},
                         headers=h).status_code == 204


def test_health_benefits_and_perks_scope(client, db, company, admin):
    h = admin["headers"]
    boss = factories.employee(db, company)
    report = factories.employee(db, company, line_manager_id=boss)
    stranger = factories.employee(db, company)
    manager = factories.login_as(db, client, company, role_codes="line_manager", employee_id=boss)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=report)

    card = factories.upload(client, h, name="Insurance card.png", content=factories.PNG_BYTES, module="benefits")
    hb = client.post(f"{API}/health-benefits", json={"employeeId": report, "insurer": "State Life",
                                                     "coverageAmount": 500000, "lifeCoverAmount": 1000000,
                                                     "annualPayment": 24000, "status": "availed",
                                                     "startDate": _d(0), "endDate": _d(365),
                                                     "documentFileId": int(card["id"])}, headers=h)
    assert hb.status_code == 201, hb.text
    hb = hb.json()["data"]
    assert hb["annualPayment"] == 24000 and hb["status"] == "availed"
    assert hb["documentFileId"] == card["id"] and hb["documentFile"]["name"] == "Insurance card.png"
    own_view = client.get(f"{API}/health-benefits/{hb['id']}", headers=staff["headers"]).json()["data"]
    assert client.get(own_view["documentFile"]["url"]).content == factories.PNG_BYTES
    no_doc = client.post(f"{API}/health-benefits", json={"employeeId": report, "insurer": "X",
                                                         "documentFileId": 999999999}, headers=h)
    assert no_doc.status_code == 422 and "documentFileId" in no_doc.json()["fieldErrors"]
    bad = client.post(f"{API}/health-benefits", json={"employeeId": report, "insurer": "X", "startDate": _d(5),
                                                      "endDate": _d(1)}, headers=h)
    assert bad.status_code == 422 and "endDate" in bad.json()["fieldErrors"]
    theirs = client.post(f"{API}/health-benefits", json={"employeeId": stranger, "insurer": "Jubilee"},
                         headers=h).json()["data"]

    seen = {r["id"] for r in client.get(f"{API}/health-benefits", headers=staff["headers"]).json()["data"]}
    assert hb["id"] in seen and theirs["id"] not in seen
    assert client.get(f"{API}/health-benefits/{theirs['id']}", headers=staff["headers"]).status_code == 404

    perk = client.post(f"{API}/perks", json={"employeeId": report, "occasion": "eid_ul_fitr", "perkDate": _d(10),
                                             "amount": 5000, "description": "Gift hamper"}, headers=h)
    assert perk.status_code == 201, perk.text
    perk = perk.json()["data"]
    dup = client.post(f"{API}/perks", json={"employeeId": report, "occasion": "eid_ul_fitr", "perkDate": _d(10)},
                      headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "PERK_DUPLICATE"
    wrong = client.post(f"{API}/perks", json={"employeeId": report, "occasion": "halloween", "perkDate": _d(10)},
                        headers=h)
    assert wrong.status_code == 422
    # The line manager sees the report's perk (team scope), not a stranger's.
    client.post(f"{API}/perks", json={"employeeId": stranger, "occasion": "birthday", "perkDate": _d(3)}, headers=h)
    team = client.get(f"{API}/perks", params={"pageSize": 100}, headers=manager["headers"]).json()["data"]
    assert {p["employeeId"] for p in team} == {str(report)}

    availed = client.put(f"{API}/perks/{perk['id']}",
                         json={"employeeId": report, "occasion": "eid_ul_fitr", "perkDate": _d(10), "amount": 5000,
                               "status": "availed", "rowVersion": perk["rowVersion"]}, headers=h)
    assert availed.status_code == 200 and availed.json()["data"]["status"] == "availed"
    stale = client.put(f"{API}/perks/{perk['id']}",
                       json={"employeeId": report, "occasion": "eid_ul_fitr", "perkDate": _d(10),
                             "rowVersion": perk["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    assert client.delete(f"{API}/perks/{perk['id']}", params={"rowVersion": perk["rowVersion"]},
                         headers=h).status_code == 409
    assert client.delete(f"{API}/perks/{perk['id']}", params={"rowVersion": availed.json()["data"]["rowVersion"]},
                         headers=h).status_code == 204
    assert client.delete(f"{API}/health-benefits/{hb['id']}", params={"rowVersion": hb["rowVersion"]},
                         headers=h).status_code == 204
