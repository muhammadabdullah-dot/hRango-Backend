"""Test-only helpers for the recruitment tests: organisation rows and a Manpower open position written with
plain SQL (those screens belong to other modules), single permission grants, and API helpers for this
module's own records. Names carry a random suffix so runs never collide."""
from datetime import date

from app.core.db import Db
from tests import factories
from tests.factories import _scalar, tag

API = "/api/recruitment"


def _named(db: Db, table: str, company_id: int, prefix: str) -> int:
    return _scalar(db, f"SET NOCOUNT ON; INSERT {table} (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)",
                   company_id, f"{prefix}{tag()}")


def job_title(db: Db, company_id: int) -> int:
    return _named(db, "org.job_title", company_id, "Job ")


def designation(db: Db, company_id: int) -> int:
    return _named(db, "org.designation", company_id, "Designation ")


def employment_type(db: Db, company_id: int) -> int:
    return _named(db, "org.employment_type", company_id, "Permanent ")


def city(db: Db) -> int:
    return _scalar(db, "SELECT TOP 1 id FROM org.city ORDER BY id")


def open_position(db: Db, company_id: int, seats: int, job_title_id: int | None = None,
                  department_id: int | None = None, branch_id: int | None = None) -> int:
    """An approved budget's open position, as Manpower releases it."""
    duration = _scalar(db, "SET NOCOUNT ON; INSERT mp.budget_duration (company_id, name, start_date, end_date) "
                           "OUTPUT INSERTED.id VALUES (?, ?, ?, ?)",
                       company_id, f"FY {tag()}", date(2026, 1, 1), date(2026, 12, 31))
    budget = _scalar(db, "SET NOCOUNT ON; INSERT mp.e_budget (company_id, budget_duration_id, job_title_id, department_id, "
                         "title, amount, total_positions, start_date, end_date, status) OUTPUT INSERTED.id "
                         "VALUES (?, ?, ?, ?, ?, 1000000, ?, ?, ?, N'approved')",
                     company_id, duration, job_title_id, department_id, f"Budget {tag()}", seats, date(2026, 1, 1),
                     date(2026, 12, 31))
    return _scalar(db, "SET NOCOUNT ON; INSERT mp.open_position (company_id, e_budget_id, job_title_id, department_id, "
                       "branch_id, title, approved_positions, total_positions, status) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, N'active')",
                   company_id, budget, job_title_id, department_id, branch_id, f"Seat {tag()}", seats, seats)


def grant(db: Db, company_id: int, user_id: int, code: str, scope: str = "own") -> None:
    """One extra permission for one user (auth.user_permission_override), as the role screen would add."""
    cur = db.conn.cursor()
    try:
        cur.execute("INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope) "
                    "SELECT ?, ?, id, N'grant', ? FROM auth.permission WHERE code = ?", company_id, user_id, scope, code)
    finally:
        cur.close()


def scalar(db: Db, sql: str, *params):
    return _scalar(db, sql, *params)


# ---------------------------------------------------------------- API helpers

def opening(client, headers: dict, publish: bool = True, **fields) -> dict:
    body = {"title": f"Engineer {tag()}", "vacancies": 2, **fields}
    r = client.post(f"{API}/openings", json=body, headers=headers)
    assert r.status_code == 201, r.text
    data = r.json()["data"]
    if publish:
        r = client.post(f"{API}/openings/{data['id']}/publish", json={"rowVersion": data["rowVersion"]},
                        headers=headers)
        assert r.status_code == 200, r.text
        data = r.json()["data"]
    return data


def applicant_body(**fields) -> dict:
    t = tag()
    return {"firstName": "Ayesha", "lastName": f"Khan {t}", "email": f"ayesha.{t}@mail.test", "phone": "0300-1234567",
            "source": "job_board", **fields}


def apply(client, headers: dict, opening_id: str, **applicant) -> dict:
    r = client.post(f"{API}/applications", json={"jobOpeningId": opening_id, "applicant": applicant_body(**applicant)},
                    headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def upload_cv(client, headers: dict, name: str = "cv.pdf") -> dict:
    return factories.upload(client, headers, name=name, module="recruitment")
