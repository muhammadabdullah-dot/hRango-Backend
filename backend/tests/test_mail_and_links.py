"""Outgoing mail (roadmap 1.4), password reset by e-mail and invitations (1.5)."""
import email
import re
import socket
import socketserver
import threading
from email import policy

import pytest

from app.core import mail
from app.core.config import settings
from tests import factories

TOKEN = re.compile(r"#token=([A-Za-z0-9_\-]+)")


def _query(db, sql, *params):
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
        cols = [d[0] for d in cur.description] if cur.description else []
        return [dict(zip(cols, row)) for row in cur.fetchall()] if cols else []
    finally:
        cur.close()


def _execute(db, sql, *params):
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


class FakeSmtp:
    """Just enough of an SMTP server to receive messages (no TLS, no auth)."""

    def __init__(self):
        self.messages: list[email.message.EmailMessage] = []
        outer = self

        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                self.wfile.write(b"220 fake ESMTP\r\n")
                while line := self.rfile.readline():
                    command = line.decode("ascii", "replace").strip().upper()
                    if command.startswith(("EHLO", "HELO")):
                        self.wfile.write(b"250-fake\r\n250 8BITMIME\r\n")
                    elif command.startswith(("MAIL FROM", "RCPT TO", "RSET", "NOOP")):
                        self.wfile.write(b"250 OK\r\n")
                    elif command == "DATA":
                        self.wfile.write(b"354 go ahead\r\n")
                        data = b""
                        while (chunk := self.rfile.readline()) not in (b".\r\n", b""):
                            data += chunk[1:] if chunk.startswith(b"..") else chunk
                        outer.messages.append(email.message_from_bytes(data, policy=policy.default))
                        self.wfile.write(b"250 queued\r\n")
                    elif command == "QUIT":
                        self.wfile.write(b"221 bye\r\n")
                        return
                    else:
                        self.wfile.write(b"502 not here\r\n")

        self.server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@pytest.fixture()
def smtp(monkeypatch):
    server = FakeSmtp()
    for name, value in {"mail_enabled": True, "mail_backend": "smtp", "smtp_host": "127.0.0.1", "smtp_port": server.port,
                        "smtp_starttls": False, "smtp_ssl": False, "smtp_username": "", "mail_from": "hRango <no-reply@hrango.test>",
                        "app_public_url": "https://app.hrango.test"}.items():
        monkeypatch.setattr(settings, name, value)
    yield server
    server.close()


def _drain(db):
    while mail.deliver_due(db):
        pass


def _last_mail(db, to_address):
    rows = _query(db, "SELECT TOP 1 * FROM core.mail_message WHERE to_address = ? ORDER BY id DESC", to_address)
    return rows[0] if rows else None


# ---------------------------------------------------------------- the sender

def test_queued_mail_is_sent_and_its_body_cleared(db, smtp):
    to = f"someone.{factories.tag()}@example.test"
    queued = mail.queue(db, kind="test", to_address=to, to_name="Some One", subject="Hello",
                        body_html="<p>Hi <b>there</b></p>", body_text="Hi there")
    assert queued["status"] == "queued"
    _drain(db)
    got = [m for m in smtp.messages if to in m["To"]]
    assert len(got) == 1
    assert got[0]["Subject"] == "Hello" and got[0]["From"] == "hRango <no-reply@hrango.test>"
    assert got[0]["Auto-Submitted"] == "auto-generated"
    assert "Hi there" in got[0].get_body(("plain",)).get_content()
    row = _last_mail(db, to)
    assert row["status"] == "sent" and row["sent_at"] and row["body_html"] is None and row["body_text"] is None


def test_a_failed_send_is_retried_later(db, smtp, monkeypatch):
    closed = socket.socket()
    closed.bind(("127.0.0.1", 0))
    port = closed.getsockname()[1]
    closed.close()
    monkeypatch.setattr(settings, "smtp_port", port)
    to = f"retry.{factories.tag()}@example.test"
    mail.queue(db, kind="test", to_address=to, subject="Later", body_html="<p>x</p>")
    _drain(db)
    row = _last_mail(db, to)
    assert row["status"] == "queued" and row["attempts"] == 1 and row["error"] == "The mail server could not be reached."
    assert row["body_html"] == "<p>x</p>"  # kept for the retry


def test_after_six_attempts_it_is_given_up(db, smtp):
    to = f"giveup.{factories.tag()}@example.test"
    mail.queue(db, kind="test", to_address=to, subject="Never", body_html="<p>x</p>")
    message_id = _last_mail(db, to)["id"]
    _execute(db, "UPDATE core.mail_message SET attempts = 6 WHERE id = ?", message_id)
    db.call("core.usp_mail_result", id=message_id, ok=False, error="The mail server answered 550.")
    row = _last_mail(db, to)
    assert row["status"] == "failed" and row["body_html"] is None


