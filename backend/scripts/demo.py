"""Demo data: Top Edge Technologies with its departments, people and a sign-in for each of them.

Runs through the API itself (in-process), signed in as the company's administrator, so every record
passes the same checks as the screens. Development and demo databases only (*_dev or *_demo).

  $env:HRANGO_ADMIN_PASSWORD = "..."     the administrator made by --bootstrap
  $env:HRANGO_DEMO_PASSWORD  = "..."     the password every demo account gets
  .venv\\Scripts\\python.exe -m scripts.demo --admin-email shelley.kannes@topedge.tech --accounts-out ..\\demo-accounts.md

Run it once on a freshly bootstrapped database (scripts.seed --reset, then --bootstrap). The
administrator is linked to the HR Manager's employee record, so their own pages work too.
"""
import argparse
import os
import sys
from datetime import date
from pathlib import Path

os.environ.setdefault("WEBHOOK_WORKER", "false")

from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.main import app  # noqa: E402
from scripts.seed import db_name  # noqa: E402

DOMAIN = "topedge.tech"

LOCATIONS = [("Lahore", "LHR", 31.5204, 74.3587), ("Islamabad", "ISB", 33.6844, 73.0479)]
BRANCHES = [("Lahore Head Office", "LHR", "Lahore", "Gulberg III, Lahore"),
            ("Islamabad Office", "ISB", "Islamabad", "Blue Area, Islamabad")]
DESIGNATIONS = ["Chief Executive Officer", "Chief Technology Officer", "Head of Department", "Manager", "Team Lead",
                "Senior Executive", "Executive", "Senior Software Engineer", "Software Engineer",
                "Associate Software Engineer", "Officer", "Assistant"]
GRADES = [("G1", 1), ("G2", 2), ("G3", 3), ("G4", 4), ("G5", 5), ("G6", 6)]
JOB_LEVELS = [("Executive Leadership", 1), ("Senior Management", 2), ("Middle Management", 3), ("Professional", 4),
              ("Associate", 5), ("Support Staff", 6)]
DEPARTMENTS = ["Executive Office", "Human Resource & Admin", "Finance & Accounts", "Software Development",
               "Quality Assurance", "UI/UX Design", "Sales & Marketing", "IT & Network Support"]

