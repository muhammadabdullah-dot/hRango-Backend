"""Self-service sign-up (roadmap 1.1): a trial organisation without staff, finished from an e-mail link."""
import re

import pytest

from app.core.config import settings
from tests import factories
from tests.test_platform import staff

TOKEN = re.compile(r"#token=([A-Za-z0-9_\-]+)")


def _last_mail(db, to_address):
    cur = db.conn.cursor()
    try:
        row = cur.execute("SELECT TOP 1 kind, subject, body_html, company_id FROM core.mail_message WHERE to_address = ? "
                          "ORDER BY id DESC", to_address).fetchone()
        return None if row is None else {"kind": row[0], "subject": row[1], "body_html": row[2], "company_id": row[3]}
    finally:
        cur.close()


@pytest.fixture()
def mail_on(monkeypatch, tmp_path):
    for name, value in {"mail_enabled": True, "mail_backend": "file", "mail_file_dir": str(tmp_path),
                        "mail_from": "hRango <no-reply@hrango.test>", "app_public_url": "https://app.hrango.test"}.items():
        monkeypatch.setattr(settings, name, value)


def _body(**extra):
    t = factories.tag()
    return {"companyName": f"Sunrise Foods {t}", "ownerName": "Ayesha Khan", "ownerEmail": f"ayesha.{t}@sunrise.test",
            "country": "Pakistan", "acceptTerms": True, **extra}


def test_sign_up_makes_a_trial_organisation_finished_from_the_e_mail(client, db, mail_on):
    me = staff(db, client)
    plan = client.post("/api/platform/plans", headers=me["headers"], json={
        "name": f"Starter {factories.tag()}", "priceMonthly": 1500, "priceAnnual": 15000, "employeeLimit": 25}).json()["data"]
    offered = client.get("/api/public/plans").json()["data"]
    assert any(p["id"] == plan["id"] and p["employeeLimit"] == 25 for p in offered)
    assert all("subscriptionCount" not in p for p in offered)

    body = _body(planId=int(plan["id"]))
    r = client.post("/api/public/signup", json=body)
    assert r.status_code == 202, r.text
    assert "Check your e-mail" in r.json()["data"]["message"]

    # Nobody signs in before the link is used.
    assert client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": "!invited"}).status_code == 401
    sent = _last_mail(db, body["ownerEmail"])
    assert sent["kind"] == "signup" and "/accept-invite#token=" in sent["body_html"]
    token = TOKEN.search(sent["body_html"]).group(1)
    assert client.post("/api/auth/invite/accept", json={"token": token, "password": "Sunrise@2026"}).status_code == 200

    login = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": "Sunrise@2026"})
    assert login.status_code == 200, login.text
    who = login.json()["data"]["user"]
    assert who["role"] == "Account Owner" and who["companyName"] == body["companyName"]
    owner = {"Authorization": f"Bearer {login.json()['data']['token']}"}
    usage = client.get("/api/organisation/plan", headers=owner).json()["data"]
    assert usage["planName"] == plan["name"] and usage["subscriptionStatus"] == "trial" and usage["employeeLimit"] == 25

    # Staff see it as a customer of its own.
    found = client.get("/api/platform/organisations", headers=me["headers"], params={"q": body["companyName"]}).json()
    assert any(o["name"] == body["companyName"] for o in found["data"])


def test_an_address_that_already_signs_in_gets_the_same_answer(client, db, company, mail_on):
    _, address = factories.user(db, company, role_codes="employee")
    r = client.post("/api/public/signup", json=_body(ownerEmail=address))
    assert r.status_code == 202
    told = _last_mail(db, address)
    assert told["kind"] == "signup_existing" and told["company_id"] is None
    # The existing account is untouched.
    assert client.post("/api/auth/login", json={"email": address, "password": factories.PASSWORD}).status_code == 200


def test_the_same_company_name_as_another_customer_is_fine(client, db, mail_on):
    first = _body()
    second = _body(companyName=first["companyName"])
    assert client.post("/api/public/signup", json=first).status_code == 202
    assert client.post("/api/public/signup", json=second).status_code == 202
    a, b = _last_mail(db, first["ownerEmail"]), _last_mail(db, second["ownerEmail"])
    assert a["company_id"] != b["company_id"]  # a new company each time, never someone else's


def test_sign_up_needs_terms_mail_and_a_real_plan(client, db, mail_on, monkeypatch):
    no_terms = client.post("/api/public/signup", json=_body(acceptTerms=False))
    assert no_terms.status_code == 422 and "acceptTerms" in no_terms.json()["fieldErrors"]
    bad_plan = client.post("/api/public/signup", json=_body(planId=987654321))
    assert bad_plan.status_code == 422 and "planId" in bad_plan.json()["fieldErrors"]
    monkeypatch.setattr(settings, "mail_enabled", False)
    off = client.post("/api/public/signup", json=_body())
    assert off.status_code == 503 and off.json()["code"] == "SIGNUP_UNAVAILABLE"


def test_sign_up_is_limited_per_address(client, db, mail_on, monkeypatch):
    monkeypatch.setattr(settings, "login_throttle", True)
    body = _body()
    cur = db.conn.cursor()
    try:
        cur.execute("DELETE FROM auth.login_attempt WHERE email = ?", body["ownerEmail"])
    finally:
        cur.close()
    for _ in range(5):
        client.post("/api/public/signup", json=body)
    assert client.post("/api/public/signup", json=body).status_code == 429
