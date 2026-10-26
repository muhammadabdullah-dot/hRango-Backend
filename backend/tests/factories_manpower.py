"""Test-only helpers for the manpower and benefits tests: organisation reference rows, salaries and stored
files written with plain SQL (those screens belong to other modules), and API helpers for this module's
own records. Names carry a random suffix so runs never collide."""
from datetime import date

from app.core.db import Db
from tests.factories import _scalar, tag


def _named(db: Db, table: str, company_id: int, name: str | None = None, prefix: str = "") -> int:
    return _scalar(db, f"SET NOCOUNT ON; INSERT {table} (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)",
                   company_id, name or f"{prefix}{tag()}")


def job_title(db: Db, company_id: int, name: str | None = None) -> int:
    return _named(db, "org.job_title", company_id, name, "Job ")


def employee_group(db: Db, company_id: int, name: str | None = None) -> int:
    return _named(db, "org.employee_group", company_id, name, "Group ")


def division(db: Db, company_id: int, name: str | None = None) -> int:
    return _named(db, "org.division", company_id, name, "Division ")


def grade(db: Db, company_id: int, name: str | None = None) -> int:
    return _named(db, "org.grade", company_id, name, "Grade ")


def cost_center(db: Db, company_id: int, name: str | None = None) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT org.cost_center (company_id, code, name) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?)", company_id, f"CC{tag()[:6]}", name or f"Cost {tag()}")


def salary(db: Db, employee_id: int, amount: float, effective: date = date(2020, 1, 1)) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT hr.employee_salary (employee_id, effective_date, amount) "
                       "OUTPUT INSERTED.id VALUES (?, ?, ?)", employee_id, effective, amount)


def employee_details(db: Db, employee_id: int, job_title_id: int | None = None, date_of_birth: date | None = None,
                     marital_status: str | None = None) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute("UPDATE hr.employee SET job_title_id = ?, date_of_birth = ?, marital_status = ? WHERE id = ?",
                    job_title_id, date_of_birth, marital_status, employee_id)
    finally:
        cur.close()


# ---------------------------------------------------------------- API helpers for manpower records

def duration(client, headers: dict, start: str = "2031-01-01", end: str = "2031-12-31", current: bool = False,
             name: str | None = None) -> dict:
    r = client.post("/api/manpower/budget-durations",
                    json={"name": name or f"FY {tag()}", "startDate": start, "endDate": end, "isCurrent": current},
                    headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def position(client, headers: dict, job_title_id: int, branch_id: int, group_id: int, department_id: int | None = None,
             min_salary: float = 100000, max_salary: float = 150000, **extra) -> dict:
    body = {"jobTitleId": str(job_title_id), "branchId": str(branch_id), "employeeGroupId": str(group_id),
            "departmentId": str(department_id) if department_id else None, "minSalary": min_salary,
            "maxSalary": max_salary, **extra}
    r = client.post("/api/manpower/positions", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]
