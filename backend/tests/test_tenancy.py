"""Phase 0 tenancy rules: suspension reaches every door (roadmap 0.3), companies a customer creates join it
(0.4), company creation, editing and names (BE-06 b-d), and who may change whose sign-in (BE-04)."""
import pytest

from app.core.config import settings
from app.services.webhook_dispatcher import dispatch_once
from tests import factories
from tests import factories_projects as pm
from tests.test_integrations import Receiver
from tests.test_organisation import _general
from tests.test_platform import staff
from tests.test_platform_portal import OWNER_PASSWORD, org


def _execute(db, sql, *params):
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def _scalar(db, sql, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def _owner(client, body) -> dict:
    r = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['data']['token']}"}


def _set_status(client, me, row, status) -> dict:
    r = client.patch(f"/api/platform/organisations/{row['id']}/status", headers=me["headers"],
                     json={"status": status, "rowVersion": row["rowVersion"]})
    assert r.status_code == 200, r.text
    return r.json()["data"]


def _link(db, company_id: int, customer_id) -> None:
    _execute(db, "INSERT plat.customer_company (customer_id, company_id) VALUES (?, ?)", int(customer_id), company_id)


@pytest.fixture()
def me(db, client):
    return staff(db, client)


# ---------------------------------------------------------------- 0.4 and BE-06: companies

def test_a_company_the_customer_creates_joins_the_customer(client, db, me):
    row, body = org(client, me["headers"])
    owner = _owner(client, body)
    name = f"Dubai FZ-LLC {factories.tag()}"
    created = client.post("/api/organisation/companies", headers=owner, json=_general(name, currency="AED"))
    assert created.status_code == 201, created.text
    listed = client.get(f"/api/platform/organisations/{row['id']}/companies", headers=me["headers"]).json()["data"]
    assert {c["name"] for c in listed} == {body["name"], name}
    assert _scalar(db, "SELECT customer_id FROM plat.customer_company WHERE company_id = ?",
                   int(created.json()["data"]["id"])) == int(row["id"])


def test_company_names_are_unique_within_one_customer_only(client, me):
    name = f"Head Office {factories.tag()}"
    _, body_a = org(client, me["headers"])
    _, body_b = org(client, me["headers"])
    owner_a, owner_b = _owner(client, body_a), _owner(client, body_b)
    assert client.post("/api/organisation/companies", headers=owner_a, json=_general(name)).status_code == 201
    # Another customer may use the same name, and learns nothing about the first.
    assert client.post("/api/organisation/companies", headers=owner_b, json=_general(name)).status_code == 201
    dup = client.post("/api/organisation/companies", headers=owner_a, json=_general(name.upper()))
    assert dup.status_code == 409 and dup.json()["code"] == "COMPANY_DUPLICATE"


def test_an_hr_manager_does_not_create_companies(client, db):
    company = factories.company(db)
    hr = factories.login_as(db, client, company, role_codes="hr_manager")["headers"]
    r = client.post("/api/organisation/companies", headers=hr, json=_general(f"Side Co {factories.tag()}"))
    assert r.status_code == 403
    # The rest of organisation set-up stays with HR.
    assert client.get("/api/organisation/general", headers=hr).status_code == 200


def test_editing_another_company_needs_the_permission_there(client, db):
    home, other = factories.company(db), factories.company(db)
    admin = factories.login_as(db, client, home, role_codes="company_admin")
    _execute(db, "INSERT auth.user_company (user_account_id, company_id) VALUES (?, ?)", admin["user_id"], other)
    target = client.get(f"/api/organisation/companies/{other}", headers=admin["headers"])
    assert target.status_code == 200, target.text
    data = target.json()["data"]
    r = client.put(f"/api/organisation/companies/{other}", headers=admin["headers"],
                   json=_general(data["organizationName"], rowVersion=data["rowVersion"]))
    assert r.status_code == 403
    # With the permission in that company it works.
    _execute(db, "INSERT auth.user_role (user_account_id, role_id) SELECT ?, id FROM auth.role "
                 "WHERE company_id = ? AND code = N'company_admin'", admin["user_id"], other)
    r = client.put(f"/api/organisation/companies/{other}", headers=admin["headers"],
                   json=_general(data["organizationName"], rowVersion=data["rowVersion"]))
    assert r.status_code == 200, r.text


