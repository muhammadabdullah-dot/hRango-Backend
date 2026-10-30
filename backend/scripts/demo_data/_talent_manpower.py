"""Manpower planning for the talent part: this fiscal year's plan, a plan per hiring department (new
positions), the e-budgets they make, a few decisions by the department heads and HR, and the open positions
the approved budgets release (recruitment's openings are made from them)."""
from datetime import date

from scripts.demo_data import World
from scripts.demo_data._talent_common import data, iso, lookup_or_create

# Positions: (key, job title, department, branch, grade, min, max)
POSITIONS = [
    ("react", "Senior React Developer", "Software Development", "Lahore Head Office", "G3", 250000, 350000),
    ("ase", "Associate Software Engineer", "Software Development", "Lahore Head Office", "G1", 80000, 120000),
    ("sqa", "SQA Engineer", "Quality Assurance", "Lahore Head Office", "G2", 120000, 180000),
    ("intern", "HR Intern", "Human Resource & Admin", "Lahore Head Office", "G1", 35000, 45000),
    ("sales", "Sales Executive", "Sales & Marketing", "Islamabad Office", "G2", 90000, 140000),
    ("designer", "UI/UX Designer", "UI/UX Design", "Lahore Head Office", "G2", 130000, 190000),
    ("network", "Network Engineer", "IT & Network Support", "Lahore Head Office", "G2", 110000, 160000),
]

# Plans: (title, department, branch or None, description, [(position key, headcount, start month offset)])
PLANS = [
    ("Software Development: product team growth", "Software Development", None,
     "Two senior React developers for the client portal rebuild and an associate engineer for support work.",
     [("react", 2, 2), ("ase", 1, 6)]),
    ("Quality Assurance: automation capacity", "Quality Assurance", None,
     "One SQA engineer to take over regression automation.", [("sqa", 1, 3)]),
    ("HR & Admin: internship programme", "Human Resource & Admin", None,
     "Two six-month HR interns for recruitment coordination and records.", [("intern", 2, 4)]),
    ("Sales & Marketing: Islamabad expansion", "Sales & Marketing", "Islamabad Office",
     "Two sales executives for the federal government and enterprise accounts.", [("sales", 2, 3)]),
    ("UI/UX Design: second designer", "UI/UX Design", None,
     "A second product designer once the client portal design system starts.", [("designer", 1, 6)]),
    ("IT & Network Support: network engineer", "IT & Network Support", None,
     "A network engineer for the new Islamabad office floor.", [("network", 1, 4)]),
]

# Decisions on the plan budgets: job title -> (who decides, approve / reject, remarks). Others stay pending.
DECISIONS = {
    "Senior React Developer": ("Haroon Rashid", "approve", "Approved: needed before the portal kick-off."),
    "SQA Engineer": ("Rabia Anwar", "approve", "Approved for the automation roadmap."),
    "HR Intern": ("Shelley Kannes", "approve", "Approved for six months."),
    "Sales Executive": ("Asad Mirza", "approve", "Approved; Islamabad office seats are ready."),
    "Network Engineer": ("Shelley Kannes", "reject",
                         "Not this year: the IT team covers the new floor with a vendor contract."),
}


def fiscal_year(today: date) -> tuple[str, date, date]:
    y = today.year if today.month >= 7 else today.year - 1
    return f"FY {y}-{(y + 1) % 100:02d}", date(y, 7, 1), date(y + 1, 6, 30)


def add_months(d: date, n: int) -> date:
    m = d.month - 1 + n
    return date(d.year + m // 12, m % 12 + 1, 1)


def seed(w: World) -> dict:
    """Returns {"open_positions": {job title: OpenPositionOut}, "job_titles": {name: JobTitleOut}}."""
    hr = w.admin
    name, fy_start, fy_end = fiscal_year(w.today)
    prev_name, prev_start, prev_end = fiscal_year(date(fy_start.year - 1, 7, 1))
    lookup_or_create(hr, "/manpower/budget-durations", "/manpower/budget-durations", prev_name,
                     {"name": prev_name, "startDate": iso(prev_start), "endDate": iso(prev_end), "isCurrent": False})
    duration = lookup_or_create(hr, "/manpower/budget-durations", "/manpower/budget-durations", name,
                                {"name": name, "startDate": iso(fy_start), "endDate": iso(fy_end), "isCurrent": True})

    group = lookup_or_create(hr, "/organisation/employee-groups", "/organisation/employee-groups", "Staff")
    grades = {g["name"]: g for g in hr.all("/organisation/grades")}
    titles = {}
    positions = {}
    for key, title, dept, branch, grade, lo, hi in POSITIONS:
        titles[title] = lookup_or_create(hr, "/organisation/job-titles", "/organisation/job-titles", title)
        positions[key] = data(hr, "POST", "/manpower/positions", {
            "jobTitleId": int(titles[title]["id"]), "branchId": int(w.branches[branch]["id"]),
            "employeeGroupId": int(group["id"]), "departmentId": int(w.departments[dept]["id"]),
            "gradeId": int(grades[grade]["id"]) if grade in grades else None,
            "minSalary": lo, "maxSalary": hi, "status": "active"})

    plans = []
    for title, dept, branch, description, lines in PLANS:
        body_lines = []
        for key, headcount, offset in lines:
            start = max(add_months(fy_start, offset), fy_start)
            body_lines.append({"kind": "new_position", "positionId": int(positions[key]["id"]),
                               "headcount": headcount, "startDate": iso(start), "endDate": iso(fy_end)})
        plans.append(data(hr, "POST", "/manpower/plans", {
            "title": title, "budgetDurationId": int(duration["id"]),
            "departmentId": int(w.departments[dept]["id"]),
            "branchId": int(w.branches[branch]["id"]) if branch else None,
            "description": description, "lines": body_lines}))

    # A budget added by hand (not from a plan), waiting for approval.
    data(hr, "POST", "/manpower/budgets", {
        "title": "Contract QA testers for the banking client", "budgetDurationId": int(duration["id"]),
        "departmentId": int(w.departments["Quality Assurance"]["id"]), "amount": 720000, "totalPositions": 2,
        "startDate": iso(max(add_months(fy_start, 5), fy_start)), "endDate": iso(add_months(fy_start, 11))})

    decided = 0
    for plan in plans:
        for budget in plan["budgets"]:
            decision = DECISIONS.get(budget.get("jobTitleName") or budget["title"])
            if not decision:
                continue
            who, verb, remarks = decision
            data(w.as_(who), "POST", f"/manpower/budgets/{budget['id']}/{verb}",
                 {"remarks": remarks, "rowVersion": budget["rowVersion"]})
            decided += 1

    open_positions = {o["jobTitleName"] or o["title"]: o for o in hr.all("/manpower/open-positions")}
    budgets = hr("GET", "/manpower/budgets?page=1&pageSize=1")["meta"]["total"]
    print(f"   manpower: {name}, {len(positions)} positions, {len(plans)} plans, {budgets} budgets "
          f"({decided} decided), {len(open_positions)} open positions")
    return {"open_positions": open_positions, "job_titles": titles}
