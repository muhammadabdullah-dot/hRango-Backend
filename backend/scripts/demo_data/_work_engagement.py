"""Work part, Engagement: company announcements, newsfeed posts (welcomes for the people on probation, a
birthday, a work anniversary, a product launch, a client win) with colleagues' reactions, comments and
views, and surveys: an employee satisfaction survey most people answered, a closed lunch pulse and a draft."""
import random
from datetime import date

from scripts.demo_data import World
from scripts.demo_data._work_util import active_people, day, iso


def _closest(w: World, field: str, skip: set[str]) -> tuple[str, int, int]:
    """The person whose birthday / joining anniversary is nearest today: (name, days from today, years)."""
    best = None
    for p in w.people:
        name = f"{p['first']} {p['last']}"
        if name in skip or name not in active_people(w):
            continue
        d = date.fromisoformat(p[field])
        for year in (w.today.year - 1, w.today.year, w.today.year + 1):
            try:
                when = d.replace(year=year)
            except ValueError:            # 29 February
                when = date(year, 3, 1)
            delta = (when - w.today).days
            years = year - d.year
            if years < 1:
                continue
            # Prefer one that has just happened (people post on the day or soon after) over one far ahead.
            score = abs(delta) if delta <= 0 else delta + 3
            if best is None or score < best[0]:
                best = (score, name, delta, years)
    return best[1], best[2], best[3]


def _when(delta: int, d: date) -> str:
    if delta == 0:
        return "today"
    if delta == -1:
        return "yesterday"
    if delta == 1:
        return "tomorrow"
    return f"on {d:%A} {d.day} {d:%B}"