# ---------------------------------------------------------------- 0.3: suspension reaches every door

def test_switching_into_a_suspended_company_is_refused(client, db, me):
    row, _ = org(client, me["headers"])
    suspended_company = factories.company(db)
    _link(db, suspended_company, row["id"])
    visitor = factories.login_as(db, client, factories.company(db), role_codes="company_admin")
    _execute(db, "INSERT auth.user_company (user_account_id, company_id) VALUES (?, ?)", visitor["user_id"],
             suspended_company)
    there = {**visitor["headers"], "X-Company-Id": str(suspended_company)}
    assert client.get("/api/auth/me", headers=there).status_code == 200

    row = _set_status(client, me, row, "suspended")
    refused = client.get("/api/auth/me", headers=there)
    assert refused.status_code == 403 and "suspended" in refused.json()["message"]
    assert client.get("/api/auth/me", headers=visitor["headers"]).status_code == 200  # own company still works

    _set_status(client, me, row, "active")
    assert client.get("/api/auth/me", headers=there).status_code == 200


def test_webhooks_wait_while_suspended(client, db, me, monkeypatch):
    monkeypatch.setattr(settings, "webhook_allow_private", True)
    receiver = Receiver()
    try:
        row, _ = org(client, me["headers"])
        company = factories.company(db)
        _link(db, company, row["id"])
        admin = factories.login_as(db, client, company, role_codes="company_admin")
        hook = client.post("/api/integrations/webhooks", headers=admin["headers"], json={
            "name": f"Hold {factories.tag()}", "url": receiver.url, "events": ["notification.*"]})
        assert hook.status_code == 201, hook.text

        row = _set_status(client, me, row, "suspended")
        db.call("core.usp_event_publish", company_id=company, event_type="notification.created", payload="{}")
        while dispatch_once(db):
            pass
        assert receiver.received == []

        _set_status(client, me, row, "active")
        while dispatch_once(db):
            pass
        assert len(receiver.received) == 1
    finally:
        receiver.close(db)


def test_public_share_links_close_while_suspended(client, db, me):
    row, _ = org(client, me["headers"])
    company = factories.company(db)
    _link(db, company, row["id"])
    dept = factories.department(db, company)
    owner = pm.person(db, client, company, dept, first_name="Owner")
    ws = pm.workspace(client, owner["headers"], dept, owner["employee_id"], privacy="workspace")
    task = pm.task(client, owner["headers"], ws["id"], name="Shared plan")
    share = client.put("/api/projects/shares", headers=owner["headers"], json={
        "entityType": "task", "entityId": int(task["id"]), "isPublic": True, "properties": ["assignee"]})
    assert share.status_code == 200, share.text
    token = share.json()["data"]["token"]
    assert client.get(f"/api/public/shares/{token}").status_code == 200

    row = _set_status(client, me, row, "suspended")
    assert client.get(f"/api/public/shares/{token}").status_code == 404

    _set_status(client, me, row, "active")
    assert client.get(f"/api/public/shares/{token}").status_code == 200


def test_nightly_jobs_and_reminders_skip_suspended_companies(client, db, me):
    row, _ = org(client, me["headers"])
    company = factories.company(db)
    _link(db, company, row["id"])
    assert _scalar(db, "SELECT plat.fn_company_blocked(?)", company) is False
    row = _set_status(client, me, row, "suspended")
    assert _scalar(db, "SELECT plat.fn_company_blocked(?)", company) is True
    # The nightly script's company list leaves it out.
    listed = _scalar(db, "SELECT COUNT(*) FROM org.company WHERE id = ? AND plat.fn_company_blocked(id) = 0", company)
    assert listed == 0
    _set_status(client, me, row, "cancelled")
    assert _scalar(db, "SELECT plat.fn_company_blocked(?)", company) is True


