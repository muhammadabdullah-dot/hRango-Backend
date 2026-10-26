"""Users, roles, grants and denials, sessions and the change history (Mini SRS 3.1, ACC-1..16)."""
from tests import factories
from tests import factories_organisation as fo


def _audit_actions(db, entity_type: str, entity_id: int) -> list[str]:
    cur = db.conn.cursor()
    rows = cur.execute("SELECT action_name FROM core.audit_log WHERE entity_type = ? AND entity_id = ? ORDER BY id",
                       entity_type, entity_id).fetchall()
    cur.close()
    return [r.action_name for r in rows]


def test_permission_catalogue(client, db, admin):
    rows = client.get("/api/access/permissions", headers=admin["headers"]).json()["data"]
    by_code = {r["code"]: r for r in rows}
    assert by_code["employees.salary.view"]["isSensitive"] and by_code["employees.bank_accounts.edit"]["isSensitive"]
    assert by_code["employees.identity.view"]["isSensitive"]
    assert not by_code["employees.directory.view"]["isSensitive"]
    assert by_code["organisation.branches.create"]["label"] == "Branches: Add"


def test_user_lifecycle(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company, first_name="Nida", last_name="Shah")
    hr_role = fo.role_id(db, company, "hr_officer")
    email = f"nida.{factories.tag()}@test.local"

    weak = client.post("/api/access/users", headers=h, json={"email": email, "password": "abcdefgh", "employeeId": emp})
    assert weak.status_code == 422 and "password" in weak.json()["fieldErrors"]
    r = client.post("/api/access/users", headers=h,
                    json={"email": email.upper(), "password": "Start@2026", "employeeId": emp, "roleIds": [hr_role]})
    assert r.status_code == 201, r.text
    u = r.json()["data"]
    assert u["email"] == email and u["name"] == "Nida Shah" and [x["code"] for x in u["roles"]] == ["hr_officer"]
    assert [c["id"] for c in u["companies"]] == [str(company)]

    dup = client.post("/api/access/users", headers=h, json={"email": email, "password": "Start@2026",
                                                            "displayName": "Copy"})
    assert dup.status_code == 409 and dup.json()["code"] == "USER_EMAIL_DUPLICATE"
    taken = client.post("/api/access/users", headers=h, json={"email": f"x{factories.tag()}@t.local",
                                                              "password": "Start@2026", "employeeId": emp})
    assert taken.status_code == 409 and taken.json()["code"] == "USER_EMPLOYEE_TAKEN"

    login = client.post("/api/auth/login", json={"email": email, "password": "Start@2026"})
    assert login.status_code == 200
    token_h = {"Authorization": f"Bearer {login.json()['data']['token']}"}

    page = client.get("/api/access/users", params={"q": "Nida Shah"}, headers=h).json()
    assert page["meta"]["total"] == 1 and page["data"][0]["roleNames"] == "HR Officer"

    second = factories.company(db)
    fo.execute(db, "INSERT auth.user_company (user_account_id, company_id) VALUES (?, ?)", admin["user_id"], second)
    # Signing in stamps last_login_at, so read the user again before editing.
    u = client.get(f"/api/access/users/{u['id']}", headers=h).json()["data"]
    edited = client.put(f"/api/access/users/{u['id']}", headers=h,
                        json={"email": email, "employeeId": emp, "companyIds": [second], "rowVersion": u["rowVersion"]})
    assert edited.status_code == 200, edited.text
    assert {c["id"] for c in edited.json()["data"]["companies"]} == {str(company), str(second)}
    foreign = factories.company(db)
    refused = client.put(f"/api/access/users/{u['id']}", headers=h,
                         json={"email": email, "employeeId": emp, "companyIds": [foreign],
                               "rowVersion": edited.json()["data"]["rowVersion"]})
    assert refused.status_code == 403
    stale = client.put(f"/api/access/users/{u['id']}", headers=h,
                       json={"email": email, "employeeId": emp, "rowVersion": u["rowVersion"]})
    assert stale.status_code == 409

    effective = client.get(f"/api/access/users/{u['id']}/permissions", headers=h).json()["data"]
    assert "employees.directory.view" in {p["code"] for p in effective}
    assert not any(p["code"].startswith("access.") for p in effective)

    off = client.patch(f"/api/access/users/{u['id']}/disable", headers=h,
                       json={"rowVersion": edited.json()["data"]["rowVersion"]})
    assert off.status_code == 200 and not off.json()["data"]["isActive"]
    assert client.get("/api/auth/me", headers=token_h).status_code == 401
    on = client.patch(f"/api/access/users/{u['id']}/enable", headers=h,
                      json={"rowVersion": off.json()["data"]["rowVersion"]})
    assert on.json()["data"]["isActive"]

    assert client.put(f"/api/access/users/{u['id']}/password", headers=h, json={"password": "Reset@2026"}).status_code == 204
    assert client.post("/api/auth/login", json={"email": email, "password": "Reset@2026"}).status_code == 200
    assert _audit_actions(db, "auth.user_account", int(u["id"]))[:2] == ["create", "role_added"]