def seed(w: World) -> dict:
    counts = dict(announcements=0, posts=0, post_comments=0, reactions=0, views=0, surveys=0, survey_responses=0,
                  survey_skips=0)
    rnd = random.Random(2026)
    hr = w.as_("Shelley Kannes")
    eid = w.emp_id
    everyone = active_people(w)

    # ------------------------------------------------------------------ announcements (HR)
    announcements = [
        dict(kind="notice", title="Winter office timings",
             body="From 1 November office hours are 9:30 am to 6:00 pm at both offices. Biometric shift rules are "
                  "updated automatically; no action is needed from you.", publish_from=iso(day(w, -3, False)),
             publish_to=iso(day(w, 30, False))),
        dict(kind="event", title="Quarterly town hall",
             body="Imran will share the Q3 results, the Retail POS win and the 2027 hiring plan. Lahore in the "
                  "main hall, Islamabad on the video link.", event_date=iso(day(w, 7)),
             publish_from=iso(day(w, -2, False)), publish_to=iso(day(w, 7))),
        dict(kind="event", title="Annual offsite 2026",
             body="Two days in the northern areas for everyone. Fill in the Annual Offsite Preferences form under "
                  "My Forms so we can plan travel, rooms and food.", event_date=iso(day(w, 38)),
             publish_from=iso(day(w, -1, False)), publish_to=iso(day(w, 38))),
        dict(kind="notice", title="Biometric re-enrolment: Islamabad office",
             body="The new fingerprint device at the Islamabad reception goes live on Monday. Please re-enrol with "
                  "Junaid between 10 am and 1 pm this week.", publish_from=iso(day(w, -6, False)),
             publish_to=iso(day(w, 4, False))),
        dict(kind="notice", title="Health insurance cards are ready",
             body="Collect your 2026 health insurance card from Bilal at the admin desk.",
             publish_from=iso(day(w, -25, False)), publish_to=iso(day(w, -8, False))),
    ]
    for a in announcements:
        hr("POST", "/organisation/announcements", a)
        counts["announcements"] += 1

    # ------------------------------------------------------------------ newsfeed
    probation = [p for p in w.people if p.get("status") == "probation"]
    bday_name, bday_delta, _ = _closest(w, "born", set())
    anniv_name, anniv_delta, anniv_years = _closest(w, "joined", {f"{p['first']} {p['last']}" for p in probation})
    person = {f"{p['first']} {p['last']}": p for p in w.people}
    bday_date = day(w, bday_delta, False)
    anniv_date = day(w, anniv_delta, False)
    anniv_manager = person[anniv_name].get("manager") or "Imran Siddiqui"
    bday_poster = "Ayesha Khan" if bday_name != "Ayesha Khan" else "Shelley Kannes"
    bday_first = person[bday_name]["first"]

    posts = []
    for p in probation:
        name = f"{p['first']} {p['last']}"
        joined = date.fromisoformat(p["joined"])
        team = {"Software Development": ("the web team", ["Faisal Javed", "Areeba Hameed", "Zain Abbas", "Haroon Rashid"]),
                "Quality Assurance": ("the QA team", ["Rabia Anwar", "Danish Iqbal", "Haroon Rashid"])}.get(
            p["dept"], (p["dept"], [p.get("manager", "Shelley Kannes")]))
        posts.append(dict(
            author="Shelley Kannes", mentions=[name, p["manager"]],
            body=f"Please welcome @{name}, who joined {team[0]} as {p['title']} on {joined:%d %B}. "
                 f"{p['first']} reports to @{p['manager']}. Say hello when you pass by! 👋",
            comments=[(team[1][0], f"Welcome aboard {p['first']}! Glad to have you with us."),
                      (team[1][1], "Welcome! Ping me if you need help with the dev set-up.")]
                     + ([(team[1][2], f"Great to have you here, {p['first']}.")] if len(team[1]) > 2 else []),
            reply=(name, "Thank you all, happy to be here!"),
            reactors=rnd.sample([n for n in everyone if n != name], 14), kind="celebrate"))
    posts.append(dict(
        author=bday_poster, mentions=[bday_name],
        body=(f"Happy birthday @{bday_name}! 🎂 Cake in the pantry at 4 pm." if bday_delta == 0 else
              f"Belated birthday wishes to @{bday_name}, whose birthday was {_when(bday_delta, bday_date)}! 🎂"
              if bday_delta < 0 else
              f"@{bday_name}'s birthday is {_when(bday_delta, bday_date)} 🎂 Cake in the pantry at 4 pm, don't tell "
              f"{bday_first}!"),
        comments=[("Imran Siddiqui", f"Happy birthday {bday_first}, have a great year ahead."),
                  ("Nadia Hussain", "Many happy returns! 🎉"), ("Sana Malik", "Happy birthday! Save me a slice.")],
        reply=(bday_name, "Thank you everyone, you made my day."),
        reactors=rnd.sample([n for n in everyone if n != bday_name], 17), kind="love"))
    posts.append(dict(
        author=anniv_manager, mentions=[anniv_name],
        body=(f"Happy work anniversary @{anniv_name}: {anniv_years} years at Top Edge today!" if anniv_delta == 0 else
              f"Happy work anniversary @{anniv_name}, who completed {anniv_years} years at Top Edge "
              f"{_when(anniv_delta, anniv_date)}!" if anniv_delta < 0 else
              f"@{anniv_name} completes {anniv_years} years at Top Edge {_when(anniv_delta, anniv_date)}!")
             + " Thank you for everything you do for the team. 🙌",
        comments=[("Haroon Rashid", f"Congratulations {person[anniv_name]['first']}, here's to many more."),
                  ("Shelley Kannes", "Happy work anniversary! 🎉")],
        reply=(anniv_name, "Time flies. Thank you all!"),
        reactors=rnd.sample([n for n in everyone if n != anniv_name], 12), kind="celebrate"))
    posts.append(dict(
        author="Haroon Rashid", mentions=["Zain Abbas", "Areeba Hameed", "Danish Iqbal", "Mehwish Akram", "Maham Zafar"],
        body="hRango v2.4 is live for all customers 🚀 Biometric punches now retry when a device loses its link, payroll "
             "exports the HBL bank file, and leave balances got a fresh look. Thanks @Zain Abbas @Areeba Hameed "
             "@Maham Zafar and QA @Danish Iqbal @Mehwish Akram for a clean release.",
        comments=[("Imran Siddiqui", "Great work team. Two customers already wrote in about the bank file."),
                  ("Shelley Kannes", "The new leave cards are so much clearer, thank you!"),
                  ("Asad Mirza", "Sharing the release notes with prospects this week.")],
        reply=("Zain Abbas", "Thanks! The payroll team found the edge cases early, which helped a lot."),
        reactors=rnd.sample([n for n in everyone if n != "Haroon Rashid"], 20), kind="celebrate", pin=True))
    posts.append(dict(
        author="Asad Mirza", mentions=["Faisal Javed", "Komal Shah"],
        body="Signed! We are building the point of sale for a 40-store retail chain. Kick-off is done and "
             "@Faisal Javed's team is already in the build phase. Big thanks to @Komal Shah for the proposal work.",
        comments=[("Haroon Rashid", "Great win. FBR integration is the one to watch."),
                  ("Komal Shah", "Team effort! The demo by Areeba closed it.")],
        reactors=rnd.sample([n for n in everyone if n != "Asad Mirza"], 13), kind="like"))
    posts.append(dict(
        author="Imran Siddiqui", mentions=[],
        body="Thank you all for a strong Q3: revenue up 18% on last year and two new enterprise customers. "
             "See you at the town hall next week, bring your questions.",
        comments=[("Haroon Rashid", "Proud of this team."), ("Nadia Hussain", "Detailed numbers will be in the town hall deck.")],
        reactors=rnd.sample([n for n in everyone if n != "Imran Siddiqui"], 18), kind="insightful"))
    posts.append(dict(
        author="Waqas Butt", mentions=[],
        body="IT tip of the week 🔐 Lock your screen (Windows + L) whenever you leave your desk. MFA for email "
             "starts with the IT team this week and reaches everyone next month.",
        comments=[("Junaid Akhtar", "Ask us at the IT desk if your authenticator app gives you trouble.")],
        reactors=rnd.sample([n for n in everyone if n != "Waqas Butt"], 8), kind="support"))
    posts.append(dict(
        author="Taha Saleem", mentions=[], visibility="department", dept="Sales & Marketing",
        body="New brochure drafts for the HR suite are in the shared folder. Feedback by Thursday please.",
        comments=[("Komal Shah", "Page 3 needs the new payroll screenshots.")],
        reactors=["Asad Mirza", "Komal Shah"], kind="like"))
    posts.append(dict(
        author="Maham Zafar", mentions=["Omer Farooq"],
        body="Design critique Friday is back: bring one screen you are proud of and one you are not. Thanks "
             "@Omer Farooq for hosting. 🎨",
        comments=[("Areeba Hameed", "Count the frontend team in!")],
        reactors=rnd.sample([n for n in everyone if n != "Maham Zafar"], 7), kind="like"))

    kinds = ["like", "love", "celebrate", "support", "insightful"]
    for post in posts:
        author = w.as_(post["author"])
        body = {"body": post["body"], "visibility": post.get("visibility", "public"),
                "mentionIds": [eid(n) for n in post["mentions"]]}
        if post.get("dept"):
            body["departmentId"] = int(w.departments[post["dept"]]["id"])
        made = author("POST", "/engagement/posts", body)["data"]
        pid = made["id"]
        counts["posts"] += 1
        seen = set()
        for i, name in enumerate(post["reactors"]):
            kind = post["kind"] if i % 3 else rnd.choice(kinds)
            w.as_(name)("POST", f"/engagement/posts/{pid}/view")
            w.as_(name)("PUT", f"/engagement/posts/{pid}/reaction", {"kind": kind})
            seen.add(name)
            counts["reactions"] += 1
        first_comment = None
        for name, text in post["comments"]:
            if name not in seen:
                w.as_(name)("POST", f"/engagement/posts/{pid}/view")
                seen.add(name)
            c = w.as_(name)("POST", f"/engagement/posts/{pid}/comments", {"body": text})["data"]
            first_comment = first_comment or c
            counts["post_comments"] += 1
        if post.get("reply") and first_comment:
            name, text = post["reply"]
            w.as_(name)("POST", f"/engagement/posts/{pid}/comments", {"body": text, "parentId": int(first_comment["id"])})
            w.as_(name)("PUT", f"/engagement/comments/{first_comment['id']}/like", {"liked": True})
            counts["post_comments"] += 1
        # People who scrolled past without reacting.
        for name in rnd.sample(everyone, 6):
            if name not in seen and post.get("visibility", "public") == "public":
                w.as_(name)("POST", f"/engagement/posts/{pid}/view")
                seen.add(name)
        counts["views"] += len(seen)
        if post.get("pin"):
            hr("PATCH", f"/engagement/posts/{pid}/pin", {"pinned": True})

    # ------------------------------------------------------------------ surveys
    survey = hr("POST", "/engagement/surveys", {
        "title": "Employee satisfaction survey – Q4 2026",
        "description": "Ten minutes, fully anonymous. Results are shared at the town hall and drive next year's "
                       "people plan.",
        "isAnonymous": True, "opensOn": iso(day(w, -6, False)), "closesOn": iso(day(w, 8, False)),
        "questions": [
            {"questionType": "rating", "questionText": "Overall, how satisfied are you working at Top Edge?",
             "isRequired": True, "scaleMin": 1, "scaleMax": 5, "scaleMinLabel": "Very unsatisfied",
             "scaleMaxLabel": "Very satisfied"},
            {"questionType": "rating", "questionText": "How would you rate your work-life balance?",
             "isRequired": True, "scaleMin": 1, "scaleMax": 5, "scaleMinLabel": "Poor", "scaleMaxLabel": "Excellent"},
            {"questionType": "single", "questionText": "Do you feel your work is recognised?", "isRequired": True,
             "options": ["Always", "Often", "Sometimes", "Rarely", "Never"]},
            {"questionType": "multiple", "questionText": "What do you value most about working here?",
             "options": ["My team", "Learning and growth", "Flexible hours", "Salary and benefits",
                         "Interesting projects", "Office location"]},
            {"questionType": "dropdown", "questionText": "How likely are you to recommend Top Edge as a place to work?",
             "isRequired": True, "options": ["Very likely", "Likely", "Not sure", "Unlikely"]},
            {"questionType": "paragraph", "questionText": "What is one thing we should improve?"},
        ]})["data"]
    survey = hr("PATCH", f"/engagement/surveys/{survey['id']}/publish", {"rowVersion": survey["rowVersion"]})["data"]
    counts["surveys"] += 1
    q = survey["questions"]
    improve = ["More structured onboarding for new joiners.", "Clearer promotion criteria.",
               "Quieter space for focused work on the 2nd floor.", "Better coffee, honestly.",
               "More cross-team knowledge sharing sessions.", "Faster laptop replacements.",
               "Earlier notice for weekend releases.", "A learning budget per person.",
               "Parking at the Lahore office.", "Fewer meetings on Fridays."]
    order = rnd.sample(everyone, len(everyone))
    responders, skippers = order[:21], order[21:23]
    for name in responders:
        r = random.Random(name)
        mood = r.choice([5, 4, 4, 4, 3, 3, 5, 2])
        answers = [
            {"questionId": int(q[0]["id"]), "rating": mood},
            {"questionId": int(q[1]["id"]), "rating": max(1, min(5, mood + r.choice([-1, 0, 0, 1])))},
            {"questionId": int(q[2]["id"]), "optionIds": [int(q[2]["options"][min(4, max(0, 5 - mood + r.choice([-1, 0, 0])))]["id"])]},
            {"questionId": int(q[3]["id"]), "optionIds": [int(o["id"]) for o in r.sample(q[3]["options"], r.choice([1, 2, 2, 3]))]},
            {"questionId": int(q[4]["id"]), "optionIds": [int(q[4]["options"][min(3, max(0, 4 - mood + r.choice([0, 0, 1])))]["id"])]},
        ]
        if r.random() < 0.6:
            answers.append({"questionId": int(q[5]["id"]), "text": r.choice(improve)})
        w.as_(name)("POST", f"/engagement/my-surveys/{survey['id']}/response", {"answers": answers})
        counts["survey_responses"] += 1
    for name in skippers:
        w.as_(name)("POST", f"/engagement/my-surveys/{survey['id']}/skip")
        counts["survey_skips"] += 1

    # A lunch pulse for the Lahore office: answered, then closed.
    lahore = w.branches["Lahore Head Office"]
    pulse = hr("POST", "/engagement/surveys", {
        "title": "Cafeteria and lunch pulse", "description": "Help us choose the new lunch vendor.",
        "isAnonymous": False, "opensOn": iso(day(w, -20, False)), "closesOn": iso(day(w, 3, False)),
        "audience": [{"unitType": "branch", "unitId": int(lahore["id"])}],
        "questions": [
            {"questionType": "single", "questionText": "How often do you order lunch at the office?", "isRequired": True,
             "options": ["Every day", "Two or three times a week", "Rarely", "Never"]},
            {"questionType": "rating", "questionText": "Rate the current vendor's food", "isRequired": True,
             "scaleMin": 1, "scaleMax": 5, "scaleMinLabel": "Poor", "scaleMaxLabel": "Great"},
            {"questionType": "text", "questionText": "A dish you would like on the menu"},
        ]})["data"]
    pulse = hr("PATCH", f"/engagement/surveys/{pulse['id']}/publish", {"rowVersion": pulse["rowVersion"]})["data"]
    counts["surveys"] += 1
    pq = pulse["questions"]
    dishes = ["Chicken karahi", "Daal chawal on Fridays", "Grilled sandwiches", "Salads", "Biryani", "Chapli kebab"]
    lahore_people = [n for n in everyone if w.employees[n].get("branchName") == lahore["name"]]
    for name in rnd.sample(lahore_people, min(13, len(lahore_people))):
        r = random.Random("pulse" + name)
        answers = [{"questionId": int(pq[0]["id"]), "optionIds": [int(r.choice(pq[0]["options"][:3])["id"])]},
                   {"questionId": int(pq[1]["id"]), "rating": r.choice([2, 3, 3, 4, 2])}]
        if r.random() < 0.7:
            answers.append({"questionId": int(pq[2]["id"]), "text": r.choice(dishes)})
        w.as_(name)("POST", f"/engagement/my-surveys/{pulse['id']}/response", {"answers": answers})
        counts["survey_responses"] += 1
    pulse = hr("GET", f"/engagement/surveys/{pulse['id']}")["data"]
    hr("PATCH", f"/engagement/surveys/{pulse['id']}/close", {"rowVersion": pulse["rowVersion"]})

    # A draft for next year.
    hr("POST", "/engagement/surveys", {
        "title": "Manager effectiveness survey 2027",
        "description": "Draft: questions to review with the department heads.",
        "isAnonymous": True, "opensOn": iso(day(w, 60, False)), "closesOn": iso(day(w, 75, False)),
        "questions": [
            {"questionType": "rating", "questionText": "My manager gives me useful feedback", "isRequired": True,
             "scaleMin": 1, "scaleMax": 5},
            {"questionType": "rating", "questionText": "My manager helps me grow", "isRequired": True,
             "scaleMin": 1, "scaleMax": 5},
            {"questionType": "paragraph", "questionText": "What should your manager start or stop doing?"},
        ]})
    counts["surveys"] += 1
    return counts
