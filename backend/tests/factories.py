"""Test-only helpers that make the records other tests need. They write with plain SQL on purpose:
the screens that create these records belong to their own modules, and tests of one module should
not depend on another module's endpoints. Names carry a random suffix so runs never collide.
"""
import json
import uuid

from app.core.db import Db
from app.core.default_roles import expanded as default_roles
from app.core.security import hash_password

PASSWORD = "Test@12345"


def tag() -> str:
    return uuid.uuid4().hex[:8]


def _scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def company(db: Db, name: str | None = None) -> int:
    company_id = db.call_one("org.usp_company_provision", name=name or f"Test Company {tag()}")["company_id"]
    db.call("auth.usp_role_defaults_apply", company_id=company_id, roles=json.dumps(default_roles()))
    return company_id


def location(db: Db, company_id: int, name: str | None = None) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT org.location (company_id, name, employee_prefix) "
                       "OUTPUT INSERTED.id VALUES (?, ?, ?)", company_id, name or f"Location {tag()}", "TST")


def branch(db: Db, company_id: int, location_id: int | None = None, name: str | None = None) -> int:
    location_id = location_id or location(db, company_id)
    return _scalar(db, "SET NOCOUNT ON; INSERT org.branch (company_id, location_id, name) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?)", company_id, location_id, name or f"Branch {tag()}")


def department(db: Db, company_id: int, name: str | None = None, parent_id: int | None = None) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT org.department (company_id, name, parent_id) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?)", company_id, name or f"Department {tag()}", parent_id)


def employee(db: Db, company_id: int, branch_id: int | None = None, department_id: int | None = None,
             line_manager_id: int | None = None, first_name: str = "Test", last_name: str | None = None) -> int:
    branch_id = branch_id or branch(db, company_id)
    return _scalar(db, "SET NOCOUNT ON; INSERT hr.employee (company_id, code, first_name, last_name, status, "
                       "branch_id, department_id, line_manager_id) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?, ?, N'active', ?, ?, ?)",
                   company_id, f"T-{tag()}", first_name, last_name or tag(), branch_id, department_id,
                   line_manager_id)


def user(db: Db, company_id: int, employee_id: int | None = None, role_codes: str = "",
         is_system_admin: bool = False) -> tuple[int, str]:
    email = f"user.{tag()}@test.local"
    user_id = db.call_one("auth.usp_user_provision", company_id=company_id, email=email,
                          password_hash=hash_password(PASSWORD), employee_id=employee_id,
                          display_name=None if employee_id else "Test User", is_system_admin=is_system_admin,
                          role_codes=role_codes)["user_id"]
    return user_id, email


def login_as(db: Db, client, company_id: int, role_codes: str = "", employee_id: int | None = None) -> dict:
    """Make a user with these roles, sign in, and return {"user_id", "email", "token", "headers"}."""
    user_id, email = user(db, company_id, employee_id=employee_id, role_codes=role_codes)
    r = client.post("/api/auth/login", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    token = r.json()["data"]["token"]
    return {"user_id": user_id, "email": email, "token": token, "headers": {"Authorization": f"Bearer {token}"}}


PDF_BYTES = b"%PDF-1.4\n1 0 obj << >> endobj\ntrailer << >>\n%%EOF\n"
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


def upload(client, headers: dict, name: str = "document.pdf", content: bytes = PDF_BYTES, module: str = "core") -> dict:
    """Uploads a file as that user and returns its JSON (id, name, url, ...)."""
    r = client.post("/api/files", files={"file": (name, content)}, data={"module": module}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]
