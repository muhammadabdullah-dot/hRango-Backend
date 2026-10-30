"""Demo activity for Top Edge Technologies: shifts and attendance, leaves and requests, payroll, projects,
recruitment and the rest, so every screen has something to show. Runs after scripts.demo (the people)
and, like it, through the API as the people who would do each thing.

  $env:HRANGO_ADMIN_PASSWORD = "..."; $env:HRANGO_DEMO_PASSWORD = "..."
  .venv\\Scripts\\python.exe -m scripts.demo_data --admin-email shelley.kannes@topedge.tech
  .venv\\Scripts\\python.exe -m scripts.demo_data --admin-email ... --only time,leave_requests

Each part is a module here with `seed(w: World) -> None`; PARTS is the order they run in (later parts may
read what earlier ones made). Dates are relative to today, so the data looks current whenever it is made.
"""
import os
import sys
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

os.environ.setdefault("WEBHOOK_WORKER", "false")

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from scripts.demo import DOMAIN, PEOPLE, Api  # noqa: E402

# Run order. Each name is a module in this package.
PARTS = ("time", "leave_requests", "payroll_assets", "work", "talent")


@dataclass
class World:
    """What every part needs: the API as any person, and the organisation by name."""
    client: TestClient
    admin_email: str
    admin_password: str
    demo_password: str
    admin: Api = None
    today: date = field(default_factory=date.today)
    employees: dict[str, dict[str, Any]] = field(default_factory=dict)      # "First Last" -> EmployeeOut
    departments: dict[str, dict[str, Any]] = field(default_factory=dict)    # name -> DepartmentOut
    branches: dict[str, dict[str, Any]] = field(default_factory=dict)       # name -> BranchOut
    locations: dict[str, dict[str, Any]] = field(default_factory=dict)      # name -> LocationOut
    people: list[dict[str, Any]] = field(default_factory=list)              # scripts.demo.PEOPLE
    _sessions: dict[str, Api] = field(default_factory=dict)

    def email(self, name: str) -> str:
        """The sign-in of "First Last"."""
        person = next(p for p in PEOPLE if f"{p['first']} {p['last']}" == name)
        return self.admin_email if person.get("admin") else f"{person['first']}.{person['last']}@{DOMAIN}".lower()

    def as_(self, name: str) -> Api:
        """The API signed in as "First Last" (the administrator for Shelley Kannes)."""
        email = self.email(name)
        if email not in self._sessions:
            password = self.admin_password if email == self.admin_email else self.demo_password
            r = self.client.post("/api/auth/login", json={"email": email, "password": password})
            if r.status_code != 200:
                sys.exit(f"sign-in as {name} failed: {r.text}")
            self._sessions[email] = Api(self.client, r.json()["data"]["token"])
        return self._sessions[email]

    def emp_id(self, name: str) -> int:
        return int(self.employees[name]["id"])

    def in_department(self, department: str) -> list[str]:
        return [n for n, e in self.employees.items() if e.get("departmentName") == department]

    def days_ago(self, n: int) -> date:
        return self.today - timedelta(days=n)

    def workdays(self, start: date, end: date) -> list[date]:
        """Monday to Friday between start and end, inclusive."""
        out, d = [], start
        while d <= end:
            if d.weekday() < 5:
                out.append(d)
            d += timedelta(days=1)
        return out


def load(admin_email: str) -> World:
    admin_password, demo_password = os.environ.get("HRANGO_ADMIN_PASSWORD"), os.environ.get("HRANGO_DEMO_PASSWORD")
    if not admin_password or not demo_password:
        sys.exit("set HRANGO_ADMIN_PASSWORD and HRANGO_DEMO_PASSWORD")
    w = World(TestClient(app), admin_email, admin_password, demo_password, people=PEOPLE)
    w.admin = w.as_("Shelley Kannes")
    w.employees = {e["name"]: e for e in w.admin.all("/employees")}
    if not w.employees:
        sys.exit("no employees: run scripts.demo first")
    w.departments = {d["name"]: d for d in w.admin.all("/organisation/departments")}
    w.branches = {b["name"]: b for b in w.admin.all("/organisation/branches")}
    w.locations = {loc["name"]: loc for loc in w.admin.all("/organisation/locations")}
    return w