def test_acc11_self_and_admin_rules(client, db, company):
    me = factories.login_as(db, client, company, role_codes="company_admin")
    h = me["headers"]
    mine = client.get(f"/api/access/users/{me['user_id']}", headers=h).json()["data"]
    own_roles = client.put(f"/api/access/users/{me['user_id']}/roles", headers=h,
                           json={"roleIds": [], "rowVersion": mine["rowVersion"]})
    assert own_roles.status_code == 403
    own_off = client.patch(f"/api/access/users/{me['user_id']}/disable", headers=h, json={"rowVersion": mine["rowVersion"]})
    assert own_off.status_code == 403
    make_admin = client.post("/api/access/users", headers=h, json={"email": f"a{factories.tag()}@t.local",
                                                                   "password": "Start@2026", "displayName": "Root",
                                                                   "isSystemAdmin": True})
    assert make_admin.status_code == 403
    sysadmin_id, _ = factories.user(db, company, role_codes="", is_system_admin=True)
    target = client.get(f"/api/access/users/{sysadmin_id}", headers=h).json()["data"]
    assert client.put(f"/api/access/users/{sysadmin_id}/password", headers=h,
                      json={"password": "Reset@2026"}).status_code == 403
    assert client.patch(f"/api/access/users/{sysadmin_id}/disable", headers=h,
                        json={"rowVersion": target["rowVersion"]}).status_code == 403
    own_grant = client.put(f"/api/access/users/{me['user_id']}/overrides", headers=h,
                           json={"code": "payroll.payrolls.view", "effect": "deny"})
    assert own_grant.status_code in (403, 422)


def test_cannot_grant_what_you_do_not_hold(client, db, company):
    # A user administrator who holds the access screens but no employee permissions.
    deputy = factories.login_as(db, client, company)
    for code in ("access.users.view", "access.users.edit", "access.roles.view", "access.roles.edit",
                 "access.roles.assign", "access.overrides.edit", "organisation.branches.view"):
        fo.override(db, deputy["user_id"], code)
    fo.override(db, deputy["user_id"], "organisation.departments.view", scope="team")
    h = deputy["headers"]
    target_id, _ = factories.user(db, company)
    target = client.get(f"/api/access/users/{target_id}", headers=h).json()["data"]

    too_much = client.put(f"/api/access/users/{target_id}/roles", headers=h,
                          json={"roleIds": [fo.role_id(db, company, "company_admin")], "rowVersion": target["rowVersion"]})
    assert too_much.status_code == 403 and too_much.json()["code"] == "ROLE_EXCEEDS_YOUR_ACCESS"

    grant = client.put(f"/api/access/users/{target_id}/overrides", headers=h,
                       json={"code": "employees.salary.view", "effect": "grant", "scope": "company"})
    assert grant.status_code == 403
    wider = client.put(f"/api/access/users/{target_id}/overrides", headers=h,
                       json={"code": "organisation.departments.view", "effect": "grant", "scope": "company"})
    assert wider.status_code == 403
    ok = client.put(f"/api/access/users/{target_id}/overrides", headers=h,
                    json={"code": "organisation.branches.view", "effect": "grant", "scope": "company",
                          "reason": "Covers for the admin"})
    assert ok.status_code == 200, ok.text

    role = client.post("/api/access/roles", headers=factories.login_as(db, client, company,
                                                                       role_codes="company_admin")["headers"],
                       json={"name": f"Auditors {factories.tag()}"}).json()["data"]
    tick = client.put(f"/api/access/roles/{role['id']}/permissions", headers=h,
                      json={"permissions": [{"code": "employees.salary.view", "scope": "company"}],
                            "rowVersion": role["rowVersion"]})
    assert tick.status_code == 403 and tick.json()["code"] == "PERMISSION_NOT_HELD"


