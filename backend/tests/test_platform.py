"""Platform staff are separate from customers: their own accounts and tokens, no reach into a company, and no
customer account can reach another customer."""
from app.core.db import Db
from app.core.security import hash_password
from tests import factories

PASSWORD = "Platform@2026!"


def staff(db: Db, client, role: str = "super_admin") -> dict:
    email = f"staff.{factories.tag()}@hrango.test"
    row = db.call_one("plat.usp_staff_save", actor_id=None, id=None, email=email, display_name=f"Staff {role}",
                      role=role, is_active=True, password_hash=hash_password(PASSWORD), row_version=None)
    r = client.post("/api/platform/auth/login", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return {"id": row["id"], "email": email, "headers": {"Authorization": f"Bearer {r.json()['data']['token']}"}}


def test_sign_in_me_and_sign_out(client, db):
    me = staff(db, client, "support")
    r = client.get("/api/platform/auth/me", headers=me["headers"])
    assert r.status_code == 200 and r.json()["data"]["role"] == "support"
    bad = client.post("/api/platform/auth/login", json={"email": me["email"], "password": "wrong-password"})
    assert bad.status_code == 401
    assert client.post("/api/platform/auth/logout", headers=me["headers"]).status_code == 204
    assert client.get("/api/platform/auth/me", headers=me["headers"]).status_code == 401


def test_tokens_do_not_cross_between_staff_and_customers(client, db):
    company = factories.company(db)
    customer = factories.login_as(db, client, company, role_codes="company_admin")
    me = staff(db, client)
    assert client.get("/api/platform/staff", headers=customer["headers"]).status_code == 401
    assert client.get("/api/platform/auth/me", headers=customer["headers"]).status_code == 401
    assert client.get("/api/auth/me", headers=me["headers"]).status_code == 401
    assert client.get("/api/employees", headers=me["headers"]).status_code == 401
    assert client.get("/api/employees", headers={**me["headers"], "X-Company-Id": str(company)}).status_code == 401
    # A staff email does not sign in as a customer, nor the other way round.
    assert client.post("/api/auth/login", json={"email": me["email"], "password": PASSWORD}).status_code == 401
    assert client.post("/api/platform/auth/login",
                       json={"email": customer["email"], "password": factories.PASSWORD}).status_code == 401


def test_a_company_administrator_stays_inside_their_company(client, db):
    mine, other = factories.company(db), factories.company(db)
    admin = factories.login_as(db, client, mine, role_codes="company_admin")
    listed = client.get("/api/organisation/companies?pageSize=100", headers=admin["headers"]).json()["data"]
    assert [c["id"] for c in listed] == [str(mine)]
    assert client.get(f"/api/organisation/companies/{other}", headers=admin["headers"]).status_code == 404
    assert client.get("/api/employees", headers={**admin["headers"], "X-Company-Id": str(other)}).status_code == 403


def test_customers_cannot_set_the_old_flag(client, db):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    r = client.post("/api/access/users", headers=admin["headers"], json={
        "email": f"new.{factories.tag()}@t.local", "password": "Start@2026", "displayName": "New",
        "isSystemAdmin": True})
    assert r.status_code == 201
    assert "isSystemAdmin" not in r.json()["data"]
    assert client.get("/api/organisation/companies", headers=admin["headers"]).json()["meta"]["total"] == 1


def test_only_a_super_admin_manages_staff(client, db):
    root, admin, support = staff(db, client), staff(db, client, "admin"), staff(db, client, "support")
    body = {"email": f"new.{factories.tag()}@hrango.test", "displayName": "New", "role": "billing",
            "password": "Long-enough-2026"}
    assert client.post("/api/platform/staff", json=body, headers=admin["headers"]).status_code == 403
    assert client.get("/api/platform/staff", headers=support["headers"]).status_code == 403
    assert client.get("/api/platform/staff", headers=admin["headers"]).status_code == 200
    r = client.post("/api/platform/staff", json=body, headers=root["headers"])
    assert r.status_code == 201, r.text
    assert "passwordHash" not in r.json()["data"]
    weak = {**body, "email": f"w.{factories.tag()}@hrango.test", "password": "onlyletterslong"}
    assert client.post("/api/platform/staff", json=weak, headers=root["headers"]).status_code == 422


def test_nobody_locks_the_platform_out(client, db):
    root = staff(db, client)
    mine = client.get(f"/api/platform/staff/{root['id']}", headers=root["headers"]).json()["data"]
    change = {k: mine[k] for k in ("email", "displayName", "rowVersion")}
    assert client.put(f"/api/platform/staff/{root['id']}", headers=root["headers"],
                      json={**change, "role": "support"}).status_code == 403
    assert client.put(f"/api/platform/staff/{root['id']}", headers=root["headers"],
                      json={**change, "role": "super_admin", "isActive": False}).status_code == 403


def test_switching_off_or_a_new_password_ends_sessions(client, db):
    root, other = staff(db, client), staff(db, client, "support")
    assert client.put(f"/api/platform/staff/{other['id']}/password", headers=root["headers"],
                      json={"password": "Another-long-2026"}).status_code == 204
    assert client.get("/api/platform/auth/me", headers=other["headers"]).status_code == 401
    log = client.get("/api/platform/audit?pageSize=20", headers=root["headers"]).json()["data"]
    assert "staff_password_set" in [x["actionName"] for x in log]


def test_executives_see_salaries_but_not_identity_or_bank(client, db):
    company = factories.company(db)
    ceo = factories.login_as(db, client, company, role_codes="executive")
    held = {p["code"]: p["scope"] for p in client.get("/api/auth/me", headers=ceo["headers"]).json()["data"]["permissions"]}
    for code in ("employees.salary.view", "payroll.payslips.view", "payroll.salary_sheet.view",
                 "payroll.salary_revision.view"):
        assert held.get(code) == "company", code
    for code in ("employees.identity.view", "employees.bank_accounts.view", "benefits.health.view"):
        assert code not in held, code
