"""Performance for the talent part: a rating scale and an appraisal form, KPIs per department, goals for
everyone with check-ins, last half-year's cycle reviewed, finalised (with increments proposed, one applied and
one rejected) and closed, and this half-year's cycle launched with reviews under way. Managers set their
team's goals and rate them; HR (Shelley Kannes) runs the cycles and finalises."""
import random
from datetime import date, timedelta

from scripts.demo import PEOPLE
from scripts.demo_data import World
from scripts.demo_data._talent_common import (as_first, attempt, current, data, eid, first_of_next_month, iso, note,
                                                salary_of)

HR = "Shelley Kannes"
HR2 = "Ayesha Khan"       # finalises the HR Manager's own appraisal

SCALE = [(1, "Unsatisfactory", "Falls well short of what the role needs."),
         (2, "Needs Improvement", "Meets some expectations; clear gaps to close."),
         (3, "Meets Expectations", "Does what the role needs, reliably."),
         (4, "Exceeds Expectations", "Regularly goes beyond what the role needs."),
         (5, "Outstanding", "Exceptional results and a model for others.")]

CRITERIA = [("Job knowledge and quality of work", "Accuracy, depth and quality of the work delivered.", 25),
            ("Productivity and delivery", "Delivers agreed work on time.", 20),
            ("Communication and teamwork", "Works well with colleagues and clients.", 15),
            ("Ownership and initiative", "Takes responsibility and improves how things are done.", 10)]
GOALS_WEIGHT = 30

# Department -> KPIs: (name, key result area, measure, target, unit)
KPIS = {
    "Executive Office": [("Company revenue growth", "Growth", "percentage", 20, "%"),
                         ("Client retention", "Clients", "percentage", 90, "%")],
    "Human Resource & Admin": [("Time to hire", "Recruitment", "number", 30, "days"),
                               ("Appraisals completed on time", "Performance", "percentage", 100, "%")],
    "Finance & Accounts": [("Payroll processed by the 1st", "Payroll", "yes_no", None, None),
                           ("Month-end close", "Reporting", "number", 5, "working days")],
    "Software Development": [("Sprint commitment delivered", "Delivery", "percentage", 90, "%"),
                             ("Code review turnaround", "Quality", "number", 24, "hours")],
    "Quality Assurance": [("Regression suite automated", "Automation", "percentage", 70, "%"),
                          ("Defect leakage to production", "Quality", "percentage", 5, "%")],
    "UI/UX Design": [("Design hand-offs on time", "Delivery", "percentage", 95, "%"),
                     ("Usability score (SUS)", "Experience", "number", 80, "points")],
    "Sales & Marketing": [("Quarterly sales target", "Revenue", "amount", 15000000, "PKR"),
                          ("Qualified leads per month", "Pipeline", "number", 40, "leads")],
    "IT & Network Support": [("Tickets resolved within SLA", "Support", "percentage", 95, "%"),
                             ("System uptime", "Infrastructure", "percentage", 99.5, "%")],
}

# Department -> (H1 goal, H2 quarter goal, H2 half-year goal) titles, and a personal development goal.
GOALS = {
    "Executive Office": ("Close two enterprise accounts", "Open the Islamabad office floor", "Agree the FY budget with the board",
                         "Complete an executive leadership course"),
    "Human Resource & Admin": ("Roll out the new leave policy", "Hire the Q3 positions", "Run the H2 appraisal cycle on time",
                               "Earn the SHRM-CP certificate"),
    "Finance & Accounts": ("Close the FY accounts with the auditors", "Move vendor payments to the bank portal",
                           "Monthly MIS within 5 working days", "Finish the advanced Excel and Power BI course"),
    "Software Development": ("Ship the client portal v2", "Migrate the API to .NET 8", "Release the mobile app 3.0",
                             "Finish the Advanced React and TypeScript course"),
    "Quality Assurance": ("Automate the smoke suite", "Set up API contract tests", "Automate 70% of regression",
                          "Learn Playwright end to end"),
    "UI/UX Design": ("Publish the design system v1", "Usability study of the client portal",
                     "Redesign the onboarding flow", "Complete a motion design course"),
    "Sales & Marketing": ("Meet the H1 sales target", "Launch the LinkedIn campaign", "Meet the H2 sales target",
                          "Complete a negotiation skills workshop"),
    "IT & Network Support": ("Replace the core switches", "Set up the Islamabad office network",
                             "Move backups to Azure", "Earn the CCNA certificate"),
}

STRONG = {"Areeba Hameed", "Faisal Javed", "Rabia Anwar", "Usman Ghani", "Omer Farooq", "Komal Shah", "Ayesha Khan",
          "Nadia Hussain", "Haroon Rashid", "Asad Mirza"}
