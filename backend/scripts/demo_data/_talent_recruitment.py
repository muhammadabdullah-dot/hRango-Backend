"""Recruitment for the talent part, run by the recruiter (Hamza Riaz): rejection reasons, openings (four
from Manpower's open positions, one closed earlier this year, one draft), 22 applicants spread over the
pipeline, interviews held (with the panel's own evaluations) and coming up this week and next, and offers:
one sent, one accepted and hired, one declined."""
from datetime import timedelta

from scripts.demo_data import World
from scripts.demo_data._talent_common import at, attempt, data, eid, iso, note, workday_before, workdays_after

REASONS = ["Insufficient experience", "Failed technical interview", "Salary expectations too high",
           "Not a culture fit", "Position filled", "Did not respond", "Overqualified for the role"]

# key -> opening. "from": the Manpower open position (job title) it recruits for.
OPENINGS = {
    "react": dict(title="Senior React Developer", from_="Senior React Developer", dept="Software Development",
                  desig="Senior Software Engineer", manager="Faisal Javed", city="Lahore", mode="hybrid",
                  exp=(4, 8), salary=(250000, 350000), posted=95,
                  description="Build the client portal and internal products in React and TypeScript.",
                  requirements="4+ years of React, TypeScript, REST APIs; testing with Jest or Vitest."),
    "sqa": dict(title="SQA Engineer", from_="SQA Engineer", dept="Quality Assurance", desig="Software Engineer",
                manager="Rabia Anwar", city="Lahore", mode="on_site", exp=(2, 5), salary=(120000, 180000), posted=60,
                description="Own regression automation for our web and mobile products.",
                requirements="Selenium or Playwright, API testing, a CI pipeline you have built or kept."),
    "intern": dict(title="HR Intern", from_="HR Intern", dept="Human Resource & Admin", desig="Assistant",
                   manager="Shelley Kannes", city="Lahore", mode="on_site", exp=(0, 1), salary=(35000, 45000),
                   posted=40, etype="Contractual",
                   description="Six-month internship: recruitment coordination, onboarding and HR records.",
                   requirements="BBA / MBA (HR) final year or fresh graduate; good written English."),
    "sales": dict(title="Sales Executive", from_="Sales Executive", dept="Sales & Marketing", desig="Executive",
                  manager="Asad Mirza", city="Islamabad", branch="Islamabad Office", mode="on_site", exp=(2, 4),
                  salary=(90000, 140000), posted=50,
                  description="Win and grow enterprise and public-sector accounts from our Islamabad office.",
                  requirements="2+ years of B2B software sales; own transport preferred."),
    "ase": dict(title="Associate Software Engineer", dept="Software Development",
                desig="Associate Software Engineer", manager="Faisal Javed", city="Lahore", mode="on_site",
                exp=(0, 1), salary=(80000, 110000), posted=125, vacancies=1, closed=True,
                description="Graduate role in the web team (filled in August).",
                requirements="BS Computer Science; JavaScript and one backend language."),
    "devops": dict(title="DevOps Engineer", dept="IT & Network Support", desig="Senior Software Engineer",
                   manager="Waqas Butt", city="Lahore", mode="hybrid", exp=(3, 6), salary=(220000, 300000),
                   posted=None, vacancies=1, draft=True,
                   description="Run our Azure hosting, CI/CD and monitoring.",
                   requirements="Azure, Docker, GitHub Actions, Terraform."),
}

