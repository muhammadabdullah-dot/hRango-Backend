"""Failed sign-ins pause further attempts (BE-07); unknown emails cost the same as wrong passwords."""
import time

import pytest

from app.core import security
from app.core.config import settings
from tests import factories


@pytest.fixture(autouse=True)
def throttle_on(monkeypatch):
    monkeypatch.setattr(settings, "login_throttle", True)


def _execute(db, sql, *params):
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def _login(client, email, password):
    return client.post("/api/auth/login", json={"email": email, "password": password})


def _clear(db, email):
    _execute(db, "DELETE FROM auth.login_attempt WHERE email = ?", email)


def _user(db, company):
    user_id, email = factories.user(db, company, role_codes="employee")
    _clear(db, email)
    return user_id, email


def test_five_wrong_passwords_pause_that_account_from_that_address(client, db, company):
    _, email = _user(db, company)
    for _ in range(5):
        assert _login(client, email, "Wrong@2026").status_code == 401
    paused = _login(client, email, factories.PASSWORD)
    assert paused.status_code == 429
    assert paused.json()["code"] == "TOO_MANY_ATTEMPTS"
    assert 0 < int(paused.headers["retry-after"]) <= 15 * 60
    assert "Try again in 15 minutes" in paused.json()["message"]


def test_a_successful_sign_in_clears_the_count(client, db, company):
    _, email = _user(db, company)
    for _ in range(4):
        assert _login(client, email, "Wrong@2026").status_code == 401
    assert _login(client, email, factories.PASSWORD).status_code == 200
    for _ in range(4):
        assert _login(client, email, "Wrong@2026").status_code == 401
    assert _login(client, email, factories.PASSWORD).status_code == 200


def test_the_pause_ends_fifteen_minutes_after_the_last_failure(client, db, company):
    _, email = _user(db, company)
    for _ in range(5):
        _login(client, email, "Wrong@2026")
    assert _login(client, email, factories.PASSWORD).status_code == 429
    _execute(db, "UPDATE auth.login_attempt SET attempted_at = DATEADD(MINUTE, -16, attempted_at) WHERE email = ?", email)
    assert _login(client, email, factories.PASSWORD).status_code == 200


def test_unknown_emails_are_counted_and_answered_like_wrong_passwords(client, db):
    email = f"nobody.{factories.tag()}@nowhere.test"
    _clear(db, email)
    first = _login(client, email, "Wrong@2026")
    assert first.status_code == 401 and first.json()["code"] == "INVALID_CREDENTIALS"
    for _ in range(4):
        _login(client, email, "Wrong@2026")
    assert _login(client, email, "Wrong@2026").status_code == 429


def test_unknown_email_costs_the_same_password_work(monkeypatch):
    calls = []
    real = security.verify_password
    monkeypatch.setattr(security, "verify_password", lambda p, s: calls.append(s) or real(p, s))
    assert security.password_matches("Anything@1", None) is False
    assert calls and calls[0].startswith("scrypt$")


def test_the_check_takes_about_as_long_either_way():
    stored = security.hash_password("Right@2026")
    started = time.perf_counter()
    security.password_matches("Wrong@2026", stored)
    real = time.perf_counter() - started
    started = time.perf_counter()
    security.password_matches("Wrong@2026", None)
    dummy = time.perf_counter() - started
    assert dummy > real * 0.5


def test_one_address_guessing_many_accounts_is_paused(client, db):
    ip = "203.0.113.77"
    _execute(db, "DELETE FROM auth.login_attempt WHERE ip_address = ?", ip)
    _execute(db, "INSERT auth.login_attempt (realm, email, ip_address, succeeded, attempted_at) "
                 "SELECT TOP 50 N'customer', CONCAT(N'spray', ROW_NUMBER() OVER (ORDER BY (SELECT 1)), N'@x.test'), ?, 0, "
                 "SYSUTCDATETIME() FROM sys.all_objects", ip)
    row = db.call_one("auth.usp_login_throttle_check", realm="customer", email="someone.else@x.test", ip_address=ip)
    assert row["retry_after_seconds"] > 0
    other = db.call_one("auth.usp_login_throttle_check", realm="customer", email="someone.else@x.test",
                        ip_address="198.51.100.7")
    assert other["retry_after_seconds"] == 0


def test_staff_sign_in_has_the_same_limits(client, db):
    email = f"staff.{factories.tag()}@nowhere.test"
    _clear(db, email)
    for _ in range(5):
        r = client.post("/api/platform/auth/login", json={"email": email, "password": "Wrong@2026wrong"})
        assert r.status_code == 401
    r = client.post("/api/platform/auth/login", json={"email": email, "password": "Wrong@2026wrong"})
    assert r.status_code == 429
