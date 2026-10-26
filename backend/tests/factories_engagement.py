"""Engagement test helpers: signed-in staff, posts with uploaded photos, surveys.

Until the default Employee role holds the engagement codes staff need (see comparison/13-engagement.md),
`person` gives each test user, as personal grants with own scope, what the Employee role is meant to get:
engagement.feed.* (read, post, react, comment, edit and delete their own) and
engagement.survey_responses.respond.
"""
from app.core.db import Db
from tests import factories

STAFF_CODES = ("engagement.feed.view", "engagement.feed.create", "engagement.feed.edit", "engagement.feed.delete",
               "engagement.survey_responses.respond")
API = "/api/engagement"


def scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


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
           first_name: str = "Staff", role_codes: str = "employee", granted: bool = True) -> dict:
    """An employee with a sign-in: {"employee_id", "user_id", "headers", ...}."""
    employee_id = factories.employee(db, company, branch_id=branch_id, department_id=department_id,
                                     first_name=first_name)
    user = factories.login_as(db, client, company, role_codes=role_codes, employee_id=employee_id)
    if granted:
        grant(db, user["user_id"])
    return {**user, "employee_id": employee_id}


def photo(client, headers: dict, name: str = "photo.png") -> dict:
    return factories.upload(client, headers, name=name, content=factories.PNG_BYTES, module="engagement")


def post(client, headers: dict, body: str | None = "Hello team", **extra) -> dict:
    r = client.post(f"{API}/posts", json={"body": body, **extra}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def notifications(db: Db, employee_id: int, entity_type: str, entity_id) -> int:
    """How many inbox notifications an employee has about a record."""
    return scalar(db, "SELECT COUNT(*) FROM core.notification n JOIN auth.user_account u ON u.id = n.user_account_id "
                      "WHERE u.employee_id = ? AND n.entity_type = ? AND n.entity_id = ?",
                  employee_id, entity_type, int(entity_id))


def events(db: Db, event_type: str, entity_id) -> int:
    return scalar(db, "SELECT COUNT(*) FROM core.outbox_event WHERE event_type = ? AND entity_id = ?",
                  event_type, int(entity_id))


def survey_body(**extra) -> dict:
    return {"title": f"Employee Satisfaction Survey {factories.tag()}", "closesOn": "2099-12-31",
            "questions": [
                {"questionType": "single", "questionText": "How happy are you at work?", "isRequired": True,
                 "options": ["Happy", "Neutral", "Unhappy"]},
                {"questionType": "multiple", "questionText": "Which perks do you use?", "options": ["Gym", "Lunch", "Transport"]},
                {"questionType": "rating", "questionText": "Rate your manager", "isRequired": True, "scaleMin": 1,
                 "scaleMax": 5, "scaleMinLabel": "Poor", "scaleMaxLabel": "Great"},
                {"questionType": "paragraph", "questionText": "Anything else?"},
            ], **extra}


def survey(client, headers: dict, publish: bool = True, **extra) -> dict:
    r = client.post(f"{API}/surveys", json=survey_body(**extra), headers=headers)
    assert r.status_code == 201, r.text
    s = r.json()["data"]
    if publish:
        r = client.patch(f"{API}/surveys/{s['id']}/publish", json={"rowVersion": s["rowVersion"]}, headers=headers)
        assert r.status_code == 200, r.text
        s = r.json()["data"]
    return s


def answers_for(s: dict, choice: int = 0, perks: tuple[int, ...] = (0, 1), rating: int = 4,
                text: str | None = "Keep it up") -> list[dict]:
    q = s["questions"]
    out = [{"questionId": q[0]["id"], "optionIds": [q[0]["options"][choice]["id"]]},
           {"questionId": q[1]["id"], "optionIds": [q[1]["options"][i]["id"] for i in perks]},
           {"questionId": q[2]["id"], "rating": rating}]
    if text is not None:
        out.append({"questionId": q[3]["id"], "text": text})
    return out