# Applicants: (first, last, gender, opening, applied days ago, source, years, employer, current title,
#              expected salary, outcome). Outcomes are handled in seed().
APPLICANTS = [
    ("Usama", "Tariq", "male", "react", 88, "linkedin", 6, "Systems Limited", "Senior Software Engineer", 320000, "hired"),
    ("Mariam", "Saleem", "female", "react", 80, "referral", 5, "Arbisoft", "Frontend Engineer", 300000, "offer_sent"),
    ("Fatima", "Zahid", "female", "react", 47, "job_board", 4, "10Pearls", "React Developer", 280000, "round2_upcoming"),
    ("Ahmed", "Raza", "male", "react", 33, "career_site", 5, "Netsol Technologies", "Software Engineer", 290000, "interview_upcoming"),
    ("Hassan", "Ali", "male", "react", 21, "linkedin", 4, "Contour Software", "Frontend Developer", 260000, "shortlisted"),
    ("Sara", "Imtiaz", "female", "react", 9, "career_site", 3, "Tkxel", "Software Engineer", 240000, "screening"),
    ("Bilal", "Khurshid", "male", "react", 55, "job_board", 1, "Freelance", "Web Developer", 200000, "rejected_screening:Insufficient experience"),
    ("Noman", "Akbar", "male", "react", 2, "career_site", 7, "Afiniti", "Senior Frontend Engineer", 380000, "applied"),
    ("Ayesha", "Noor", "female", "sqa", 52, "linkedin", 4, "Venture Dive", "SQA Engineer", 170000, "offer_declined"),
    ("Waleed", "Khan", "male", "sqa", 44, "job_board", 2, "i2c", "Junior QA Engineer", 150000, "failed"),
    ("Iqra", "Batool", "female", "sqa", 26, "referral", 3, "Folio3", "QA Automation Engineer", 160000, "interview_upcoming"),
    ("Rizwan", "Ahmed", "male", "sqa", 4, "career_site", 2, "Techlogix", "SQA Engineer", 140000, "applied"),
    ("Zoya", "Farooq", "female", "intern", 30, "career_site", 0, "LUMS (final year)", "Student", 40000, "interview_upcoming"),
    ("Hamid", "Nawaz", "male", "intern", 18, "walk_in", 0, "UCP (graduate)", "Fresh graduate", 40000, "screening"),
    ("Laiba", "Arshad", "female", "intern", 25, "career_site", 0, "Kinnaird College", "Student", 38000, "withdrawn"),
    ("Umer", "Shafiq", "male", "intern", 3, "linkedin", 0, "FAST NU (graduate)", "Fresh graduate", 45000, "applied"),
    ("Kamran", "Yousaf", "male", "sales", 41, "agency", 3, "Jazz Business", "Corporate Sales Executive", 130000, "interviewed"),
    ("Hina", "Pervaiz", "female", "sales", 38, "linkedin", 4, "PTCL", "Key Account Manager", 220000, "rejected_screening:Salary expectations too high"),
    ("Talha", "Javed", "male", "sales", 14, "job_board", 2, "Zong 4G", "Sales Officer", 110000, "screening"),
    ("Saba", "Riaz", "female", "sales", 6, "referral", 2, "TPL Trakker", "Sales Executive", 120000, "applied"),
    ("Adeel", "Hussain", "male", "ase", 118, "career_site", 0, "COMSATS (graduate)", "Fresh graduate", 90000, "closed:Position filled"),
    ("Mahnoor", "Ali", "female", "ase", 104, "job_board", 1, "Ebryx", "Trainee Engineer", 95000, "closed_failed"),
]