# (first, last, gender, department, designation, job title, grade, level, branch, roles, manager key, extras)
# The manager key is the "first last" of the line manager; "head" marks the department head.
P = dict
PEOPLE = [
    P(first="Imran", last="Siddiqui", gender="male", dept="Executive Office", desig="Chief Executive Officer",
      title="Chief Executive Officer", grade="G6", level="Executive Leadership", roles=["executive"], head=True,
      joined="2016-01-04", born="1978-03-12", marital="married"),
    P(first="Sana", last="Malik", gender="female", dept="Executive Office", desig="Executive",
      title="Executive Assistant", grade="G2", level="Professional", manager="Imran Siddiqui",
      joined="2021-06-01", born="1994-08-21", marital="single"),
    # Human Resource & Admin: the existing administrator becomes its HR Manager (linked, not a new account).
    P(first="Shelley", last="Kannes", gender="female", dept="Human Resource & Admin", desig="Manager",
      title="HR Manager", grade="G5", level="Senior Management", roles=["hr_manager"], head=True, admin=True,
      manager="Imran Siddiqui", joined="2018-02-12", born="1988-11-02", marital="married"),
    P(first="Ayesha", last="Khan", gender="female", dept="Human Resource & Admin", desig="Senior Executive",
      title="HR Officer", grade="G3", level="Professional", roles=["hr_officer"], manager="Shelley Kannes",
      joined="2020-09-14", born="1993-05-17", marital="married"),
    P(first="Hamza", last="Riaz", gender="male", dept="Human Resource & Admin", desig="Executive",
      title="Talent Acquisition Specialist", grade="G2", level="Professional", roles=["recruiter"],
      manager="Shelley Kannes", joined="2022-03-07", born="1996-01-29", marital="single"),
    P(first="Bilal", last="Ahmed", gender="male", dept="Human Resource & Admin", desig="Officer",
      title="Admin Officer", grade="G2", level="Professional", manager="Shelley Kannes",
      joined="2019-07-01", born="1990-10-10", marital="married"),
    P(first="Kashif", last="Mehmood", gender="male", dept="Human Resource & Admin", desig="Assistant",
      title="Office Assistant", grade="G1", level="Support Staff", manager="Bilal Ahmed",
      joined="2021-01-11", born="1987-04-03", marital="married"),
    P(first="Nadia", last="Hussain", gender="female", dept="Finance & Accounts", desig="Manager",
      title="Finance Manager", grade="G5", level="Senior Management", roles=["finance", "payroll_manager"],
      head=True, manager="Imran Siddiqui", joined="2017-05-15", born="1985-12-19", marital="married"),
    P(first="Usman", last="Ghani", gender="male", dept="Finance & Accounts", desig="Senior Executive",
      title="Payroll Accountant", grade="G3", level="Professional", roles=["payroll_manager"],
      manager="Nadia Hussain", joined="2019-11-04", born="1991-06-08", marital="married"),
    P(first="Farah", last="Naz", gender="female", dept="Finance & Accounts", desig="Executive",
      title="Accounts Officer", grade="G2", level="Professional", manager="Nadia Hussain",
      joined="2023-02-20", born="1997-09-14", marital="single"),
    P(first="Haroon", last="Rashid", gender="male", dept="Software Development", desig="Chief Technology Officer",
      title="Chief Technology Officer", grade="G6", level="Executive Leadership", head=True,
      manager="Imran Siddiqui", joined="2016-03-01", born="1982-07-25", marital="married"),
    P(first="Faisal", last="Javed", gender="male", dept="Software Development", desig="Team Lead",
      title="Team Lead (Web)", grade="G4", level="Middle Management", roles=["line_manager"],
      manager="Haroon Rashid", joined="2018-08-13", born="1989-02-11", marital="married"),
    P(first="Areeba", last="Hameed", gender="female", dept="Software Development", desig="Senior Software Engineer",
      title="Senior Frontend Engineer", grade="G3", level="Professional", manager="Faisal Javed",
      joined="2020-01-06", born="1995-03-30", marital="single"),
    P(first="Zain", last="Abbas", gender="male", dept="Software Development", desig="Software Engineer",
      title="Backend Engineer", grade="G2", level="Professional", manager="Faisal Javed",
      joined="2022-07-18", born="1998-12-05", marital="single"),
    P(first="Hira", last="Shahid", gender="female", dept="Software Development", desig="Software Engineer",
      title="Mobile App Engineer", grade="G2", level="Professional", manager="Faisal Javed",
      joined="2023-04-03", born="1999-05-22", marital="single"),
    P(first="Saad", last="Qureshi", gender="male", dept="Software Development", desig="Associate Software Engineer",
      title="Associate Software Engineer", grade="G1", level="Associate", manager="Faisal Javed",
      joined="2026-08-04", born="2002-02-14", marital="single", status="probation", probation_end="2026-11-03"),
    P(first="Rabia", last="Anwar", gender="female", dept="Quality Assurance", desig="Team Lead",
      title="QA Lead", grade="G4", level="Middle Management", head=True, manager="Haroon Rashid",
      joined="2018-10-01", born="1990-08-09", marital="married"),
    P(first="Danish", last="Iqbal", gender="male", dept="Quality Assurance", desig="Software Engineer",
      title="SQA Engineer", grade="G2", level="Professional", manager="Rabia Anwar",
      joined="2021-09-13", born="1996-11-17", marital="single"),
    P(first="Mehwish", last="Akram", gender="female", dept="Quality Assurance", desig="Associate Software Engineer",
      title="Associate SQA Engineer", grade="G1", level="Associate", manager="Rabia Anwar",
      joined="2026-09-01", born="2001-07-01", marital="single", status="probation", probation_end="2026-11-30"),
    P(first="Omer", last="Farooq", gender="male", dept="UI/UX Design", desig="Team Lead",
      title="Design Lead", grade="G4", level="Middle Management", head=True, manager="Haroon Rashid",
      joined="2019-03-18", born="1991-04-27", marital="married"),
    P(first="Maham", last="Zafar", gender="female", dept="UI/UX Design", desig="Executive",
      title="UI/UX Designer", grade="G2", level="Professional", manager="Omer Farooq",
      joined="2022-11-07", born="1998-10-03", marital="single"),
    P(first="Asad", last="Mirza", gender="male", dept="Sales & Marketing", desig="Manager",
      title="Sales Manager", grade="G5", level="Senior Management", head=True, branch="Islamabad Office",
      manager="Imran Siddiqui", joined="2017-09-04", born="1984-01-16", marital="married"),
    P(first="Komal", last="Shah", gender="female", dept="Sales & Marketing", desig="Executive",
      title="Business Development Executive", grade="G2", level="Professional", branch="Islamabad Office",
      manager="Asad Mirza", joined="2023-01-09", born="1997-06-12", marital="single"),
    P(first="Taha", last="Saleem", gender="male", dept="Sales & Marketing", desig="Executive",
      title="Digital Marketing Executive", grade="G2", level="Professional", branch="Islamabad Office",
      manager="Asad Mirza", joined="2024-05-20", born="1999-09-08", marital="single"),
    P(first="Waqas", last="Butt", gender="male", dept="IT & Network Support", desig="Manager",
      title="IT Manager", grade="G4", level="Middle Management", head=True, manager="Haroon Rashid",
      joined="2018-04-02", born="1987-03-21", marital="married"),
    P(first="Junaid", last="Akhtar", gender="male", dept="IT & Network Support", desig="Executive",
      title="Network Administrator", grade="G2", level="Professional", manager="Waqas Butt",
      joined="2021-12-06", born="1995-12-28", marital="married"),
]