def test_roles(client, db, company, admin):
    h = admin["headers"]
    name = f"Branch Clerks {factories.tag()}"
    role = client.post("/api/access/roles", headers=h, json={"name": name, "description": "Front desk"}).json()["data"]
    assert role["permissionCount"] == 0 and not role["isSystem"] and role["code"].startswith("custom_")
    dup = client.post("/api/access/roles", headers=h, json={"name": name.lower()})
    assert dup.status_code == 409 and dup.json()["code"] == "ROLE_DUPLICATE"

    branch = factories.branch(db, company)
    other_branch = factories.branch(db, company)
    no_units = client.put(f"/api/access/roles/{role['id']}/permissions", headers=h,
                          json={"permissions": [{"code": "employees.directory.view", "scope": "selected_units"}],
                                "rowVersion": role["rowVersion"]})
    assert no_units.status_code == 422
    unknown = client.put(f"/api/access/roles/{role['id']}/permissions", headers=h,
                         json={"permissions": [{"code": "nope.nope.view", "scope": "own"}],
                               "rowVersion": role["rowVersion"]})
    assert unknown.status_code == 422
    ticked = client.put(f"/api/access/roles/{role['id']}/permissions", headers=h,
                        json={"permissions": [
                            {"code": "employees.directory.view", "scope": "selected_units",
                             "units": [{"unitType": "branch", "unitId": branch}]},
                            {"code": "dashboard.hr.view", "scope": "company"}],
                            "rowVersion": role["rowVersion"]})
    assert ticked.status_code == 200, ticked.text
    t = ticked.json()["data"]
    assert t["permissionCount"] == 2
    view = next(p for p in t["permissions"] if p["code"] == "employees.directory.view")
    assert view["units"][0]["unitId"] == str(branch) and view["units"][0]["unitName"]
    stale = client.put(f"/api/access/roles/{role['id']}", headers=h, json={"name": name, "rowVersion": role["rowVersion"]})
    assert stale.status_code == 409

    # A holder of the role sees exactly the employees of the selected branch.
    clerk_id, clerk_email = factories.user(db, company)
    clerk_user = client.get(f"/api/access/users/{clerk_id}", headers=h).json()["data"]
    assigned = client.put(f"/api/access/users/{clerk_id}/roles", headers=h,
                          json={"roleIds": [int(role["id"])], "rowVersion": clerk_user["rowVersion"]})
    assert assigned.status_code == 200 and assigned.json()["data"]["roles"][0]["name"] == name
    inside = factories.employee(db, company, branch_id=branch)
    outside = factories.employee(db, company, branch_id=other_branch)
    token = client.post("/api/auth/login", json={"email": clerk_email, "password": factories.PASSWORD}).json()["data"]["token"]
    ch = {"Authorization": f"Bearer {token}"}
    seen = {e["id"] for e in client.get("/api/employees", params={"pageSize": 100}, headers=ch).json()["data"]}
    assert str(inside) in seen and str(outside) not in seen

    copy = client.post(f"/api/access/roles/{role['id']}/copy", headers=h, json={"name": f"{name} copy"})
    assert copy.status_code == 201 and copy.json()["data"]["permissionCount"] == 2

    in_use = client.delete(f"/api/access/roles/{role['id']}", params={"rowVersion": t["rowVersion"]}, headers=h)
    assert in_use.status_code == 409
    retired = client.patch(f"/api/access/roles/{role['id']}/retire", headers=h, json={"rowVersion": t["rowVersion"]})
    assert retired.status_code == 200 and not retired.json()["data"]["isActive"]
    assert client.get("/api/employees", headers=ch).status_code == 403
    listed = client.get("/api/access/roles", params={"q": name}, headers=h).json()
    assert listed["meta"]["total"] == 1  # the copy; the retired one is hidden
    assert client.get("/api/access/roles", params={"q": name, "includeRetired": True},
                      headers=h).json()["meta"]["total"] == 2

    c = copy.json()["data"]
    assert client.delete(f"/api/access/roles/{c['id']}", params={"rowVersion": c["rowVersion"]}, headers=h).status_code == 204
    system = client.get(f"/api/access/roles/{fo.role_id(db, company, 'employee')}", headers=h).json()["data"]
    assert client.delete(f"/api/access/roles/{system['id']}", params={"rowVersion": system["rowVersion"]},
                         headers=h).status_code == 409

    actions = _audit_actions(db, "auth.role", int(role["id"]))
    assert actions[0] == "create" and actions.count("permission_added") == 2 and actions[-1] == "retire"
    history = client.get("/api/access/audit", params={"entity": "role", "entityId": role["id"]}, headers=h).json()
    assert history["meta"]["total"] == len(actions) and history["data"][0]["entityName"] == name