class Recruiter:
    """The recruiter's calls, plus panel slots that never clash."""

    def __init__(self, w: World):
        self.w, self.api = w, w.as_("Hamza Riaz")
        self.reasons: dict[str, str] = {}
        self.used: set[tuple[int, str]] = set()
        self.counts = {"interviews": 0, "evaluations": 0, "offers": 0}

    def slot(self, day, panel: list[str], hour: int = 11) -> str:
        """A time on `day` at which nobody on the panel is already booked."""
        while True:
            when = at(day, hour)
            if not any((eid(self.w, p), when) in self.used for p in panel):
                for p in panel:
                    self.used.add((eid(self.w, p), when))
                return when
            hour += 1

    def move(self, app: dict, stage: str, remarks: str | None = None) -> dict:
        return data(self.api, "PATCH", f"/recruitment/applications/{app['id']}/stage",
                    {"stage": stage, "remarks": remarks, "rowVersion": app["rowVersion"]})

    def reload(self, app: dict) -> dict:
        return data(self.api, "GET", f"/recruitment/applications/{app['id']}")

    def reject(self, app: dict, reason: str, remarks: str) -> dict:
        return data(self.api, "POST", f"/recruitment/applications/{app['id']}/reject",
                    {"rejectionReasonId": int(self.reasons[reason]), "remarks": remarks, "rowVersion": app["rowVersion"]})

    def interview(self, app: dict, day, panel: list[str], title: str, mode: str = "in_person",
                  hour: int = 11) -> dict:
        self.counts["interviews"] += 1
        venue = "Meeting room 2, Gulberg office" if mode == "in_person" else ("Microsoft Teams" if mode == "video" else None)
        return data(self.api, "POST", "/recruitment/interviews", {
            "applicationId": int(app["id"]), "title": title, "mode": mode, "scheduledAt": self.slot(day, panel, hour),
            "durationMinutes": 60, "venue": venue, "interviewerIds": [eid(self.w, p) for p in panel]})

    def held(self, app: dict, day, panel: list[str], title: str, verdicts: list[tuple[int, str, str]],
             result: str, remarks: str, mode: str = "in_person") -> dict:
        """An interview that took place: each panel member's own evaluation, then the result."""
        iv = self.interview(app, day, panel, title, mode)
        for person, (rating, rec, comment) in zip(panel, verdicts):
            api = self.api if person == "Hamza Riaz" else self.w.as_(person)
            status, body = attempt(api, "POST", f"/recruitment/interviews/{iv['id']}/evaluations", {
                "rating": rating, "recommendation": rec, "comments": comment,
                "strengths": comment if rating >= 4 else None, "concerns": comment if rating <= 2 else None})
            if status >= 300:   # not allowed to evaluate for themselves: HR records it for them
                note(f"{person} could not record an evaluation ({status} {body.get('code')}); HR entered it")
                data(self.api, "POST", f"/recruitment/interviews/{iv['id']}/evaluations", {
                    "employeeId": eid(self.w, person), "rating": rating, "recommendation": rec, "comments": comment})
            self.counts["evaluations"] += 1
        iv = data(self.api, "GET", f"/recruitment/interviews/{iv['id']}")
        return data(self.api, "POST", f"/recruitment/interviews/{iv['id']}/complete",
                    {"status": "completed", "result": result, "remarks": remarks, "rowVersion": iv["rowVersion"]})

    def offer(self, app: dict, salary: int, joining, expires) -> dict:
        self.counts["offers"] += 1
        offer = data(self.api, "POST", "/recruitment/offers", {
            "applicationId": int(app["id"]), "offeredSalary": salary, "salaryFrequency": "monthly",
            "joiningDate": iso(joining), "probationMonths": 3, "expiresOn": iso(expires),
            "remarks": "Standard benefits: OPD and IPD cover, provident fund after confirmation."})
        return data(self.api, "POST", f"/recruitment/offers/{offer['id']}/send",
                    {"remarks": "Offer letter emailed to the candidate.", "rowVersion": offer["rowVersion"]})

    def respond(self, offer: dict, decision: str, remarks: str) -> dict:
        return data(self.api, "POST", f"/recruitment/offers/{offer['id']}/respond",
                    {"decision": decision, "remarks": remarks, "rowVersion": offer["rowVersion"]})


def _cities(w: World) -> dict[str, int]:
    out = {}
    for state in ("PK-PB", "PK-IS"):
        status, rows = attempt(w.admin, "GET", f"/organisation/geo/cities?state={state}")
        for c in rows if status == 200 else []:
            out[c["name"]] = int(c["id"])
    return out