def test_mail_off_records_disabled_and_sends_nothing(db, monkeypatch):
    monkeypatch.setattr(settings, "mail_enabled", False)
    to = f"off.{factories.tag()}@example.test"
    assert mail.queue(db, kind="test", to_address=to, subject="Off", body_html="<p>x</p>")["status"] == "disabled"
    assert mail.deliver_due(db) == 0
    row = _last_mail(db, to)
    assert row["status"] == "disabled" and row["body_html"] is None


def test_the_file_backend_writes_eml_files(db, monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "mail_enabled", True)
    monkeypatch.setattr(settings, "mail_backend", "file")
    monkeypatch.setattr(settings, "mail_file_dir", str(tmp_path))
    monkeypatch.setattr(settings, "mail_from", "hRango <no-reply@hrango.test>")
    to = f"file.{factories.tag()}@example.test"
    mail.queue(db, kind="test", to_address=to, subject="On disk", body_html="<p>x</p>")
    _drain(db)
    files = list(tmp_path.glob("*.eml"))
    assert len(files) == 1
    assert email.message_from_bytes(files[0].read_bytes(), policy=policy.default)["To"] == to


def test_mail_settings_are_checked_at_start():
    from app.core.config import Settings

    base = {"jwt_secret": "x" * 40, "file_link_secret": "y" * 40, "app_env": "production",
            "app_public_url": "https://app.example.com"}
    problems = Settings(_env_file=None, **base, mail_enabled=True, mail_from="", smtp_host="").startup_problems()
    assert any("MAIL_FROM" in p for p in problems) and any("SMTP_HOST" in p for p in problems)
    problems = Settings(_env_file=None, **base, mail_enabled=True, mail_from="a@b.c", smtp_host="smtp.example.com",
                        smtp_starttls=False, smtp_ssl=False).startup_problems()
    assert any("SMTP_STARTTLS" in p for p in problems)
    assert any("APP_PUBLIC_URL" in p for p in Settings(_env_file=None, **{**base, "app_public_url": "http://x"}).startup_problems())


# ---------------------------------------------------------------- forgot password

def test_forgot_password_without_mail_says_so(client, db, monkeypatch):
    monkeypatch.setattr(settings, "mail_enabled", False)
    r = client.post("/api/auth/password/forgot", json={"email": "anyone@example.test"})
    assert r.status_code == 503 and r.json()["code"] == "MAIL_UNAVAILABLE"


def test_reset_password_by_e_mail(client, db, company, smtp):
    user_id, address = factories.user(db, company, role_codes="employee")
    signed_in = client.post("/api/auth/login", json={"email": address, "password": factories.PASSWORD}).json()["data"]
    old_session = {"Authorization": f"Bearer {signed_in['token']}"}

    asked = client.post("/api/auth/password/forgot", json={"email": address.upper()})
    assert asked.status_code == 202 and "If an account uses that address" in asked.json()["data"]["message"]
    queued = _last_mail(db, address)
    assert queued["kind"] == "password_reset" and queued["subject"] == "Reset your hRango password"
    token = TOKEN.search(queued["body_html"]).group(1)
    assert "https://app.hrango.test/reset-password#token=" in queued["body_html"]
    # Only its hash is stored.
    assert not _query(db, "SELECT 1 AS x FROM auth.user_token WHERE token_hash = ?", token)

    _drain(db)
    sent = [m for m in smtp.messages if address in m["To"]][-1]
    assert token in sent.get_body(("plain",)).get_content()

    looked = client.post("/api/auth/links/inspect", json={"token": token})
    assert looked.status_code == 200 and looked.json()["data"]["purpose"] == "password_reset"
    assert looked.json()["data"]["email"] == address

    weak = client.post("/api/auth/password/reset", json={"token": token, "password": "onlyletters"})
    assert weak.status_code == 422 and "password" in weak.json()["fieldErrors"]
    done = client.post("/api/auth/password/reset", json={"token": token, "password": "Brand@New2026"})
    assert done.status_code == 200 and done.json()["data"]["email"] == address
    assert client.get("/api/auth/me", headers=old_session).status_code == 401  # signed out everywhere
    assert client.post("/api/auth/login", json={"email": address, "password": factories.PASSWORD}).status_code == 401
    assert client.post("/api/auth/login", json={"email": address, "password": "Brand@New2026"}).status_code == 200

    again = client.post("/api/auth/password/reset", json={"token": token, "password": "Other@New2026"})
    assert again.status_code == 410 and again.json()["code"] == "LINK_USED"


