"""Talent Management extras: the directory's summary tiles (GET /employees/summary) and the gender and
placement filters of the list, with the list's scope."""
from tests import factories, factories_requests as fr


def _people(db, company_id: int, branch_id: int, department_id: int, manager_id: int | None = None) -> list[int]:
    """Five people: two male, two female (one on probation), one without a gender."""
    ids = []
    for gender, status in (("male", "active"), ("male", "active"), ("female", "active"), ("female", "probation"),
                           (None, "active")):
        emp = factories.employee(db, company_id, branch_id=branch_id, department_id=department_id,
                                 line_manager_id=manager_id)
        fr.execute(db, "UPDATE hr.employee SET gender = ?, status = ? WHERE id = ?", gender, status, emp)
        ids.append(emp)
    return ids


def test_summary_counts_by_gender_and_status(client, db):
    company_id = factories.company(db)
    branch_id = factories.branch(db, company_id)
    department_id = factories.department(db, company_id)
    _people(db, company_id, branch_id, department_id)
    left = factories.employee(db, company_id, branch_id=branch_id, department_id=department_id)
    fr.execute(db, "UPDATE hr.employee SET gender = N'male', status = N'left' WHERE id = ?", left)
    admin = factories.login_as(db, client, company_id, role_codes="company_admin")

    r = client.get("/api/employees/summary", headers=admin["headers"])
    assert r.status_code == 200, r.text
    s = r.json()["data"]
    assert s["total"] == 5
    assert s["byGender"] == {"male": 2, "female": 2, "other": 0, "unspecified": 1}
    assert s["byStatus"] == {"active": 4, "probation": 1, "notice": 0, "left": 0, "inactive": 0}

    # The list's filters apply: inactive people on request, and the gender filter.
    s = client.get("/api/employees/summary?includeInactive=true", headers=admin["headers"]).json()["data"]
    assert s["total"] == 6 and s["byStatus"]["left"] == 1 and s["byGender"]["male"] == 3
    s = client.get("/api/employees/summary?gender=female", headers=admin["headers"]).json()["data"]
    assert s["total"] == 2 and s["byGender"] == {"male": 0, "female": 2, "other": 0, "unspecified": 0}
    assert client.get("/api/employees/summary?gender=unknown", headers=admin["headers"]).status_code == 422

    # Without the directory permission there is no summary.
    nobody = factories.login_as(db, client, company_id, role_codes="")
    assert client.get("/api/employees/summary", headers=nobody["headers"]).status_code == 403


def test_summary_follows_the_list_scope(client, db):
    """A line manager sees their team only, in the list and in the tiles."""
    company_id = factories.company(db)
    branch_id = factories.branch(db, company_id)
    department_id = factories.department(db, company_id)
    manager = fr.person(db, client, company_id, "employee,line_manager", branch_id, department_id, first_name="Mona")
    team = _people(db, company_id, branch_id, department_id, manager_id=manager.employee_id)
    _people(db, company_id, branch_id, department_id)  # not in the team

    listed = client.get("/api/employees?pageSize=100", headers=manager.headers).json()
    summary = client.get("/api/employees/summary", headers=manager.headers).json()["data"]
    assert summary["total"] == listed["meta"]["total"]
    assert set(team) <= {int(e["id"]) for e in listed["data"]}
    assert summary["total"] < 11


def test_list_gender_and_placement_filters(client, db, company, admin):
    branch_id = factories.branch(db, company)
    department_id = factories.department(db, company)
    manager = factories.employee(db, company, branch_id=branch_id, department_id=department_id)
    ids = _people(db, company, branch_id, department_id, manager_id=manager)
    h = admin["headers"]

    r = client.get(f"/api/employees?gender=female&lineManagerId={manager}", headers=h)
    assert r.status_code == 200, r.text
    assert sorted(int(e["id"]) for e in r.json()["data"]) == sorted(ids[2:4])
    assert all(e["gender"] == "female" for e in r.json()["data"])

    r = client.get(f"/api/employees?lineManagerId={manager}&branchId={branch_id}&departmentId={department_id}",
                   headers=h)
    assert r.json()["meta"]["total"] == 5
    # The remaining placement filters are accepted (nobody here has these units).
    for name in ("locationId", "areaId", "divisionId", "jobTitleId", "gradeId", "employmentTypeId",
                 "employeeGroupId"):
        r = client.get(f"/api/employees?lineManagerId={manager}&{name}=999999999", headers=h)
        assert r.status_code == 200 and r.json()["meta"]["total"] == 0, name