def _openings(w: World, r: Recruiter, open_positions: dict, job_titles: dict) -> dict[str, dict]:
    designations = {d["name"]: d for d in w.admin.all("/organisation/designations")}
    etypes = {t["name"]: t for t in w.admin.all("/organisation/employment-types")}
    cities = _cities(w)
    openings = {}
    for key, o in OPENINGS.items():
        op = open_positions.get(o.get("from_", ""))
        posted = w.days_ago(o["posted"]) if o.get("posted") else None
        body = {
            "title": o["title"], "openPositionId": int(op["id"]) if op else None,
            "jobTitleId": int(job_titles[o["title"]]["id"]) if o["title"] in job_titles else None,
            "designationId": int(designations[o["desig"]]["id"]) if o["desig"] in designations else None,
            "departmentId": int(w.departments[o["dept"]]["id"]),
            "branchId": int(w.branches[o.get("branch", "Lahore Head Office")]["id"]),
            "employmentTypeId": int(etypes[o.get("etype", "Permanent")]["id"]),
            "hiringManagerId": eid(w, o["manager"]), "cityId": cities.get(o["city"]), "workMode": o["mode"],
            "experienceFromYears": o["exp"][0], "experienceToYears": o["exp"][1],
            "vacancies": o.get("vacancies") if not op else None,
            "postedOn": iso(posted), "applyBy": iso(posted + timedelta(days=60)) if posted else None,
            "salaryFrom": o["salary"][0], "salaryTo": o["salary"][1], "isSalaryVisible": key in ("intern", "sales"),
            "description": o["description"], "requirements": o["requirements"]}
        if not op and o.get("from_"):
            note(f"no open position for {o['from_']}; the opening stands alone")
            body["vacancies"] = 2
        opening = data(r.api, "POST", "/recruitment/openings", body)
        if not o.get("draft"):
            opening = data(r.api, "POST", f"/recruitment/openings/{opening['id']}/publish",
                           {"rowVersion": opening["rowVersion"]})
        openings[key] = opening
    return openings


