"""Work part, Custom Forms: HR (Ayesha Khan) builds an IT equipment request form and the annual offsite
preferences form for everyone, a team dinner venue vote that is now closed, and a draft training needs
assessment. Many people (not everyone) fill them in from My Forms."""
import random

from scripts.demo_data import World
from scripts.demo_data._work_util import active_people, day, iso


def _opt(field: dict, label: str) -> int:
    return int(next(o["id"] for o in field["options"] if o["label"] == label))


def _form(api, body: dict, publish: bool) -> dict:
    form = api("POST", "/forms", body)["data"]
    if publish:
        form = api("POST", f"/forms/{form['id']}/publish", {"rowVersion": form["rowVersion"]})["data"]
    return form


def seed(w: World) -> dict:
    counts = dict(forms=0, form_responses=0)
    hr = w.as_("Ayesha Khan")
    everyone = active_people(w)
    rnd = random.Random(1509)

    def choice(label: str, type_: str, options: list[str], required: bool = False, section: str | None = None,
               help_text: str | None = None) -> dict:
        return {"type": type_, "label": label, "required": required, "sectionKey": section, "helpText": help_text,
                "options": [{"label": o} for o in options]}

    def field(label: str, type_: str, required: bool = False, section: str | None = None, help_text: str | None = None,
              lo: float | None = None, hi: float | None = None) -> dict:
        return {"type": type_, "label": label, "required": required, "sectionKey": section, "helpText": help_text,
                "min": lo, "max": hi}

    def submit(name: str, form: dict, values: dict[str, object]) -> None:
        by_label = {f["label"]: f for f in form["fields"]}
        answers = []
        for label, value in values.items():
            f = by_label[label]
            if f["type"] in ("single_choice", "dropdown"):
                value = _opt(f, value)
            elif f["type"] == "multiple_choice":
                value = [_opt(f, v) for v in value]
            answers.append({"fieldId": int(f["id"]), "value": value})
        w.as_(name)("POST", f"/forms/{form['id']}/responses", {"answers": answers})
        counts["form_responses"] += 1

    # ------------------------------------------------------------------ IT equipment request
    equipment = ["Laptop", "Monitor", "Keyboard and mouse", "Headset", "Docking station", "Other"]
    it_form = _form(hr, {
        "title": "IT equipment request", "category": "IT",
        "description": "Ask for new or replacement equipment. IT (Waqas and Junaid) picks requests up within two "
                       "working days.",
        "audience": {"kind": "everyone"}, "oneResponsePerPerson": False, "anonymous": False,
        "fields": [
            choice("Equipment needed", "dropdown", equipment, True),
            field("Why do you need it?", "long_text", True),
            choice("Urgency", "single_choice", ["Low", "Normal", "Urgent"], True),
            field("Needed by", "date"),
            field("Current asset tag (if replacing)", "short_text", help_text="Printed on the sticker, e.g. TE-LT-0142"),
            field("My line manager has agreed", "checkbox"),
        ]}, True)
    counts["forms"] += 1
    it_requests = [
        ("Zain Abbas", "Monitor", "A second screen for code review and database work.", "Normal", 7, None, True),
        ("Zain Abbas", "Docking station", "My laptop has two USB-C ports; I need a dock for the second monitor.",
         "Low", 10, None, True),
        ("Hira Shahid", "Other", "An Android test phone with Android 14 (Samsung) to reproduce the leave form crash.",
         "Urgent", 2, None, True),
        ("Saad Qureshi", "Headset", "For client calls and the daily stand-up from home.", "Normal", 5, None, False),
        ("Maham Zafar", "Monitor", "A colour-accurate monitor for design work.", "Normal", 14, "TE-MN-0088", True),
        ("Komal Shah", "Laptop", "My laptop shuts down on battery during client demos.", "Urgent", 3, "TE-LT-0117", True),
        ("Danish Iqbal", "Keyboard and mouse", "The keyboard's Enter key is sticking.", "Low", None, "TE-KB-0203", False),
        ("Usman Ghani", "Monitor", "Payroll reconciliation needs two spreadsheets side by side.", "Normal", 6, None, True),
        ("Taha Saleem", "Headset", "Webinars and campaign calls.", "Low", 12, None, False),
        ("Farah Naz", "Laptop", "Current laptop is five years old and very slow with the accounting software.",
         "Normal", 15, "TE-LT-0061", True),
    ]
    for name, what, why, urgency, needed, tag, agreed in it_requests:
        values = {"Equipment needed": what, "Why do you need it?": why, "Urgency": urgency,
                  "My line manager has agreed": agreed}
        if needed is not None:
            values["Needed by"] = iso(day(w, needed))
        if tag:
            values["Current asset tag (if replacing)"] = tag
        submit(name, it_form, values)

    # ------------------------------------------------------------------ annual offsite preferences
    offsite = _form(hr, {
        "title": "Annual offsite preferences 2026", "category": "Events",
        "description": "Two days away together. Tell us if you are coming and what you would enjoy; we book travel "
                       "and rooms from these answers.",
        "closesOn": iso(day(w, 10, False)), "audience": {"kind": "everyone"}, "oneResponsePerPerson": True,
        "anonymous": False,
        "sections": [{"key": "attend", "title": "Attendance"}, {"key": "prefs", "title": "Your preferences",
                                                                "description": "Pick as many activities as you like."}],
        "fields": [
            choice("Will you attend?", "single_choice", ["Yes", "No", "Not sure yet"], True, "attend"),
            choice("Travelling from", "dropdown", ["Lahore", "Islamabad"], True, "attend"),
            choice("Preferred destination", "single_choice",
                   ["Nathia Gali", "Murree", "Hunza", "Skardu", "Lahore city day out"], False, "prefs"),
            choice("Activities you would enjoy", "multiple_choice",
                   ["Hiking", "Bonfire and music", "Team games", "Cricket match", "Spa and relaxation",
                    "Workshops"], False, "prefs"),
            choice("Dietary preference", "dropdown", ["No restrictions", "Vegetarian", "Diabetic-friendly", "Other"],
                   False, "prefs"),
            field("How excited are you?", "rating", False, "prefs", lo=1, hi=5),
            field("Anything we should know?", "short_text", False, "prefs",
                  help_text="Allergies, medication, travel or room needs"),
        ]}, True)
    counts["forms"] += 1
    notes = ["Mild peanut allergy.", "I would like a ground-floor room.", "Travelling with my own car.",
             "Need to be back by Sunday evening.", "Happy to help organise games!"]
    for name in rnd.sample(everyone, 19):
        r = random.Random("offsite" + name)
        attend = r.choice(["Yes", "Yes", "Yes", "Yes", "Not sure yet", "No"])
        branch = w.employees[name].get("branchName") or ""
        values = {"Will you attend?": attend, "Travelling from": "Islamabad" if "Islamabad" in branch else "Lahore"}
        if attend != "No":
            values |= {"Preferred destination": r.choice(["Nathia Gali", "Hunza", "Hunza", "Skardu", "Murree"]),
                       "Activities you would enjoy": r.sample(["Hiking", "Bonfire and music", "Team games",
                                                               "Cricket match", "Spa and relaxation", "Workshops"],
                                                              r.choice([1, 2, 3])),
                       "Dietary preference": r.choice(["No restrictions"] * 4 + ["Vegetarian", "Diabetic-friendly"]),
                       "How excited are you?": r.choice([5, 5, 4, 4, 3])}
            if r.random() < 0.3:
                values["Anything we should know?"] = r.choice(notes)
        submit(name, offsite, values)

    # ------------------------------------------------------------------ team dinner vote, now closed
    dinner = _form(w.as_("Shelley Kannes"), {
        "title": "Q3 team dinner: venue vote", "category": "Events",
        "description": "Vote for the venue of the Q3 team dinner (Lahore office).",
        "audience": {"kind": "branches", "ids": [int(w.branches["Lahore Head Office"]["id"])]},
        "oneResponsePerPerson": True, "anonymous": False,
        "fields": [
            choice("Venue", "single_choice", ["Monal Lahore", "Andaaz", "Cafe Aylanto", "Salt'n Pepper Village"], True),
            choice("Preferred evening", "dropdown", ["Thursday", "Friday", "Saturday"], True),
            field("Bringing a plus one?", "checkbox"),
        ]}, True)
    counts["forms"] += 1
    lahore = [n for n in everyone if w.employees[n].get("branchName") == "Lahore Head Office"]
    for name in rnd.sample(lahore, min(14, len(lahore))):
        r = random.Random("dinner" + name)
        submit(name, dinner, {"Venue": r.choice(["Andaaz", "Andaaz", "Monal Lahore", "Cafe Aylanto", "Salt'n Pepper Village"]),
                              "Preferred evening": r.choice(["Friday", "Friday", "Thursday", "Saturday"]),
                              "Bringing a plus one?": r.random() < 0.3})
    shelley = w.as_("Shelley Kannes")
    dinner = shelley("GET", f"/forms/{dinner['id']}")["data"]
    shelley("POST", f"/forms/{dinner['id']}/close", {"rowVersion": dinner["rowVersion"]})

    # ------------------------------------------------------------------ a draft
    _form(hr, {
        "title": "Training needs assessment 2027", "category": "Learning",
        "description": "Draft: to go out with the performance reviews in January.",
        "audience": {"kind": "everyone"}, "oneResponsePerPerson": True, "anonymous": False,
        "fields": [
            choice("Areas you want to grow in", "multiple_choice",
                   ["Technical skills", "Leadership", "Communication", "Project management", "Domain (HR / payroll)"],
                   True),
            field("A course or certification you have in mind", "long_text"),
            field("How confident are you in your current role?", "rating", lo=1, hi=5),
        ]}, False)
    counts["forms"] += 1
    return counts