WEAK = {"Taha Saleem", "Kashif Mehmood"}
NEW = {"Saad Qureshi", "Mehwish Akram"}          # joined after the last cycle
CEO = "Imran Siddiqui"

# Last cycle's outcomes beyond "no change": name -> (outcome, increment percent or None, final comments)
OUTCOMES = {
    "Areeba Hameed": ("increment", 15, "Led the portal rebuild; a 15% increment from next month."),
    "Danish Iqbal": ("increment", 10, "Strong half; increment proposed."),
    "Komal Shah": ("increment", 8, "Beat the H1 target by 12%."),
    "Junaid Akhtar": ("increment", 7, "Core switch replacement done ahead of plan."),
    "Zain Abbas": ("promotion", None, "Ready for Senior Software Engineer at the next review board."),
    "Taha Saleem": ("improvement_plan", None, "A 90-day improvement plan on campaign delivery, reviewed monthly."),
}
APPLY_FIRST = ["Areeba Hameed", "Komal Shah", "Junaid Akhtar"]   # the one applied: the first with a salary
REJECT = "Danish Iqbal"


def half_years(today: date) -> tuple[tuple[str, date, date], tuple[str, date, date]]:
    """(last half-year, this half-year) as (cycle name, start, end)."""
    if today.month >= 7:
        last, this = (1, today.year), (2, today.year)
    else:
        last, this = (2, today.year - 1), (1, today.year)

    def span(h: int, y: int) -> tuple[str, date, date]:
        return (f"H{h} {y} Appraisal", date(y, 1, 1), date(y, 6, 30)) if h == 1 else \
            (f"H{h} {y} Appraisal", date(y, 7, 1), date(y, 12, 31))
    return span(*last), span(*this)


def managers() -> dict[str, str | None]:
    return {f"{p['first']} {p['last']}": p.get("manager") for p in PEOPLE}


def level(name: str) -> int:
    return 2 if name in STRONG else (0 if name in WEAK else 1)


def reviewers(w: World, name: str, mgr: str | None) -> list[str]:
    """Who rates `name`: their line manager when their permissions reach them, else HR."""
    return [m for m in (mgr, HR, HR2) if m and m != name and m != CEO and current(w, m)]


def ratings(rng: random.Random, criteria: list[dict], lvl: int, bump: int = 0) -> list[dict]:
    lo, hi = [(2, 3), (3, 4), (4, 5)][lvl]
    notes = {2: "Some gaps to work on.", 3: "Solid and dependable.", 4: "Consistently strong.", 5: "Exceptional this period."}
    out = []
    for c in criteria:
        r = min(5, rng.randint(lo, hi) + bump)
        out.append({"criterionId": int(c["id"]), "rating": r, "comment": notes[r]})
    return out


class Perf:
    def __init__(self, w: World):
        self.w, self.mgr = w, managers()
        self.goal_count = self.checkins = 0

    def goal(self, owner: str, setter_first: bool, body: dict) -> dict:
        """A goal for `owner`, set by their manager (or HR), or by themselves."""
        body = {**body, "employeeId": eid(self.w, owner)}
        names = [owner] if not setter_first else reviewers(self.w, owner, self.mgr[owner]) + [owner]
        _, g = as_first(self.w, names, "POST", "/performance/goals", body)
        self.goal_count += 1
        return g

    def check_in(self, owner: str, goal: dict, progress: float, comments: str) -> dict:
        g = data(self.w.as_(owner), "POST", f"/performance/goals/{goal['id']}/check-ins",
                 {"progress": progress, "comments": comments, "rowVersion": goal["rowVersion"]})
        self.checkins += 1
        return g


def _settings(w: World) -> tuple[dict, dict[str, list[dict]]]:
    hr = w.admin
    scale = data(hr, "POST", "/performance/rating-scales", {
        "name": "Five-point performance scale", "isDefault": True,
        "levels": [{"score": s, "label": label, "description": d} for s, label, d in SCALE]})
    form = data(hr, "POST", "/performance/forms", {
        "name": "Half-yearly staff appraisal", "ratingScaleId": int(scale["id"]), "goalsWeight": GOALS_WEIGHT,
        "description": "Four competencies plus goal achievement; self review, then the line manager.",
        "hasSelfReview": True,
        "criteria": [{"name": n, "description": d, "weight": wt} for n, d, wt in CRITERIA]})
    kpis = {}
    for dept, rows in KPIS.items():
        kpis[dept] = [data(hr, "POST", "/performance/kpis", {
            "name": n, "keyResultArea": kra, "measureType": m, "targetValue": t, "unit": u,
            "defaultWeight": 50, "departmentId": int(w.departments[dept]["id"]),
            "description": f"{n} for {dept}."}) for n, kra, m, t, u in rows]
    return form, kpis


