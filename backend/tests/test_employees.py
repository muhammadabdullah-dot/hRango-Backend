"""Employee records: directory, card, scope, CNIC masking, line-manager cycles, switching off,
employment periods, history, salary, bank details, and the promotion / transfer approval effects."""
from datetime import date

from tests import factories
from tests import factories_organisation as fo


def _new(client, h, branch, **extra) -> dict:
    body = {"firstName": "Bilal", "lastName": f"Aslam {factories.tag()}", "branchId": branch,
            "joiningDate": "2025-07-01", **extra}
    r = client.post("/api/employees", headers=h, json=body)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def _edit_body(e: dict, **changes) -> dict:
    keys = ("code", "firstName", "lastName", "branchId", "departmentId", "designationId", "jobTitleId", "gradeId",
            "jobLevelId", "lineManagerId", "finalAuthorityId", "status", "gender", "email")
    return {**{k: e[k] for k in keys}, "rowVersion": e["rowVersion"], **changes}


def test_employee_lifecycle(client, db, company, admin):
    h = admin["headers"]
    loc = fo.scalar(db, "SET NOCOUNT ON; INSERT org.location (company_id, name, employee_prefix) OUTPUT INSERTED.id "
                        "VALUES (?, ?, N'LHR')", company, f"Loc {factories.tag()}")
    prefix = f"P{factories.tag()[:5]}"
    branch = fo.scalar(db, "SET NOCOUNT ON; INSERT org.branch (company_id, location_id, name, employee_prefix) "
                           "OUTPUT INSERTED.id VALUES (?, ?, ?, ?)", company, loc, f"Br {factories.tag()}", prefix)
    dept = factories.department(db, company)

    e = _new(client, h, branch, departmentId=dept, gender="female", email="Bilal@Example.com",
             cnic="35202 1234567 1", dateOfBirth="1995-03-04")
    assert e["code"] == f"{prefix}-0001" and e["locationId"] == str(loc) and e["joiningDate"] == "2025-07-01"
    assert e["cnic"] == "35202-1234567-1" and e["canSeeIdentity"] and e["email"] == "bilal@example.com"
    second = _new(client, h, branch)
    assert second["code"] == f"{prefix}-0002"

    no_join = client.post("/api/employees", headers=h, json={"firstName": "A", "lastName": "B", "branchId": branch})
    assert no_join.status_code == 422 and "joiningDate" in no_join.json()["fieldErrors"]
    bad_cnic = client.post("/api/employees", headers=h, json={"firstName": "A", "lastName": "B", "branchId": branch,
                                                              "joiningDate": "2025-01-01", "cnic": "123"})
    assert bad_cnic.status_code == 422 and "cnic" in bad_cnic.json()["fieldErrors"]
    dup_cnic = client.post("/api/employees", headers=h, json={"firstName": "A", "lastName": "B", "branchId": branch,
                                                              "joiningDate": "2025-01-01", "cnic": "3520212345671"})
    assert dup_cnic.status_code == 409 and dup_cnic.json()["code"] == "EMPLOYEE_CNIC_DUPLICATE"
    dup_code = client.post("/api/employees", headers=h, json={"firstName": "A", "lastName": "B", "branchId": branch,
                                                              "joiningDate": "2025-01-01", "code": e["code"]})
    assert dup_code.status_code == 409 and "code" in dup_code.json()["fieldErrors"]

    page = client.get("/api/employees", params={"branchId": branch, "pageSize": 1}, headers=h).json()
    assert page["meta"]["total"] == 2 and len(page["data"]) == 1
    assert client.get("/api/employees", params={"departmentId": dept}, headers=h).json()["meta"]["total"] == 1

    other_dept = factories.department(db, company)
    moved = client.put(f"/api/employees/{e['id']}", headers=h, json=_edit_body(e, departmentId=other_dept))
    assert moved.status_code == 200, moved.text
    assert moved.json()["data"]["departmentId"] == str(other_dept)
    assert moved.json()["data"]["cnic"] == "35202-1234567-1"  # the main form never clears the CNIC
    stale = client.put(f"/api/employees/{e['id']}", headers=h, json=_edit_body(e))
    assert stale.status_code == 409

    history = client.get(f"/api/employees/{e['id']}/history", headers=h).json()["data"]
    assert [x["changeType"] for x in history] == ["edit", "joining"]
    changes = client.get(f"/api/employees/{e['id']}/changes", headers=h).json()
    assert {c["fieldName"] for c in changes["data"]} >= {"department_id"}

    identity = client.put(f"/api/employees/{e['id']}/identity", headers=h,
                          json={"cnic": "", "rowVersion": moved.json()["data"]["rowVersion"]})
    assert identity.status_code == 200 and identity.json()["data"]["cnic"] is None

    other = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    assert client.get(f"/api/employees/{e['id']}", headers=other).status_code == 404


