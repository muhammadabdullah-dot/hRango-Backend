"""Who sees what about a colleague: work details with the directory, personal details only with
employees.personal.view; and the role a person is shown as."""
from tests import factories, factories_requests as fr

PERSONAL = ("dateOfBirth", "phone1", "phone2", "homeAddress", "maritalStatus", "parentName", "nationality")


def _team(db, client):
    company_id = factories.company(db)
    branch_id = factories.branch(db, company_id)
    department_id = factories.department(db, company_id)
    manager = factories.employee(db, company_id, branch_id=branch_id, department_id=department_id)
    staff = factories.employee(db, company_id, branch_id=branch_id, department_id=department_id,
                               line_manager_id=manager)
    fr.execute(db, "UPDATE hr.employee SET phone_1 = N'+92 300 1234567', home_address = N'House 1', "
                   "date_of_birth = '1995-01-02', marital_status = N'single', email = N'staff@test.local' WHERE id = ?",
               staff)
    return company_id, manager, staff


def test_directory_alone_hides_personal_details(client, db):
    company_id, manager, staff = _team(db, client)
    for role in ("recruiter", "executive"):
        user = factories.login_as(db, client, company_id, role_codes=role)
        row = client.get(f"/api/employees/{staff}", headers=user["headers"]).json()["data"]
        assert row["email"] == "staff@test.local" and row["canSeePersonal"] is False, role
        assert all(row[k] is None for k in PERSONAL), role
        listed = client.get("/api/employees", headers=user["headers"]).json()["data"]
        assert all(r["phone1"] is None and r["homeAddress"] is None for r in listed), role

    lead = factories.login_as(db, client, company_id, role_codes="line_manager", employee_id=manager)
    row = client.get(f"/api/employees/{staff}", headers=lead["headers"]).json()["data"]
    assert row["canSeePersonal"] is False and row["phone1"] is None
    assert client.get(f"/api/employees/{staff}/dependents", headers=lead["headers"]).status_code == 404
    assert client.get(f"/api/employees/{staff}/documents", headers=lead["headers"]).status_code == 404


def test_self_and_hr_see_personal_details(client, db):
    company_id, _, staff = _team(db, client)
    me = factories.login_as(db, client, company_id, role_codes="employee", employee_id=staff)
    hr = factories.login_as(db, client, company_id, role_codes="hr_officer")
    for user in (me, hr):
        row = client.get(f"/api/employees/{staff}", headers=user["headers"]).json()["data"]
        assert row["canSeePersonal"] is True and row["phone1"] == "+92 300 1234567"
        assert row["homeAddress"] == "House 1" and row["dateOfBirth"] == "1995-01-02"


def test_edit_without_personal_view_keeps_the_record(client, db):
    company_id, _, staff = _team(db, client)
    editor = factories.login_as(db, client, company_id, role_codes="recruiter")
    fr.execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope, "
                   "reason) SELECT ?, ?, p.id, N'grant', N'company', N'test' FROM auth.permission p "
                   "WHERE p.code = N'employees.directory.edit'", company_id, editor["user_id"])
    shown = client.get(f"/api/employees/{staff}", headers=editor["headers"]).json()["data"]
    keep = ("code", "firstName", "lastName", "branchId", "status", "phone1", "homeAddress", "dateOfBirth", "rowVersion")
    r = client.put(f"/api/employees/{staff}", json={k: shown[k] for k in keep}, headers=editor["headers"])
    assert r.status_code == 200, r.text
    hr = factories.login_as(db, client, company_id, role_codes="hr_officer")
    row = client.get(f"/api/employees/{staff}", headers=hr["headers"]).json()["data"]
    assert row["phone1"] == "+92 300 1234567" and row["homeAddress"] == "House 1"


def test_role_shown_is_the_persons_real_role(client, db):
    company_id = factories.company(db)
    for codes, shown in (("employee,recruiter", "Recruiter"), ("employee,hr_officer", "HR Officer"),
                         ("employee", "Employee"), ("department_head,employee", "Department Head")):
        user = factories.login_as(db, client, company_id, role_codes=codes)
        assert client.get("/api/auth/me", headers=user["headers"]).json()["data"]["role"] == shown, codes


def test_people_named_in_a_flow_can_act(client, db):
    """Who decides a request comes from its flow, so Employee and Executive hold the approval actions."""
    company_id = factories.company(db)
    for role in ("employee", "executive"):
        user = factories.login_as(db, client, company_id, role_codes=role)
        codes = {p["code"] for p in client.get("/api/auth/me", headers=user["headers"]).json()["data"]["permissions"]}
        assert {"requests.approvals.approve", "requests.approvals.reject"} <= codes, role