def _cycle(w: World, name: str, start: date, end: date, form: dict, self_due: date, mgr_due: date) -> dict:
    return data(w.admin, "POST", "/performance/cycles", {
        "name": name, "appraisalFormId": int(form["id"]), "startDate": iso(start), "endDate": iso(end),
        "selfReviewDueDate": iso(self_due), "managerReviewDueDate": iso(mgr_due)})


def _start(w: World, cycle: dict, people: list[str]) -> list[dict]:
    hr = w.admin
    data(hr, "POST", f"/performance/cycles/{cycle['id']}/participants",
         {"employeeIds": [eid(w, p) for p in people]})
    cycle = data(hr, "GET", f"/performance/cycles/{cycle['id']}")
    data(hr, "POST", f"/performance/cycles/{cycle['id']}/launch", {"rowVersion": cycle["rowVersion"]})
    return hr.all(f"/performance/appraisals?cycleId={cycle['id']}")


def _self_review(w: World, a: dict, criteria: list[dict], rng: random.Random, submit: bool = True) -> dict:
    name = a["employeeName"]
    return data(w.as_(name), "PUT", f"/performance/reviews/{a['id']}/self", {
        "ratings": ratings(rng, criteria, level(name), bump=1 if level(name) < 2 else 0),
        "comments": "I delivered my main goals this period and want to take on more ownership next.",
        "submit": submit, "rowVersion": a["rowVersion"]})


def _manager_review(w: World, p: Perf, a: dict, criteria: list[dict], rng: random.Random,
                    submit: bool = True) -> dict:
    name = a["employeeName"]
    lvl = level(name)
    comment = ["Needs closer support; agreed actions for next period.", "Reliable contributor; keep growing scope.",
               "Excellent period; ready for more responsibility."][lvl]
    needs = ["Time management coaching; weekly check-ins.", "Advanced technical training.",
             "Leadership for New Managers programme."][lvl]
    _, out = as_first(w, reviewers(w, name, p.mgr[name]), "PUT", f"/performance/reviews/{a['id']}/manager", {
        "ratings": ratings(rng, criteria, lvl), "comments": comment, "developmentNeeds": needs,
        "submit": submit, "rowVersion": a["rowVersion"]})
    return out


