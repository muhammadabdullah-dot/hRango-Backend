"""Training for the talent part: categories and programmes (React advanced, leadership for new managers, fire
safety and more), sessions held (attendance marked by HR, closed, participants' feedback) and coming up
(nominations by HR, by managers waiting for approval, and staff's own), and one cancelled session."""
import random
from datetime import date, timedelta

from scripts.demo_data import World
from scripts.demo_data._talent_common import attempt, data, eid, iso, only_current, workdays_after

CATEGORIES = ["Technical", "Leadership and Management", "Health and Safety", "Compliance", "Soft Skills"]

# key -> (title, category, mode, provider type, provider, hours, cost per head, certificate, validity, mandatory)
PROGRAMS = {
    "react": ("Advanced React and TypeScript", "Technical", "classroom", "internal", None, 18, 0, True, None, False,
              "Hooks in depth, state management, performance profiling and typed APIs."),
    "leaders": ("Leadership for New Managers", "Leadership and Management", "blended", "external",
                "Crescent Leadership Academy", 16, 45000, True, 36, False,
                "Delegation, feedback conversations, running one-to-ones and handling conflict."),
    "fire": ("Fire Safety and Emergency Evacuation", "Health and Safety", "classroom", "external",
             "SafeWork Training Services", 4, 2500, True, 12, True,
             "Fire classes, extinguisher drill, evacuation routes and assembly points."),
    "infosec": ("Information Security Awareness", "Compliance", "online", "internal", None, 2, 0, False, None, True,
                "Phishing, passwords and MFA, handling client data, reporting incidents."),
    "comms": ("Effective Business Communication", "Soft Skills", "classroom", "external",
              "Lahore Business Skills Centre", 8, 12000, False, None, False,
              "Clear emails, meeting notes and presenting to clients."),
}

SD = ["Areeba Hameed", "Zain Abbas", "Hira Shahid", "Saad Qureshi", "Maham Zafar"]
LEADS = ["Faisal Javed", "Rabia Anwar", "Omer Farooq", "Waqas Butt"]