def test_cnic_needs_identity_permission(client, db, company):
    branch = factories.branch(db, company)
    clerk = factories.login_as(db, client, company)
    for code in ("employees.directory.view", "employees.directory.create"):
        fo.override(db, clerk["user_id"], code)
    h = clerk["headers"]
    refused = client.post("/api/employees", headers=h, json={"firstName": "A", "lastName": "B", "branchId": branch,
                                                             "joiningDate": "2025-01-01", "cnic": "4210112345671"})
    assert refused.status_code == 403
    e = _new(client, h, branch)
    fo.execute(db, "UPDATE hr.employee SET cnic = N'42101-7654321-1' WHERE id = ?", int(e["id"]))
    seen = client.get(f"/api/employees/{e['id']}", headers=h).json()["data"]
    assert seen["cnic"] is None and not seen["canSeeIdentity"]


def test_scope_and_line_manager_cycle(client, db, company, admin):
    h = admin["headers"]
    dept = factories.department(db, company)
    sub = factories.department(db, company, parent_id=dept)
    outside = factories.department(db, company)
    head = factories.employee(db, company, department_id=dept)
    mid = factories.employee(db, company, department_id=sub, line_manager_id=head)
    low = factories.employee(db, company, department_id=sub, line_manager_id=mid)
    stranger = factories.employee(db, company, department_id=outside)

    hod = factories.login_as(db, client, company, role_codes="department_head", employee_id=head)["headers"]
    seen = {x["id"] for x in client.get("/api/employees", params={"pageSize": 100}, headers=hod).json()["data"]}
    assert seen == {str(head), str(mid), str(low)}
    assert client.get(f"/api/employees/{stranger}", headers=hod).status_code == 404
    assert client.post("/api/employees", headers=hod, json={"firstName": "N", "lastName": "O", "branchId": 1,
                                                            "joiningDate": "2026-01-01"}).status_code == 403

    top = client.get(f"/api/employees/{head}", headers=h).json()["data"]
    cycle = client.put(f"/api/employees/{head}", headers=h, json=_edit_body(top, lineManagerId=low))
    assert cycle.status_code == 422 and cycle.json()["code"] == "LINE_MANAGER_CYCLE"
    self_ = client.put(f"/api/employees/{head}", headers=h, json=_edit_body(top, lineManagerId=head))
    assert self_.status_code == 422 and "lineManagerId" in self_.json()["fieldErrors"]

    # A department head given create rights can only add people inside their department.
    creator = factories.login_as(db, client, company, employee_id=mid)
    fo.override(db, creator["user_id"], "employees.directory.create", scope="department")
    branch = factories.branch(db, company)
    inside = client.post("/api/employees", headers=creator["headers"],
                         json={"firstName": "In", "lastName": "Side", "branchId": branch, "departmentId": sub,
                               "joiningDate": "2026-01-01"})
    assert inside.status_code == 201, inside.text
    outside_try = client.post("/api/employees", headers=creator["headers"],
                              json={"firstName": "Out", "lastName": "Side", "branchId": branch,
                                    "departmentId": outside, "joiningDate": "2026-01-01"})
    assert outside_try.status_code == 403