def seed(w: World) -> None:
    rng = random.Random(20261029)
    p = Perf(w)
    form, kpis = _settings(w)
    criteria = form["criteria"]
    (last_name, last_start, last_end), (this_name, this_start, this_end) = half_years(w.today)
    everyone = sorted(w.employees)
    staff = [n for n in everyone if n in p.mgr and current(w, n)]   # the demo people still here

    # ---------------------------------------------------------------- last half-year
    last_people = [n for n in staff if n != CEO and n not in NEW]
    last_cycle = _cycle(w, last_name, last_start, last_end, form, last_end + timedelta(days=15),
                        last_end + timedelta(days=31))
    for n in last_people:
        dept = w.employees[n]["departmentName"]
        title1 = GOALS[dept][0]
        kpi = kpis[dept][0]
        lvl = level(n)
        g1 = p.goal(n, True, {"appraisalCycleId": int(last_cycle["id"]), "kpiId": int(kpi["id"]), "title": title1,
                              "startDate": iso(last_start), "dueDate": iso(last_end - timedelta(days=30)), "weight": 60})
        g1 = p.check_in(n, g1, 50, "Halfway there; on plan.")
        p.check_in(n, g1, 100 if lvl > 0 else 80, "Done." if lvl > 0 else "Most of it done; rest moves to H2.")
        g2 = p.goal(n, True, {"appraisalCycleId": int(last_cycle["id"]), "title": f"{kpis[dept][1]['name']}: H1 target",
                              "kpiId": int(kpis[dept][1]["id"]), "startDate": iso(last_start),
                              "dueDate": iso(last_end), "weight": 40})
        p.check_in(n, g2, [60, 85, 100][lvl], "Quarter-end update.")
    apps = _start(w, last_cycle, last_people)
    for a in apps:
        a = _self_review(w, a, criteria, rng)
        a = _manager_review(w, p, a, criteria, rng)
        name = a["employeeName"]
        outcome, pct, comments = OUTCOMES.get(name, ("no_change", None, "Keep up the good work."))
        body = {"finalComments": comments, "outcome": outcome, "rowVersion": a["rowVersion"]}
        if outcome == "increment":
            salary = salary_of(w, name)
            body["increment"] = ({"changeType": "percent", "changeValue": pct} if salary else
                                 {"changeType": "flat", "changeValue": 15000}) | {
                "effectiveDate": iso(first_of_next_month(w.today))}
        as_first(w, [HR2] if name == HR else [HR, HR2], "POST", f"/performance/appraisals/{a['id']}/finalise", body)
    last_cycle = data(w.admin, "GET", f"/performance/cycles/{last_cycle['id']}")
    data(w.admin, "POST", f"/performance/cycles/{last_cycle['id']}/close", {"rowVersion": last_cycle["rowVersion"]})

    # Increments: one applied (to the payroll salary), one rejected, the rest left for payroll.
    increments = {i["employeeName"]: i for i in w.admin.all("/performance/increments")}
    applied = None
    for name in APPLY_FIRST:
        inc = increments.get(name)
        if inc and inc.get("currentSalary"):
            status, body = attempt(w.admin, "POST", f"/performance/increments/{inc['id']}/apply",
                                   {"remarks": "Applied from the next payroll month.", "rowVersion": inc["rowVersion"]})
            if status < 300:
                applied = name
                break
            note(f"applying {name}'s increment was refused: {status} {body.get('code')} {body.get('message')}")
    if not applied:
        note("no increment applied: none of " + ", ".join(APPLY_FIRST) + " has a salary yet (payroll not seeded)")
    if REJECT in increments:
        inc = increments[REJECT]
        data(w.admin, "POST", f"/performance/increments/{inc['id']}/reject",
             {"remarks": "Department budget is frozen this half; revisit in the next cycle.", "rowVersion": inc["rowVersion"]})

    # ---------------------------------------------------------------- this half-year
    this_people = [n for n in staff if n != CEO]
    this_cycle = _cycle(w, this_name, this_start, this_end, form, w.today + timedelta(days=17),
                        w.today + timedelta(days=32))
    q_end = _quarter_end(w.today)
    if q_end < this_start + timedelta(days=30):        # early in a half-year: a goal due last week instead
        q_end = w.days_ago(7)
    for n in staff:
        dept = w.employees[n]["departmentName"]
        lvl = level(n)
        cyc = {"appraisalCycleId": int(this_cycle["id"])} if n != CEO else {}
        # A quarter goal now past its due date: done by the strong, overdue for the rest.
        g = p.goal(n, n != CEO, {**cyc, "title": GOALS[dept][1], "kpiId": int(kpis[dept][1]["id"]),
                                 "startDate": iso(this_start), "dueDate": iso(q_end), "weight": 30})
        g = p.check_in(n, g, 40, "Started; waiting on inputs from the client.")
        if lvl == 2 or (lvl == 1 and rng.random() < 0.5):
            p.check_in(n, g, 100, "Completed.")
        else:
            p.check_in(n, g, 75 if lvl else 45, "Slipped past the due date; finishing this month.")
        # The half-year goal, under way.
        g = p.goal(n, n != CEO, {**cyc, "title": GOALS[dept][2], "kpiId": int(kpis[dept][0]["id"]),
                                 "startDate": iso(this_start), "dueDate": iso(this_end), "weight": 50})
        if n not in NEW:
            p.check_in(n, g, [35, 55, 70][lvl], "On track for year end." if lvl else "Behind; agreed a recovery plan.")
        # Their own development goal.
        g = p.goal(n, False, {**cyc, "title": GOALS[dept][3], "startDate": iso(this_start),
                              "dueDate": iso(this_end), "weight": 20,
                              "description": "Personal development goal agreed with my manager."})
        if rng.random() < 0.6:
            p.check_in(n, g, rng.choice([20, 30, 50]), "Making steady progress.")

    apps = sorted(_start(w, this_cycle, this_people), key=lambda a: a["employeeName"])
    selfs = mgrs = drafts = 0
    for i, a in enumerate(apps):
        name = a["employeeName"]
        if name in NEW:
            continue
        if i % 2 == 0:
            a = _self_review(w, a, criteria, rng)
            selfs += 1
            # Managers who are quick: Software Development and Finance teams are rated already.
            if p.mgr[name] in ("Faisal Javed", "Nadia Hussain", "Rabia Anwar", "Asad Mirza"):
                _manager_review(w, p, a, criteria, rng)
                mgrs += 1
            elif p.mgr[name] == "Shelley Kannes":
                _manager_review(w, p, a, criteria, rng, submit=False)
                drafts += 1
        elif i % 5 == 1:
            _self_review(w, a, criteria, rng, submit=False)
            drafts += 1

    ov = data(w.admin, "GET", f"/performance/overview?employeeId={eid(w, 'Areeba Hameed')}")
    print(f"   performance: {sum(len(k) for k in kpis.values())} KPIs, {p.goal_count} goals, {p.checkins} check-ins; "
          f"{last_name}: {len(last_people)} finalised, closed, increment applied to {applied or 'nobody'}; "
          f"{this_name}: {len(apps)} launched, {selfs} self reviews, {mgrs} manager reviews, {drafts} drafts; "
          f"overview (Areeba Hameed): {ov['goals']}")


def _quarter_end(today: date) -> date:
    """The end of the last finished quarter (so its goals are due already)."""
    return date(today.year, (today.month - 1) // 3 * 3 + 1, 1) - timedelta(days=1)