# ---------------------------------------------------------------- BE-04: whose sign-in may be changed

def _helpdesk(db, client, company):
    helpdesk = factories.login_as(db, client, company)
    for code in ("access.users.view", "access.users.edit"):
        _execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, "
                     "scope, reason) SELECT ?, ?, p.id, N'grant', N'company', N'test' FROM auth.permission p "
                     "WHERE p.code = ?", company, helpdesk["user_id"], code)
    return helpdesk


@pytest.mark.parametrize("role", ["payroll_manager", "hr_manager", "hr_officer"])
def test_a_helpdesk_cannot_take_over_payroll_or_hr(client, db, role):
    company = factories.company(db)
    helpdesk = _helpdesk(db, client, company)
    target_id, _ = factories.user(db, company, role_codes=role)
    r = client.put(f"/api/access/users/{target_id}/password", headers=helpdesk["headers"], json={"password": "Reset@2026"})
    assert r.status_code == 403 and r.json()["code"] == "ACCOUNT_PROTECTED"
    ended = client.patch(f"/api/access/users/{target_id}/sessions/end", headers=helpdesk["headers"])
    assert ended.status_code == 403


def test_nobody_relinks_their_own_account_to_another_employee(client, db):
    company = factories.company(db)
    me_ = factories.login_as(db, client, company, role_codes="company_admin",
                             employee_id=factories.employee(db, company))
    someone = factories.employee(db, company, first_name="Victim")
    mine = client.get(f"/api/access/users/{me_['user_id']}", headers=me_["headers"]).json()["data"]
    r = client.put(f"/api/access/users/{me_['user_id']}", headers=me_["headers"], json={
        "email": mine["email"], "displayName": mine.get("displayName"), "employeeId": str(someone),
        "rowVersion": mine["rowVersion"]})
    assert r.status_code == 403 and "employeeId" in r.json()["fieldErrors"]


def test_only_the_home_company_changes_a_sign_in(client, db):
    home, other = factories.company(db), factories.company(db)
    person_id, _ = factories.user(db, home, role_codes="employee")
    _execute(db, "INSERT auth.user_company (user_account_id, company_id) VALUES (?, ?)", person_id, other)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    h = other_admin["headers"]

    r = client.put(f"/api/access/users/{person_id}/password", headers=h, json={"password": "Reset@2026"})
    assert r.status_code == 403 and r.json()["code"] == "ACCOUNT_HOME_ONLY"
    target = client.get(f"/api/access/users/{person_id}", headers=h).json()["data"]
    r = client.put(f"/api/access/users/{person_id}", headers=h, json={
        "email": f"moved.{factories.tag()}@t.local", "displayName": "Moved", "rowVersion": target["rowVersion"]})
    assert r.status_code == 403 and r.json()["code"] == "ACCOUNT_HOME_ONLY"
    assert client.patch(f"/api/access/users/{person_id}/disable", headers=h,
                        json={"rowVersion": target["rowVersion"]}).status_code == 403
    assert client.patch(f"/api/access/users/{person_id}/sessions/end", headers=h).status_code == 403

    # The other company still manages the person's roles there.
    role_id = _scalar(db, "SELECT id FROM auth.role WHERE company_id = ? AND code = N'employee'", other)
    roles = client.put(f"/api/access/users/{person_id}/roles", headers=h,
                       json={"roleIds": [str(role_id)], "rowVersion": target["rowVersion"]})
    assert roles.status_code == 200, roles.text

    # The home company's administrator still can.
    home_admin = factories.login_as(db, client, home, role_codes="company_admin")
    assert client.put(f"/api/access/users/{person_id}/password", headers=home_admin["headers"],
                      json={"password": "Reset@2026"}).status_code == 204