def test_deactivate_and_reactivate(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company)
    person = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    assert client.get("/api/auth/me", headers=person["headers"]).status_code == 200

    e = client.get(f"/api/employees/{emp}", headers=h).json()["data"]
    off = client.patch(f"/api/employees/{emp}/deactivate", headers=h, json={"rowVersion": e["rowVersion"]})
    assert off.status_code == 200 and off.json()["data"]["status"] == "inactive"
    assert client.get("/api/auth/me", headers=person["headers"]).status_code == 401
    login = client.post("/api/auth/login", json={"email": person["email"], "password": factories.PASSWORD})
    assert login.status_code == 403 and login.json()["code"] == "ACCOUNT_DISABLED"

    hidden = {x["id"] for x in client.get("/api/employees", params={"pageSize": 100}, headers=h).json()["data"]}
    assert str(emp) not in hidden
    shown = client.get("/api/employees", params={"status": "inactive", "pageSize": 100}, headers=h).json()["data"]
    assert str(emp) in {x["id"] for x in shown}

    again = client.patch(f"/api/employees/{emp}/deactivate", headers=h,
                         json={"rowVersion": off.json()["data"]["rowVersion"]})
    assert again.status_code == 409
    on = client.patch(f"/api/employees/{emp}/reactivate", headers=h,
                      json={"rowVersion": off.json()["data"]["rowVersion"]})
    assert on.status_code == 200 and on.json()["data"]["status"] == "active"

    me_emp = factories.employee(db, company)
    me = factories.login_as(db, client, company, role_codes="hr_manager", employee_id=me_emp)["headers"]
    mine = client.get(f"/api/employees/{me_emp}", headers=me).json()["data"]
    assert client.patch(f"/api/employees/{me_emp}/deactivate", headers=me,
                        json={"rowVersion": mine["rowVersion"]}).status_code == 403


def test_employment_periods(client, db, company, admin):
    h = admin["headers"]
    e = _new(client, h, factories.branch(db, company))
    periods = client.get(f"/api/employees/{e['id']}/employment-periods", headers=h).json()["data"]
    assert len(periods) == 1
    overlap = client.post(f"/api/employees/{e['id']}/employment-periods", headers=h, json={"joiningDate": "2026-01-01"})
    assert overlap.status_code == 409 and overlap.json()["code"] == "PERIOD_OVERLAP"
    ended = client.put(f"/api/employees/{e['id']}/employment-periods/{periods[0]['id']}", headers=h,
                       json={"joiningDate": "2025-07-01", "endDate": "2025-12-31", "rowVersion": periods[0]["rowVersion"]})
    assert ended.status_code == 200, ended.text
    rehire = client.post(f"/api/employees/{e['id']}/employment-periods", headers=h, json={"joiningDate": "2026-03-01"})
    assert rehire.status_code == 201
    assert client.get(f"/api/employees/{e['id']}", headers=h).json()["data"]["joiningDate"] == "2026-03-01"
    backwards = client.post(f"/api/employees/{e['id']}/employment-periods", headers=h,
                            json={"joiningDate": "2027-01-01", "endDate": "2026-01-01"})
    assert backwards.status_code == 422