def seed(w: World, manpower: dict) -> None:
    r = Recruiter(w)
    for n, reason in enumerate(REASONS, start=1):
        r.reasons[reason] = data(r.api, "POST", "/recruitment/settings/rejection-reasons",
                                 {"name": reason, "sortOrder": n})["id"]
    openings = _openings(w, r, manpower["open_positions"], manpower["job_titles"])

    upcoming = workdays_after(w.today, 7)          # the next working days: this week, then next week
    this_week = [d for d in upcoming if d.isocalendar()[1] == w.today.isocalendar()[1]] or upcoming[:1]
    next_week = [d for d in upcoming if d not in this_week]
    hired_name = None
    apps = {}
    for n, (first, last, gender, key, ago, source, years, employer, title, expected, outcome) in enumerate(APPLICANTS):
        applied = w.days_ago(ago)
        app = data(r.api, "POST", "/recruitment/applications", {
            "jobOpeningId": int(openings[key]["id"]), "appliedOn": iso(applied), "source": source,
            "applicant": {
                "firstName": first, "lastName": last, "gender": gender,
                "email": f"{first}.{last}.{n + 7}@example.com".lower(), "phone": f"+92 3{n % 5}1 {4100000 + n * 7703}",
                "currentEmployer": employer, "currentJobTitle": title, "experienceYears": years,
                "expectedSalary": expected, "noticePeriodDays": 0 if years == 0 else 30,
                "highestEducation": "BS Computer Science" if key in ("react", "sqa", "ase") else
                ("BBA (Human Resource Management)" if key == "intern" else "BBA (Marketing)"),
                "source": source,
                "referredByEmployeeId": eid(w, "Areeba Hameed") if source == "referral" and key == "react" else
                (eid(w, "Danish Iqbal") if source == "referral" and key == "sqa" else
                 (eid(w, "Komal Shah") if source == "referral" else None)),
                "notes": "Profile from the careers page; CV on file with the recruiter."}})
        apps[f"{first} {last}"] = app
        opening = OPENINGS[key]
        hm = opening["manager"]
        tech = ["Faisal Javed", "Haroon Rashid"] if key in ("react", "ase") else \
            (["Rabia Anwar", "Hamza Riaz"] if key == "sqa" else ([hm, "Hamza Riaz"]))
        past = workday_before(applied + timedelta(days=min(14, max(ago - 3, 1))))

        if outcome == "applied":
            continue
        app = r.move(app, "screening", "CV meets the basic requirements.")
        if outcome == "screening":
            continue
        if outcome.startswith("rejected_screening"):
            reason = outcome.split(":", 1)[1]
            r.reject(app, reason, f"Screened out: {reason.lower()}.")
            continue
        if outcome == "withdrawn":
            app = r.move(app, "shortlisted", "Good academic record.")
            data(r.api, "POST", f"/recruitment/applications/{app['id']}/withdraw",
                 {"remarks": "Candidate withdrew: going abroad for higher studies.", "rowVersion": app["rowVersion"]})
            continue
        app = r.move(app, "shortlisted", f"Shortlisted for an interview with {hm}.")
        if outcome == "shortlisted":
            continue
        if outcome.startswith("closed"):
            if outcome == "closed_failed":
                r.held(app, past, tech, "Technical interview", [(2, "no_hire", "Weak on data structures."),
                                                               (2, "no_hire", "Not ready for client work yet.")],
                       "failed", "Below the bar for the technical round.")
                app = r.reload(app)
                r.reject(app, "Failed technical interview", "Did not clear the technical round.")
            else:
                r.reject(r.reload(app), "Position filled", "The vacancy was filled by another candidate.")
            continue
        if outcome == "interview_upcoming":
            day = this_week[n % len(this_week)] if n % 2 == 0 else next_week[n % len(next_week)]
            r.interview(app, day, tech, "First interview", "video" if key == "intern" else "in_person",
                        hour=10 + n % 5)
            continue
        if outcome == "failed":
            r.held(app, past, tech, "Technical interview", [(2, "no_hire", "Struggled with test design questions."),
                                                           (3, "no_hire", "Good attitude, little automation.")],
                   "failed", "Did not meet the automation bar.")
            r.reject(r.reload(app), "Failed technical interview", "Not enough automation experience.")
            continue
        if outcome == "interviewed":
            r.held(app, past, tech, "First interview", [(4, "hire", "Strong network in telecom accounts."),
                                                       (4, "hire", "Clear communicator; realistic expectations.")],
                   "passed", "Move to the final round with the CEO.")
            continue
        if outcome == "round2_upcoming":
            r.held(app, past, tech, "Technical interview", [(4, "hire", "Solid React and testing."),
                                                           (4, "hire", "Good system design for her level.")],
                   "passed", "Invite for the final round.")
            r.interview(r.reload(app), next_week[0], ["Haroon Rashid", "Shelley Kannes"], "Final interview",
                        hour=15)
            continue
        # Offers: interviewed and passed first.
        r.held(app, past, tech, "Technical interview", [(5, "strong_hire", "Excellent React and architecture."),
                                                       (4, "hire", "Would raise the team's bar.")]
               if key == "react" else [(4, "hire", "Good automation skills."), (4, "hire", "Good fit for the team.")],
               "passed", "Recommended for an offer.")
        app = r.reload(app)
        if outcome == "offer_sent":
            r.offer(app, 315000, w.today + timedelta(days=35), w.today + timedelta(days=6))
        elif outcome == "offer_declined":
            offer = r.offer(app, 165000, w.today + timedelta(days=20), w.today + timedelta(days=7))
            r.respond(offer, "declined", "Accepted a counter-offer from her current employer.")
        elif outcome == "hired":
            joining = w.today + timedelta(days=7 - w.today.weekday())          # next Monday
            offer = r.offer(app, 330000, joining, joining - timedelta(days=1))
            r.respond(offer, "accepted", "Signed offer received.")
            app = r.reload(app)
            data(r.api, "POST", f"/recruitment/applications/{app['id']}/hire", {
                "rowVersion": app["rowVersion"], "cnic": "35202-7310452-3",
                "remarks": "Joins the web team under Faisal Javed."})
            hired_name = f"{first} {last}"

    # The graduate role was filled in August: close it.
    ase = data(r.api, "GET", f"/recruitment/openings/{openings['ase']['id']}")
    data(r.api, "POST", f"/recruitment/openings/{ase['id']}/close", {"rowVersion": ase["rowVersion"]})

    dash = data(r.api, "GET", f"/recruitment/dashboard?year={w.today.year}")
    t = dash["tiles"]
    print(f"   recruitment: {len(openings)} openings, {len(APPLICANTS)} applicants, {r.counts['interviews']} interviews "
          f"({r.counts['evaluations']} evaluations), {r.counts['offers']} offers, hired {hired_name}; dashboard: "
          f"{t['openOpenings']} open, {t['applications']} applications, {t['upcomingInterviews']} upcoming interviews")