class Api:
    def __init__(self, client: TestClient, token: str):
        self.client, self.headers = client, {"Authorization": f"Bearer {token}"}

    def __call__(self, method: str, path: str, body: dict | None = None, ok: tuple[int, ...] = (200, 201)) -> dict:
        r = self.client.request(method, f"/api{path}", json=body, headers=self.headers)
        if r.status_code not in ok:
            sys.exit(f"{method} {path} -> {r.status_code}: {r.text}")
        return r.json() if r.content else {}

    def all(self, path: str) -> list[dict]:
        sep = "&" if "?" in path else "?"
        return self("GET", f"{path}{sep}page=1&pageSize=100")["data"]


def by_name(rows: list[dict], key: str = "name") -> dict[str, dict]:
    return {r[key]: r for r in rows}


def cnic(n: int) -> str:
    return f"35202-{4000000 + n * 7919:07d}-{n % 9 + 1}"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Create the Top Edge Technologies demo data.")
    p.add_argument("--admin-email", required=True)
    p.add_argument("--accounts-out", required=True, help="where to write the list of demo sign-ins (markdown)")
    a = p.parse_args()
    name = db_name(settings.db_url)
    if not name.lower().endswith(("_dev", "_demo")):
        sys.exit(f"refused: {name} is not a *_dev or *_demo database")
    admin_password, demo_password = os.environ.get("HRANGO_ADMIN_PASSWORD"), os.environ.get("HRANGO_DEMO_PASSWORD")
    if not admin_password or not demo_password:
        sys.exit("set HRANGO_ADMIN_PASSWORD and HRANGO_DEMO_PASSWORD")

    client = TestClient(app)
    r = client.post("/api/auth/login", json={"email": a.admin_email, "password": admin_password})
    if r.status_code != 200:
        sys.exit(f"administrator sign-in failed: {r.text}")
    api = Api(client, r.json()["data"]["token"])
    if api("GET", "/employees?page=1&pageSize=1")["meta"]["total"]:
        sys.exit(f"refused: {name} already has employees (run it on a freshly bootstrapped database)")

    # Organisation
    locations = {}
    for loc, prefix, lat, lng in LOCATIONS:
        locations[loc] = api("POST", "/organisation/locations", {"name": loc, "employeePrefix": prefix,
                                                                 "latitude": lat, "longitude": lng})["data"]
    branches = {}
    for branch, prefix, loc, address in BRANCHES:
        branches[branch] = api("POST", "/organisation/branches", {
            "name": branch, "employeePrefix": prefix, "locationId": int(locations[loc]["id"]),
            "description": address})["data"]
    designations = {d: api("POST", "/organisation/designations", {"name": d})["data"] for d in DESIGNATIONS}
    grades = {g: api("POST", "/organisation/grades", {"name": g, "sortOrder": s})["data"] for g, s in GRADES}
    levels = {lv: api("POST", "/organisation/job-levels", {"name": lv, "sortOrder": s})["data"] for lv, s in JOB_LEVELS}
    departments = {d: api("POST", "/organisation/departments", {"name": d})["data"] for d in DEPARTMENTS}
    titles = {}
    for person in PEOPLE:
        if person["title"] not in titles:
            titles[person["title"]] = api("POST", "/organisation/job-titles", {"name": person["title"]})["data"]
    permanent = by_name(api.all("/organisation/employment-types"))["Permanent"]
    roles = by_name(api.all("/access/roles"), "code")
    users = by_name(api.all("/access/users"), "email")

    # People, managers first (the list is ordered so every manager comes before their team).
    employees: dict[str, dict] = {}
    accounts = []
    for n, person in enumerate(PEOPLE, start=1):
        full = f"{person['first']} {person['last']}"
        email = a.admin_email if person.get("admin") else f"{person['first']}.{person['last']}@{DOMAIN}".lower()
        branch = branches[person.get("branch", "Lahore Head Office")]
        body = {
            "firstName": person["first"], "lastName": person["last"], "gender": person["gender"],
            "maritalStatus": person["marital"], "nationality": "Pakistani", "dateOfBirth": person["born"],
            "cnic": cnic(n), "email": email, "phone1": f"+92 300 {1000000 + n * 37311 % 8999999:07d}",
            "homeAddress": f"House {n * 7}, Street {n % 12 + 1}, {branch['locationName']}",
            "branchId": int(branch["id"]), "locationId": int(branch["locationId"]),
            "departmentId": int(departments[person["dept"]]["id"]),
            "designationId": int(designations[person["desig"]]["id"]),
            "jobTitleId": int(titles[person["title"]]["id"]), "gradeId": int(grades[person["grade"]]["id"]),
            "jobLevelId": int(levels[person["level"]]["id"]), "employmentTypeId": int(permanent["id"]),
            "lineManagerId": int(employees[person["manager"]]["id"]) if person.get("manager") else None,
            "finalAuthorityId": int(employees["Imran Siddiqui"]["id"]) if person.get("manager") else None,
            "status": person.get("status", "active"), "joiningDate": person["joined"],
            "probationEndDate": person.get("probation_end"),
        }
        employees[full] = api("POST", "/employees", body)["data"]
        role_codes = [*person.get("roles", []), "employee"]
        if person.get("head") and "department_head" not in role_codes and person["dept"] != "Executive Office":
            role_codes.insert(0, "department_head")
        if person.get("admin"):
            # The administrator already exists: link it to this record and keep its roles.
            u = users[email]
            detail = api("GET", f"/access/users/{u['id']}")["data"]
            api("PUT", f"/access/users/{u['id']}", {
                "email": detail["email"], "displayName": detail.get("displayName"),
                "employeeId": int(employees[full]["id"]), "isActive": True,
                "isSystemAdmin": detail.get("isSystemAdmin", False), "rowVersion": detail["rowVersion"]})
            role_names = ", ".join(r["name"] for r in detail.get("roles", [])) or "Company Administrator"
            accounts.append((full, person["dept"], person["title"], role_names + " (system administrator)", email, None))
            continue
        api("POST", "/access/users", {"email": email, "employeeId": int(employees[full]["id"]),
                                      "password": demo_password, "roleIds": [int(roles[c]["id"]) for c in role_codes]})
        accounts.append((full, person["dept"], person["title"], ", ".join(roles[c]["name"] for c in role_codes),
                         email, demo_password))

    # Department heads, now that the people exist.
    for person in PEOPLE:
        if person.get("head"):
            dept = departments[person["dept"]]
            current = api("GET", f"/organisation/departments/{dept['id']}")["data"]
            api("PUT", f"/organisation/departments/{dept['id']}", {
                "name": current["name"], "headId": int(employees[f"{person['first']} {person['last']}"]["id"]),
                "rowVersion": current["rowVersion"]})

    write_accounts(Path(a.accounts_out), accounts, demo_password, admin_password)
    print(f"{len(LOCATIONS)} locations, {len(BRANCHES)} branches, {len(DEPARTMENTS)} departments, "
          f"{len(employees)} employees, {len(accounts)} sign-ins; accounts written to {a.accounts_out}")


def write_accounts(path: Path, accounts: list, demo_password: str, admin_password: str) -> None:
    lines = [
        "# hRango demo sign-ins: Top Edge Technologies",
        "",
        f"Made {date.today():%d %b %Y} by `backend/scripts/demo.py` on the development database. Demo data only:",
        "these people and passwords are not real.",
        "",
        f"- Password for every account below: `{demo_password}`",
        f"- Administrator (system admin, linked to Shelley Kannes): `{admin_password}`",
        "",
        "| Name | Department | Job title | Roles | Email |",
        "|---|---|---|---|---|",
    ]
    lines += [f"| {n} | {d} | {t} | {r} | `{e}` |" for n, d, t, r, e, _ in accounts]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