def test_salary_and_bank_details(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company)
    other = factories.employee(db, company)

    first = client.post(f"/api/employees/{emp}/salary", headers=h,
                        json={"effectiveDate": "2025-07-01", "amount": "150000", "source": "joining"})
    assert first.status_code == 201, first.text
    raise_ = client.post(f"/api/employees/{emp}/salary", headers=h,
                         json={"effectiveDate": "2026-01-01", "amount": "165000", "changeType": "percent",
                               "changeValue": "10"})
    assert raise_.json()["data"]["previousAmount"] == "150000.00"
    same_day = client.post(f"/api/employees/{emp}/salary", headers=h,
                           json={"effectiveDate": "2026-01-01", "amount": "1"})
    assert same_day.status_code == 409
    rows = client.get(f"/api/employees/{emp}/salary", headers=h).json()["data"]
    assert [r["isCurrent"] for r in rows] == [True, False]

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)["headers"]
    assert client.get(f"/api/employees/{emp}/salary", headers=staff).status_code == 200  # own salary
    assert client.get(f"/api/employees/{other}/salary", headers=staff).status_code == 404
    assert client.post(f"/api/employees/{emp}/salary", headers=staff,
                       json={"effectiveDate": "2026-02-01", "amount": "999999"}).status_code == 403

    acct = {"accountHolder": "Bilal Aslam", "accountNumber": "PK36 SCBL 0000 0011 2345 6702", "bankName": "Meezan Bank",
            "branchCode": "0201", "taxPayerId": "1234567-8"}
    a1 = client.post(f"/api/employees/{emp}/bank-accounts", headers=h, json=acct)
    assert a1.status_code == 201 and a1.json()["data"]["isPrimary"]
    assert a1.json()["data"]["accountNumber"] == "PK36SCBL0000001123456702"
    dup = client.post(f"/api/employees/{emp}/bank-accounts", headers=h, json=acct)
    assert dup.status_code == 409
    a2 = client.post(f"/api/employees/{emp}/bank-accounts", headers=h,
                     json={**acct, "accountNumber": "0123456789", "isPrimary": True}).json()["data"]
    accounts = client.get(f"/api/employees/{emp}/bank-accounts", headers=h).json()["data"]
    assert [a["id"] for a in accounts if a["isPrimary"]] == [a2["id"]]
    assert client.delete(f"/api/employees/{emp}/bank-accounts/{a2['id']}", headers=h,
                         params={"rowVersion": a2["rowVersion"]}).status_code == 204
    assert client.get(f"/api/employees/{emp}/bank-accounts", headers=h).json()["data"][0]["isPrimary"]
    executive = factories.login_as(db, client, company, role_codes="executive")["headers"]
    assert client.post(f"/api/employees/{emp}/bank-accounts", headers=executive, json=acct).status_code == 403


def test_lookup_picker(client, db, company, admin):
    e = factories.employee(db, company, first_name="Zubair", last_name=f"Picker{factories.tag()}")
    rows = client.get("/api/employees/lookup", params={"q": "Picker"}, headers=admin["headers"]).json()["data"]
    assert str(e) in {r["id"] for r in rows}
    bad = client.get("/api/employees/lookup", params={"permission": "nope.nope.view"}, headers=admin["headers"])
    assert bad.status_code == 422
    nobody = factories.login_as(db, client, company)["headers"]
    assert client.get("/api/employees/lookup", params={"q": "Picker"}, headers=nobody).json()["data"] == []


def test_lookup_pages_beyond_a_hundred_and_gives_unit_ids(client, db, company, admin):
    h = admin["headers"]
    dept = factories.department(db, company)
    tag = f"Pager{factories.tag()}"
    branch = factories.branch(db, company)
    made = [factories.employee(db, company, branch, dept, first_name="Paula", last_name=f"{tag}{i:03d}")
            for i in range(105)]
    first = client.get("/api/employees/lookup", params={"q": tag, "pageSize": 100}, headers=h).json()
    assert first["meta"]["total"] == 105 and first["meta"]["totalPages"] == 2 and len(first["data"]) == 100
    second = client.get("/api/employees/lookup", params={"q": tag, "page": 2, "pageSize": 100}, headers=h).json()
    assert len(second["data"]) == 5
    assert {r["id"] for r in first["data"] + second["data"]} == {str(e) for e in made}
    row = second["data"][0]
    assert row["departmentId"] == str(dept) and row["departmentName"] and row["branchId"] and row["branchName"]
    assert "photoUrl" in row
    # No paging sent: the first page, `limit` long (default 50), as before.
    legacy = client.get("/api/employees/lookup", params={"q": tag}, headers=h).json()
    assert len(legacy["data"]) == 50 and legacy["meta"]["page"] == 1
    assert len(client.get("/api/employees/lookup", params={"q": tag, "limit": 7}, headers=h).json()["data"]) == 7
    capped = client.get("/api/employees/lookup", params={"q": tag, "pageSize": 500}, headers=h).json()
    assert len(capped["data"]) == 100


