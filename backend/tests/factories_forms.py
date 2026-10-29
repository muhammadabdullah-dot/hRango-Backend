"""Custom Form test helpers: signed-in staff and forms.

Until the default Employee role holds forms.my_forms.* (see comparison/15-custom-forms.md), `person` gives
each test user those codes as personal grants with own scope.
"""
from app.core.db import Db
from tests import factories

STAFF_CODES = ("forms.my_forms.view", "forms.my_forms.submit")
API = "/api/forms"


def execute(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def grant(db: Db, user_id: int, codes: tuple[str, ...] = STAFF_CODES, scope: str = "own") -> None:
    for code in codes:
        execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope, "
                    "reason) SELECT u.company_id, u.id, p.id, N'grant', ?, N'test' FROM auth.permission p "
                    "JOIN auth.user_account u ON u.id = ? WHERE p.code = ? "
                    "AND NOT EXISTS (SELECT 1 FROM auth.user_permission_override o "
                    "WHERE o.user_account_id = u.id AND o.company_id = u.company_id AND o.permission_id = p.id)",
                scope, user_id, code)


def person(db: Db, client, company: int, department_id: int | None = None, branch_id: int | None = None,
           first_name: str = "Staff", granted: bool = True) -> dict:
    """An employee with a sign-in (Employee role): {"employee_id", "user_id", "headers", ...}."""
    employee_id = factories.employee(db, company, branch_id=branch_id, department_id=department_id,
                                     first_name=first_name)
    user = factories.login_as(db, client, company, role_codes="employee", employee_id=employee_id)
    if granted:
        grant(db, user["user_id"])
    return {**user, "employee_id": employee_id}


def form_body(**extra) -> dict:
    """A form with a section and one question of each kind the tests answer."""
    return {"title": f"Onboarding checklist {factories.tag()}", "description": "Tell us about your first week",
            "category": "Onboarding", "closesOn": "2099-12-31", "audience": {"kind": "everyone", "ids": []},
            "oneResponsePerPerson": True, "anonymous": False,
            "sections": [{"key": "s1", "id": None, "title": "About you", "description": None}],
            "fields": [
                {"id": None, "sectionKey": None, "type": "short_text", "label": "Your laptop tag", "helpText": None,
                 "required": True, "options": [], "min": None, "max": 20},
                {"id": None, "sectionKey": "s1", "type": "single_choice", "label": "How was day one?", "helpText": None,
                 "required": True, "options": [{"id": None, "label": "Great"}, {"id": None, "label": "Fine"},
                                               {"id": None, "label": "Hard"}], "min": None, "max": None},
                {"id": None, "sectionKey": "s1", "type": "multiple_choice", "label": "What did you get?",
                 "helpText": "Tick all", "required": False,
                 "options": [{"id": None, "label": "Laptop"}, {"id": None, "label": "Badge"},
                             {"id": None, "label": "Desk"}], "min": None, "max": None},
                {"id": None, "sectionKey": "s1", "type": "rating", "label": "Rate your buddy", "helpText": None,
                 "required": False, "options": [], "min": None, "max": 5},
                {"id": None, "sectionKey": "s1", "type": "checkbox", "label": "I read the handbook", "helpText": None,
                 "required": False, "options": [], "min": None, "max": None},
            ], **extra}


def as_input(form: dict, **changes) -> dict:
    """A FormIn that keeps every id of a FormOut (for edits)."""
    sections = [{"key": s["id"], "id": s["id"], "title": s["title"], "description": s["description"]}
                for s in form["sections"]]
    fields = [{"id": f["id"], "sectionKey": f["sectionId"], "type": f["type"], "label": f["label"],
               "helpText": f["helpText"], "required": f["required"],
               "options": [{"id": o["id"], "label": o["label"]} for o in f["options"]], "min": f["min"], "max": f["max"]}
              for f in form["fields"]]
    body = {"title": form["title"], "description": form["description"], "category": form["category"],
            "closesOn": form["closesOn"],
            "audience": {"kind": form["audience"]["kind"], "ids": [t["id"] for t in form["audience"]["targets"]]},
            "oneResponsePerPerson": form["oneResponsePerPerson"], "anonymous": form["anonymous"],
            "sections": sections, "fields": fields, "rowVersion": form["rowVersion"]}
    body.update(changes)
    return body


def create(client, headers: dict, publish: bool = True, **extra) -> dict:
    r = client.post(API, json=form_body(**extra), headers=headers)
    assert r.status_code == 201, r.text
    f = r.json()["data"]
    if publish:
        r = client.post(f"{API}/{f['id']}/publish", json={"rowVersion": f["rowVersion"]}, headers=headers)
        assert r.status_code == 200, r.text
        f = r.json()["data"]
    return f


def answers_for(form: dict, choice: int = 0, picks: tuple[int, ...] = (0, 1), rating: int | None = 4,
                ticked: bool | None = True, tag: str | None = "LT-001") -> list[dict]:
    f = form["fields"]
    out = [{"fieldId": f[1]["id"], "value": f[1]["options"][choice]["id"]},
           {"fieldId": f[2]["id"], "value": [f[2]["options"][i]["id"] for i in picks]}]
    if tag is not None:
        out.append({"fieldId": f[0]["id"], "value": tag})
    if rating is not None:
        out.append({"fieldId": f[3]["id"], "value": rating})
    if ticked is not None:
        out.append({"fieldId": f[4]["id"], "value": ticked})
    return out
