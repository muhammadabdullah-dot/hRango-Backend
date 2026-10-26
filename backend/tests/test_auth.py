from tests import factories


def test_login_me_logout(client, db, company):
    emp = factories.employee(db, company, first_name="Amna", last_name="Tariq")
    user_id, email = factories.user(db, company, employee_id=emp, role_codes="hr_manager")

    bad = client.post("/api/auth/login", json={"email": email, "password": "wrong"})
    assert bad.status_code == 401
    assert bad.json() == {"message": "Incorrect email or password.", "code": "INVALID_CREDENTIALS"}

    r = client.post("/api/auth/login", json={"email": email.upper(), "password": factories.PASSWORD})
    assert r.status_code == 200, r.text
    session = r.json()["data"]
    assert session["user"]["name"] == "Amna Tariq"
    assert session["user"]["role"] == "HR Manager"
    assert session["user"]["id"] == str(user_id)
    codes = {p["code"] for p in session["user"]["permissions"]}
    assert "organisation.departments.view" in codes
    assert not any(c.startswith("access.") for c in codes)

    headers = {"Authorization": f"Bearer {session['token']}"}
    assert client.get("/api/auth/me", headers=headers).status_code == 200
    assert client.post("/api/auth/logout", headers=headers).status_code == 204
    assert client.get("/api/auth/me", headers=headers).status_code == 401


def test_no_or_bad_token(client):
    assert client.get("/api/auth/me").json()["code"] == "UNAUTHENTICATED"
    assert client.get("/api/auth/me", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_permission_and_denial(client, db, company):
    emp = factories.employee(db, company)
    plain = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    r = client.post("/api/organisation/departments", json={"name": "Nope"}, headers=plain["headers"])
    assert r.status_code == 403 and r.json()["code"] == "FORBIDDEN"

    hr = factories.login_as(db, client, company, role_codes="hr_manager")
    assert client.get("/api/organisation/departments", headers=hr["headers"]).status_code == 200
    perm = db.call("auth.usp_permission_check", company_id=company, user_id=hr["user_id"],
                   code="organisation.departments.view")[0]
    assert perm["allowed"] and perm["scopes"] == "company"
    cur = db.conn.cursor()
    cur.execute("INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect) "
                "SELECT ?, ?, id, N'deny' FROM auth.permission WHERE code = N'organisation.departments.view'",
                company, hr["user_id"])
    cur.close()
    assert client.get("/api/organisation/departments", headers=hr["headers"]).status_code == 403


def test_visible_employees_by_scope(db, company):
    """Team scope reaches direct and indirect reports; department scope reaches sub-departments."""
    parent = factories.department(db, company)
    child = factories.department(db, company, parent_id=parent)
    other = factories.department(db, company)
    boss = factories.employee(db, company, department_id=parent)
    mid = factories.employee(db, company, department_id=child, line_manager_id=boss)
    low = factories.employee(db, company, department_id=child, line_manager_id=mid)
    outsider = factories.employee(db, company, department_id=other)

    def visible(user_id: int) -> set[int]:
        cur = db.conn.cursor()
        rows = cur.execute("SELECT employee_id FROM auth.fn_visible_employees(?, ?, N'organisation.departments.view')",
                           company, user_id).fetchall()
        cur.close()
        return {r.employee_id for r in rows}

    def granted(employee_id: int, scope: str) -> int:
        user_id, _ = factories.user(db, company, employee_id=employee_id)
        cur = db.conn.cursor()
        cur.execute("INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope) "
                    "SELECT ?, ?, id, N'grant', ? FROM auth.permission WHERE code = N'organisation.departments.view'",
                    company, user_id, scope)
        cur.close()
        return user_id

    assert visible(granted(boss, "team")) == {boss, mid, low}
    assert visible(granted(mid, "department")) == {mid, low}
    assert visible(granted(boss, "department")) == {boss, mid, low}
    assert visible(granted(low, "own")) == {low}
    assert outsider in visible(granted(low, "company"))
    assert visible(factories.user(db, company, employee_id=low)[0]) == set()


def test_personal_grant_stays_in_its_company(client, db, company):
    """A grant given in one company does not reach another company the user also belongs to."""
    other = factories.company(db)
    user_id, email = factories.user(db, company)
    cur = db.conn.cursor()
    cur.execute("INSERT auth.user_company (user_account_id, company_id) VALUES (?, ?)", user_id, other)
    cur.execute("INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope) "
                "SELECT ?, ?, id, N'grant', N'company' FROM auth.permission WHERE code = N'organisation.departments.view'",
                company, user_id)
    cur.close()
    token = client.post("/api/auth/login", json={"email": email, "password": factories.PASSWORD}).json()["data"]["token"]
    h = {"Authorization": f"Bearer {token}"}
    assert client.get("/api/organisation/departments", headers=h).status_code == 200
    assert client.get("/api/organisation/departments", headers={**h, "X-Company-Id": str(other)}).status_code == 403