def seed(w: World) -> None:
    hr = w.admin
    rng = random.Random(7)
    data(hr, "PUT", "/training/settings", {"minAttendancePercent": 75, "allowSelfNomination": True,
                                           "rowVersion": (data(hr, "GET", "/training/settings") or {}).get("rowVersion")})
    cats = {c: data(hr, "POST", "/training/categories", {"name": c})["id"] for c in CATEGORIES}
    programs = {}
    for key, (title, cat, mode, ptype, provider, hours, cost, cert, valid, mandatory, desc) in PROGRAMS.items():
        programs[key] = data(hr, "POST", "/training/programs", {
            "title": title, "trainingCategoryId": int(cats[cat]), "description": desc, "deliveryMode": mode,
            "providerType": ptype, "providerName": provider, "durationHours": hours, "costPerHead": cost,
            "issuesCertificate": cert, "certificateValidityMonths": valid, "isMandatory": mandatory})

    def session(key: str, start, end, title=None, trainer=None, trainer_name=None, venue=None, link=None,
                capacity=None, deadline=None, hours=(10, 13)) -> dict:
        prog = programs[key]
        return data(hr, "POST", "/training/sessions", {
            "trainingProgramId": int(prog["id"]), "title": title, "startDate": iso(start), "endDate": iso(end),
            "startTime": f"{hours[0]:02d}:00:00", "endTime": f"{hours[1]:02d}:00:00",
            "deliveryMode": "online" if link else "classroom", "venue": venue, "onlineLink": link,
            "trainerType": "internal" if trainer else "external",
            "trainerEmployeeId": eid(w, trainer) if trainer else None, "trainerName": trainer_name,
            "capacity": capacity, "nominationDeadline": iso(deadline), "cost": None})

    def nominate(api, s: dict, people: list[str], remarks: str | None = None) -> list[dict]:
        people = only_current(w, people)
        if not people:
            return []
        rows = data(api, "POST", "/training/enrolments", {
            "trainingSessionId": int(s["id"]), "employeeIds": [eid(w, p) for p in people], "remarks": remarks})
        counts["enrolments"] += len(rows)
        return rows

    counts = {"sessions": 0, "enrolments": 0, "marks": 0, "feedback": 0}

    def held(s: dict, people: list[str], absent: dict[str, set[int]], feedback_from: list[str]) -> None:
        """A session that took place: HR enrols, marks each day, closes it; participants give feedback."""
        enrolled = {e["employeeName"]: e for e in nominate(hr, s, people)}
        n, d, last = 0, date.fromisoformat(s["startDate"]), date.fromisoformat(s["endDate"])
        while d <= last:
            marks = [{"enrolmentId": int(e["id"]),
                      "status": "absent" if n in absent.get(name, set()) else "present",
                      "remarks": "Informed in advance." if n in absent.get(name, set()) else None}
                     for name, e in enrolled.items()]
            data(hr, "PUT", f"/training/sessions/{s['id']}/attendance",
                 {"attendanceDate": iso(d), "marks": marks})
            counts["marks"] += len(marks)
            d += timedelta(days=1)
            n += 1
        cur = data(hr, "GET", f"/training/sessions/{s['id']}")
        data(hr, "POST", f"/training/sessions/{s['id']}/complete", {"rowVersion": cur["rowVersion"]})
        comments = ["Very practical; the exercises were the best part.", "Good trainer, a bit rushed at the end.",
                    "Useful. Would like a follow-up session.", "Clear and well organised."]
        for name in (n for n in feedback_from if n in enrolled):
            status, _ = attempt(w.as_(name), "PUT", f"/training/enrolments/{enrolled[name]['id']}/feedback", {
                "overallRating": rng.randint(4, 5), "trainerRating": rng.randint(3, 5),
                "contentRating": rng.randint(4, 5), "comments": rng.choice(comments)})
            counts["feedback"] += status < 300

    # Held: React advanced (three days, about six weeks ago), fire safety (everyone in Lahore, two weeks ago).
    r_start = w.days_ago(45)
    while r_start.weekday() > 2:
        r_start -= timedelta(days=1)
    s = session("react", r_start, r_start + timedelta(days=2), title="Advanced React and TypeScript: batch 1",
                trainer="Faisal Javed", venue="Training room, Gulberg office", capacity=12)
    held(s, SD, {"Hira Shahid": {1}, "Maham Zafar": {1, 2}}, ["Areeba Hameed", "Zain Abbas", "Hira Shahid", "Saad Qureshi"])
    counts["sessions"] += 1

    f_day = w.days_ago(14)
    while f_day.weekday() > 4:
        f_day -= timedelta(days=1)
    s = session("fire", f_day, f_day, title="Fire safety drill: Lahore office", trainer_name="Imtiaz Baig",
                venue="Ground floor and parking", hours=(15, 17))
    lahore = [n for n, e in sorted(w.employees.items())
              if e.get("branchName") == "Lahore Head Office" and n != "Imran Siddiqui"
              and str(e.get("joiningDate")) <= iso(f_day)]            # not the new hire who joins next week
    held(s, lahore, {"Usman Ghani": {0}, "Junaid Akhtar": {0}},
         ["Ayesha Khan", "Bilal Ahmed", "Danish Iqbal", "Farah Naz", "Kashif Mehmood", "Mehwish Akram"])
    counts["sessions"] += 1

    # Coming up.
    days = workdays_after(w.today, 15)
    s = session("leaders", days[7], days[8], title="Leadership for New Managers: November cohort",
                trainer_name="Sadia Rehman (Crescent Leadership Academy)", venue="Pearl Continental, Lahore",
                capacity=8, deadline=days[3], hours=(9, 17))
    nominate(hr, s, ["Faisal Javed", "Waqas Butt"], "Nominated by HR after the H1 reviews.")
    # Managers nominate their leads; these wait for HR's approval.
    for manager, lead in (("Haroon Rashid", "Rabia Anwar"), ("Haroon Rashid", "Omer Farooq")):
        if not only_current(w, [manager, lead]) == [manager, lead]:
            continue
        status, _ = attempt(w.as_(manager), "POST", "/training/enrolments", {
            "trainingSessionId": int(s["id"]), "employeeIds": [eid(w, lead)],
            "remarks": "New team lead; please include in this cohort."})
        if status >= 300:
            nominate(hr, s, [lead], "Nominated by HR.")
        else:
            counts["enrolments"] += 1
    counts["sessions"] += 1

    s = session("infosec", days[2], days[2], title="Information Security Awareness: Q4",
                trainer="Junaid Akhtar", link="https://teams.microsoft.com/l/meetup-join/demo-infosec",
                deadline=days[1], hours=(11, 13))
    nominate(hr, s, ["Komal Shah", "Taha Saleem", "Asad Mirza", "Farah Naz", "Usman Ghani"],
             "Mandatory for staff handling client data.")
    for name in only_current(w, ("Hira Shahid", "Maham Zafar", "Danish Iqbal")):          # staff nominating themselves
        data(w.as_(name), "POST", "/training/enrolments", {"trainingSessionId": int(s["id"]), "employeeIds": [],
                                                            "remarks": "I would like to attend."})
        counts["enrolments"] += 1
    # HR approves two of the self-nominations and leaves one waiting.
    waiting = [e for e in hr.all(f"/training/enrolments?sessionId={s['id']}&status=requested")
               if e["trainingSessionId"] == s["id"] and e["status"] == "requested"]
    for e in waiting[:2]:
        data(hr, "POST", f"/training/enrolments/{e['id']}/approve", {"remarks": "Approved.", "rowVersion": e["rowVersion"]})
    counts["sessions"] += 1

    s = session("react", days[12], days[14], title="Advanced React and TypeScript: batch 2", trainer="Areeba Hameed",
                venue="Training room, Gulberg office", capacity=12, deadline=days[9])
    nominate(w.as_("Faisal Javed"), s, ["Hira Shahid", "Saad Qureshi"], "Missed days in batch 1 / new joiner.")
    counts["sessions"] += 1

    # A session called off.
    s = session("comms", days[5], days[5], title="Effective Business Communication", trainer_name="Lahore Business Skills Centre",
                venue="Training room, Gulberg office", hours=(10, 16))
    nominate(hr, s, ["Komal Shah", "Taha Saleem", "Maham Zafar"])
    cur = data(hr, "GET", f"/training/sessions/{s['id']}")
    data(hr, "POST", f"/training/sessions/{s['id']}/cancel",
         {"reason": "The trainer is unavailable; moved to next quarter.", "rowVersion": cur["rowVersion"]})
    counts["sessions"] += 1

    print(f"   training: {len(programs)} programmes, {counts['sessions']} sessions (2 held, 1 cancelled), "
          f"{counts['enrolments']} nominations, {counts['marks']} attendance marks, {counts['feedback']} feedback")