def test_overrides(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company)
    person = factories.login_as(db, client, company, role_codes="hr_manager", employee_id=emp)
    assert client.get("/api/organisation/departments", headers=person["headers"]).status_code == 200

    deny = client.put(f"/api/access/users/{person['user_id']}/overrides", headers=h,
                      json={"code": "organisation.departments.view", "effect": "deny", "reason": "Not needed"})
    assert deny.status_code == 200 and deny.json()["data"]["scope"] is None
    assert client.get("/api/organisation/departments", headers=person["headers"]).status_code == 403
    no_scope = client.put(f"/api/access/users/{person['user_id']}/overrides", headers=h,
                          json={"code": "access.users.view", "effect": "grant"})
    assert no_scope.status_code == 422
    grant = client.put(f"/api/access/users/{person['user_id']}/overrides", headers=h,
                       json={"code": "access.users.view", "effect": "grant", "scope": "company"}).json()["data"]
    assert client.get("/api/access/users", headers=person["headers"]).status_code == 200

    listed = client.get(f"/api/access/users/{person['user_id']}/overrides", headers=h).json()["data"]
    assert {o["code"]: o["effect"] for o in listed} == {"organisation.departments.view": "deny",
                                                         "access.users.view": "grant"}
    d = deny.json()["data"]
    assert client.delete(f"/api/access/users/{person['user_id']}/overrides/{d['id']}", headers=h,
                         params={"rowVersion": d["rowVersion"]}).status_code == 204
    assert client.get("/api/organisation/departments", headers=person["headers"]).status_code == 200
    assert client.delete(f"/api/access/users/{person['user_id']}/overrides/{grant['id']}", headers=h,
                         params={"rowVersion": "0000000000000000"}).status_code == 409
    actions = _audit_actions(db, "auth.user_account", person["user_id"])
    assert actions == ["override_deny", "override_grant", "override_removed"]


def test_sessions_and_own_password(client, db, company, admin):
    h = admin["headers"]
    person = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    second = client.post("/api/auth/login", json={"email": person["email"], "password": factories.PASSWORD}).json()["data"]
    second_h = {"Authorization": f"Bearer {second['token']}"}

    sessions = client.get("/api/access/sessions", params={"userId": person["user_id"]}, headers=h).json()
    assert sessions["meta"]["total"] == 2 and all(s["isActive"] for s in sessions["data"])
    ended = client.patch(f"/api/access/sessions/{sessions['data'][0]['id']}/end", headers=h).json()["data"]
    assert ended["ended"] == 1
    still = [hh for hh in (person["headers"], second_h) if client.get("/api/auth/me", headers=hh).status_code == 200]
    assert len(still) == 1

    wrong = client.post("/api/access/me/password", headers=still[0],
                        json={"currentPassword": "nope", "newPassword": "Fresh@2026"})
    assert wrong.status_code == 422 and "currentPassword" in wrong.json()["fieldErrors"]
    ok = client.post("/api/access/me/password", headers=still[0],
                     json={"currentPassword": factories.PASSWORD, "newPassword": "Fresh@2026"})
    assert ok.status_code == 204
    assert client.get("/api/auth/me", headers=still[0]).status_code == 200
    assert client.post("/api/auth/login", json={"email": person["email"], "password": "Fresh@2026"}).status_code == 200

    all_ended = client.patch(f"/api/access/users/{person['user_id']}/sessions/end", headers=h).json()["data"]
    assert all_ended["ended"] >= 1
    assert client.get("/api/auth/me", headers=still[0]).status_code == 401
    assert client.get("/api/access/sessions", headers=person["headers"]).status_code == 401
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    assert client.get("/api/access/sessions", headers=staff["headers"]).status_code == 403
