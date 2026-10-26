"""Test helpers for Performance and Training. Until the default roles hold these modules' codes (see
comparison/11-performance-training.md), people get them as personal grants with the scope a role would give:
staff 'own', line managers 'team'. Records other modules own (salaries in hr.*) are written with plain SQL."""
from datetime import date
from typing import Any

from tests import factories
from tests import factories_leaves as fl

STAFF_PERFORMANCE = ["performance.overview.view", "performance.goals.view", "performance.goals.create",
                     "performance.goals.edit", "performance.reviews.view", "performance.reviews.submit",
                     "performance.kpis.view"]
MANAGER_PERFORMANCE = STAFF_PERFORMANCE + ["performance.goals.delete", "performance.reviews.evaluate",
                                           "performance.appraisals.view"]
STAFF_TRAINING = ["training.programs.view", "training.sessions.view", "training.enrolments.view",
                  "training.enrolments.create", "training.enrolments.cancel", "training.feedback.create",
                  "training.attendance.view"]
MANAGER_TRAINING = STAFF_TRAINING + ["training.enrolments.approve", "training.enrolments.reject",
                                     "training.feedback.view"]

execute, scalar, rows = fl.execute, fl.scalar, fl.rows


def grant(db, user_id: int, codes: list[str], scope: str) -> None:
    for code in codes:
        execute(db, "INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope, reason) "
                    "SELECT u.company_id, u.id, p.id, N'grant', ?, N'test' FROM auth.permission p "
                    "JOIN auth.user_account u ON u.id = ? WHERE p.code = ? AND NOT EXISTS ("
                    "SELECT 1 FROM auth.user_permission_override o WHERE o.user_account_id = u.id "
                    "AND o.company_id = u.company_id AND o.permission_id = p.id)", scope, user_id, code)


def person(db, client, company: int, codes: list[str] | None = None, scope: str = "own", first_name: str = "Staff",
           line_manager_id: int | None = None, department_id: int | None = None,
           role_codes: str = "employee") -> dict[str, Any]:
    """An employee with a sign-in and the given codes: {"employee_id", "user_id", "headers", ...}."""
    employee_id = factories.employee(db, company, first_name=first_name, line_manager_id=line_manager_id,
                                     department_id=department_id)
    user = factories.login_as(db, client, company, role_codes=role_codes, employee_id=employee_id)
    if codes:
        grant(db, user["user_id"], codes, scope)
    return {**user, "employee_id": employee_id}


def events(db, company: int, event_type: str) -> list[dict[str, Any]]:
    return rows(db, "SELECT entity_type, entity_id, payload FROM core.outbox_event WHERE company_id = ? AND event_type = ? "
                    "ORDER BY id", company, event_type)


def notifications(db, user_id: int) -> list[dict[str, Any]]:
    return rows(db, "SELECT title, body, link, entity_type, entity_id FROM core.notification WHERE user_account_id = ? "
                    "ORDER BY id", user_id)


def salary(db, employee_id: int, amount: float, effective: date) -> int:
    return fl.insert(db, "hr.employee_salary", {"employee_id": employee_id, "effective_date": effective, "amount": amount,
                                                "change_type": "flat", "change_value": amount, "source": "joining"})


def ok(r, code: int = 200) -> dict[str, Any]:
    assert r.status_code == code, r.text
    return r.json()["data"]


# --- Performance set-up --------------------------------------------------------------------------

LEVELS = [{"score": 1, "label": "Unsatisfactory"}, {"score": 2, "label": "Needs improvement"},
          {"score": 3, "label": "Meets expectations"}, {"score": 4, "label": "Exceeds expectations"},
          {"score": 5, "label": "Outstanding"}]


def scale(client, headers: dict, **extra) -> dict:
    return ok(client.post("/api/performance/rating-scales", headers=headers,
                          json={"name": f"Five point {factories.tag()}", "levels": LEVELS, **extra}), 201)


def form(client, headers: dict, scale_id: str, goals_weight: float = 20,
         criteria: list[tuple[str, float]] = (("Quality of work", 50), ("Teamwork", 30)), **extra) -> dict:
    return ok(client.post("/api/performance/forms", headers=headers, json={
        "name": f"Annual form {factories.tag()}", "ratingScaleId": scale_id, "goalsWeight": goals_weight,
        "criteria": [{"name": n, "weight": w} for n, w in criteria], **extra}), 201)


def cycle(client, headers: dict, form_id: str, start: date, end: date, **extra) -> dict:
    return ok(client.post("/api/performance/cycles", headers=headers, json={
        "name": f"Annual {factories.tag()}", "appraisalFormId": form_id, "startDate": start.isoformat(),
        "endDate": end.isoformat(), **extra}), 201)


def goal(client, headers: dict, due: date, **extra) -> dict:
    return ok(client.post("/api/performance/goals", headers=headers,
                          json={"title": f"Goal {factories.tag()}", "dueDate": due.isoformat(), **extra}), 201)


# --- Training set-up -----------------------------------------------------------------------------

def program(client, headers: dict, **extra) -> dict:
    return ok(client.post("/api/training/programs", headers=headers, json={
        "title": f"Program {factories.tag()}", "deliveryMode": "classroom", "providerType": "internal", **extra}), 201)


def session(client, headers: dict, program_id: str, start: date, end: date, **extra) -> dict:
    return ok(client.post("/api/training/sessions", headers=headers, json={
        "trainingProgramId": program_id, "startDate": start.isoformat(), "endDate": end.isoformat(),
        "deliveryMode": "classroom", "venue": "Training room 1", "trainerType": "external",
        "trainerName": "Ayesha Siddiqui", **extra}), 201)
