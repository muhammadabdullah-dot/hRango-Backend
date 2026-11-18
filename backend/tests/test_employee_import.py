"""Bulk employee import from CSV (roadmap 1.1): check everything first, then import all or nothing."""
from tests import factories


def _setup(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    t = factories.tag()
    branch = f"Head Office {t}"
    dept = f"Finance {t}"
    factories.branch(db, company, name=branch)
    factories.department(db, company, name=dept)
    return company, admin["headers"], branch, dept, t


def _post(client, headers, text, dry_run=False):
    return client.post("/api/employees/import", params={"dryRun": str(dry_run).lower()}, content=text.encode("utf-8"),
                       headers={**headers, "Content-Type": "text/csv"})


def test_the_template_lists_the_columns(client, db):
    _, h, *_ = _setup(db, client)
    r = client.get("/api/employees/import/template", headers=h)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    header = r.text.splitlines()[0]
    assert header.startswith("First Name,Last Name,Joining Date,Branch,Code")
    assert "Line Manager Code" in header


def test_a_clean_file_imports_everyone_with_managers_from_the_same_file(client, db):
    company, h, branch, dept, t = _setup(db, client)
    text = ("First Name,Last Name,Joining Date,Branch,Department,Code,Email,Gender,Line Manager Code,Notes\n"
            f"Sara,Malik,2026-01-05,{branch},{dept},A{t},sara.{t}@x.test,female,,keep\n"
            f"Omar,Iqbal,05/02/2026,{branch.upper()},,B{t},omar.{t}@x.test,male,A{t},\n")
    checked = _post(client, h, text, dry_run=True)
    assert checked.status_code == 200, checked.text
    report = checked.json()["data"]
    assert report == {"total": 2, "created": 0, "dryRun": True, "errors": [], "ignoredColumns": ["Notes"]}
    assert client.get("/api/employees", headers=h, params={"q": f"A{t}"}).json()["meta"]["total"] == 0

    done = _post(client, h, text).json()["data"]
    assert done["created"] == 2 and done["errors"] == []
    people = {e["code"]: e for e in client.get("/api/employees", headers=h, params={"pageSize": 50}).json()["data"]}
    sara, omar = people[f"A{t}"], people[f"B{t}"]
    detail = client.get(f"/api/employees/{omar['id']}", headers=h).json()["data"]
    assert detail["lineManagerId"] == sara["id"] and detail["joiningDate"] == "2026-02-05"


def test_every_problem_is_reported_and_nothing_imported(client, db):
    company, h, branch, dept, t = _setup(db, client)
    text = ("First Name,Last Name,Joining Date,Branch,Email,Gender,Status,Code,Line Manager Code\n"
            f"Ali,,2026-01-05,{branch},ali.{t}@x.test,male,active,C{t},\n"          # no last name
            f"Hina,Raza,yesterday,{branch},hina.{t}@x.test,f,left,C{t},\n"           # date, gender, status, code repeated
            f"Zain,Butt,2026-01-05,Nowhere,ali.{t}@x.test,,,D{t},Z{t}\n")           # branch, email repeated, manager
    report = _post(client, h, text).json()["data"]
    assert report["created"] == 0
    found = {(e["row"], e["column"]) for e in report["errors"]}
    assert {(2, "Last Name"), (3, "Joining Date"), (3, "Gender"), (3, "Status"), (3, "Code"),
            (4, "Branch"), (4, "Email"), (4, "Line Manager Code")} <= found
    assert client.get("/api/employees", headers=h, params={"q": f"ali.{t}"}).json()["meta"]["total"] == 0


def test_missing_columns_and_bad_files_are_refused(client, db):
    _, h, *_ = _setup(db, client)
    r = _post(client, h, "First Name,Last Name\nA,B\n")
    assert r.status_code == 422 and "Joining Date" in r.json()["message"]
    assert _post(client, h, "").status_code == 422
    r = client.post("/api/employees/import", content=b"\xff\xfe\x00bad", headers={**h, "Content-Type": "text/csv"})
    assert r.status_code == 422


def test_only_people_who_may_add_employees_can_import(client, db):
    company, _, branch, _, t = _setup(db, client)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    r = _post(client, staff["headers"], f"First Name,Last Name,Joining Date,Branch\nA,B,2026-01-05,{branch}\n")
    assert r.status_code == 403