def test_promotion_and_transfer_effects(client, db, company, admin):
    h = admin["headers"]
    grade = fo.master(db, company, "grade")
    level = fo.master(db, company, "job_level")
    desig = fo.master(db, company, "designation")
    title = fo.job_title(db, company)
    manager = factories.employee(db, company)
    emp = factories.employee(db, company, line_manager_id=manager)
    client.post(f"/api/employees/{emp}/salary", headers=h, json={"effectiveDate": "2025-01-01", "amount": "100000"})

    rid = fo.promotion_request(db, company, emp, grade, level, desig, title, 130000, date(2026, 11, 1))
    actor = admin["user_id"]
    db.call("hr.usp_request_apply_promotion", company_id=company, actor_user_id=actor, request_id=rid)
    db.call("hr.usp_request_apply_promotion", company_id=company, actor_user_id=actor, request_id=rid)  # no-op
    assert fo.employee_fields(db, emp, "grade_id", "job_level_id", "designation_id", "job_title_id") == \
        (grade, level, desig, title)
    history = client.get(f"/api/employees/{emp}/history", headers=h).json()["data"]
    assert [x["changeType"] for x in history].count("promotion") == 1
    assert history[0]["sourceRequestId"] == str(rid) and history[0]["effectiveDate"] == "2026-11-01"
    salary = client.get(f"/api/employees/{emp}/salary", headers=h).json()["data"]
    assert salary[0]["source"] == "promotion" and salary[0]["amount"] == "130000.00"
    assert salary[0]["previousAmount"] == "100000.00"

    # Transfer to another branch and department under a new manager.
    branch = factories.branch(db, company)
    dept = factories.department(db, company)
    boss = factories.employee(db, company)
    tid = fo.transfer_request(db, company, emp, fo.branch_location(db, branch), branch, dept, boss, boss,
                              date(2026, 12, 1))
    db.call("hr.usp_request_apply_transfer", company_id=company, actor_user_id=actor, request_id=tid)
    assert fo.employee_fields(db, emp, "branch_id", "department_id", "line_manager_id") == (branch, dept, boss)

    # Cancelling the promotion first is refused: the transfer came after it.
    try:
        db.call("hr.usp_request_revert_promotion", company_id=company, actor_user_id=actor, request_id=rid)
        raise AssertionError("expected a conflict")
    except Exception as exc:  # AppError from the procedure
        assert getattr(exc, "status", None) == 409
    db.call("hr.usp_request_revert_transfer", company_id=company, actor_user_id=actor, request_id=tid)
    db.call("hr.usp_request_revert_promotion", company_id=company, actor_user_id=actor, request_id=rid)
    assert fo.employee_fields(db, emp, "grade_id", "job_title_id", "line_manager_id") == (None, None, manager)
    assert all(s["source"] != "promotion" for s in client.get(f"/api/employees/{emp}/salary", headers=h).json()["data"])

    # A transfer that would make the employee manage their own manager blocks the approval.
    report = factories.employee(db, company, line_manager_id=emp)
    bad = fo.transfer_request(db, company, emp, fo.branch_location(db, branch), branch, dept, report, boss,
                              date(2026, 12, 1))
    try:
        db.call("hr.usp_request_apply_transfer", company_id=company, actor_user_id=actor, request_id=bad)
        raise AssertionError("expected a conflict")
    except Exception as exc:
        assert getattr(exc, "status", None) == 409
    other = factories.company(db)
    try:
        db.call("hr.usp_request_apply_transfer", company_id=other, actor_user_id=actor, request_id=tid)
        raise AssertionError("expected not found")
    except Exception as exc:
        assert getattr(exc, "status", None) == 404