def test_unknown_addresses_get_the_same_answer_and_no_mail(client, db, smtp):
    address = f"nobody.{factories.tag()}@example.test"
    r = client.post("/api/auth/password/forgot", json={"email": address})
    assert r.status_code == 202
    assert _last_mail(db, address) is None


def test_a_newer_link_replaces_the_older_and_links_expire(client, db, company, smtp):
    _, address = factories.user(db, company, role_codes="employee")
    client.post("/api/auth/password/forgot", json={"email": address})
    first = TOKEN.search(_last_mail(db, address)["body_html"]).group(1)
    client.post("/api/auth/password/forgot", json={"email": address})
    second = TOKEN.search(_last_mail(db, address)["body_html"]).group(1)
    assert client.post("/api/auth/links/inspect", json={"token": first}).json()["code"] == "LINK_USED"
    assert client.post("/api/auth/links/inspect", json={"token": second}).status_code == 200

    _execute(db, "UPDATE t SET expires_at = DATEADD(MINUTE, -1, SYSUTCDATETIME()) FROM auth.user_token t "
                 "JOIN auth.user_account u ON u.id = t.user_account_id WHERE u.email = ? AND t.used_at IS NULL", address)
    expired = client.post("/api/auth/password/reset", json={"token": second, "password": "Brand@New2026"})
    assert expired.status_code == 410 and expired.json()["code"] == "LINK_EXPIRED"
    bogus = client.post("/api/auth/links/inspect", json={"token": "x" * 43})
    assert bogus.status_code == 404 and bogus.json()["code"] == "LINK_NOT_FOUND"


def test_switched_off_accounts_get_no_link(client, db, company, smtp):
    user_id, address = factories.user(db, company, role_codes="employee")
    _execute(db, "UPDATE auth.user_account SET is_active = 0 WHERE id = ?", user_id)
    assert client.post("/api/auth/password/forgot", json={"email": address}).status_code == 202
    assert _last_mail(db, address) is None


# ---------------------------------------------------------------- invitations

def test_an_administrator_invites_instead_of_typing_a_password(client, db, smtp):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    address = f"new.{factories.tag()}@example.test"
    both = client.post("/api/access/users", headers=admin["headers"], json={
        "email": address, "displayName": "New Person", "password": "Typed@2026", "sendInvite": True})
    assert both.status_code == 422
    created = client.post("/api/access/users", headers=admin["headers"], json={
        "email": address, "displayName": "New Person", "sendInvite": True})
    assert created.status_code == 201, created.text
    # Nobody can sign in to it until the invitation is accepted.
    assert client.post("/api/auth/login", json={"email": address, "password": "!invited"}).status_code == 401

    invite = _last_mail(db, address)
    assert invite["kind"] == "invite" and "/accept-invite#token=" in invite["body_html"]
    token = TOKEN.search(invite["body_html"]).group(1)
    looked = client.post("/api/auth/links/inspect", json={"token": token}).json()["data"]
    assert looked["purpose"] == "invite" and looked["email"] == address

    # An invitation link does not reset a password, and the other way round.
    assert client.post("/api/auth/password/reset", json={"token": token, "password": "Mine@2026x"}).status_code == 404
    accepted = client.post("/api/auth/invite/accept", json={"token": token, "password": "Mine@2026x"})
    assert accepted.status_code == 200 and accepted.json()["data"]["email"] == address
    assert client.post("/api/auth/login", json={"email": address, "password": "Mine@2026x"}).status_code == 200

    # Sent again later (a lost e-mail): a fresh link.
    user_id = created.json()["data"]["id"]
    resent = client.post(f"/api/access/users/{user_id}/invite", headers=admin["headers"])
    assert resent.status_code == 202 and resent.json()["data"]["sentTo"] == address


def test_invitations_follow_the_account_rules(client, db, smtp):
    home, other = factories.company(db), factories.company(db)
    person_id, _ = factories.user(db, home, role_codes="employee")
    _execute(db, "INSERT auth.user_company (user_account_id, company_id) VALUES (?, ?)", person_id, other)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    r = client.post(f"/api/access/users/{person_id}/invite", headers=other_admin["headers"])
    assert r.status_code == 403 and r.json()["code"] == "ACCOUNT_HOME_ONLY"


def test_invitations_need_mail(client, db, monkeypatch):
    monkeypatch.setattr(settings, "mail_enabled", False)
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    r = client.post("/api/access/users", headers=admin["headers"], json={
        "email": f"x.{factories.tag()}@example.test", "displayName": "X", "sendInvite": True})
    assert r.status_code == 422 and "sendInvite" in r.json()["fieldErrors"]
