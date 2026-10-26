"""Engagement surveys: the builder, publishing to an audience, the "Survey Available" list, answering
once, skipping, results per question, named answers, anonymous surveys, export, close, permissions."""
import pytest

from tests import factories
from tests import factories_engagement as fe

API = fe.API


@pytest.fixture(scope="module")
def world(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    ops = factories.department(db, company, name=f"Operations {factories.tag()}")
    ops_team = factories.department(db, company, name=f"Ops Team {factories.tag()}", parent_id=ops)
    finance = factories.department(db, company, name=f"Finance {factories.tag()}")
    people = {
        "amna": fe.person(db, client, company, ops, first_name="Amna"),
        "babar": fe.person(db, client, company, ops_team, first_name="Babar"),
        "chand": fe.person(db, client, company, ops, first_name="Chand"),
        "dua": fe.person(db, client, company, finance, first_name="Dua"),
    }
    return {"company": company, "admin": admin, "ops": ops, "finance": finance, **people}


def _pending(client, person) -> list[str]:
    r = client.get(f"{API}/my-surveys", params={"filter": "pending", "pageSize": 100}, headers=person["headers"])
    assert r.status_code == 200, r.text
    return [s["id"] for s in r.json()["data"]]


def test_builder(client, world):
    h = world["admin"]["headers"]
    one_option = fe.survey_body(questions=[{"questionType": "single", "questionText": "Pick", "options": ["Only"]}])
    r = client.post(f"{API}/surveys", json=one_option, headers=h)
    assert r.status_code == 422 and "questions[0].options" in r.json()["fieldErrors"]
    bad_scale = fe.survey_body(questions=[{"questionType": "rating", "questionText": "Rate", "scaleMin": 1, "scaleMax": 20}])
    assert client.post(f"{API}/surveys", json=bad_scale, headers=h).status_code == 422
    nobody = fe.survey_body(audience=[{"unitType": "department", "unitId": "999999999"}])
    assert client.post(f"{API}/surveys", json=nobody, headers=h).status_code == 422

    draft = client.post(f"{API}/surveys", json=fe.survey_body(questions=[]), headers=h).json()["data"]
    assert draft["status"] == "draft" and draft["questions"] == [] and draft["audienceCount"] >= 4
    empty = client.patch(f"{API}/surveys/{draft['id']}/publish", json={"rowVersion": draft["rowVersion"]}, headers=h)
    assert empty.status_code == 422 and "questions" in empty.json()["fieldErrors"]

    edited = client.put(f"{API}/surveys/{draft['id']}", json=fe.survey_body(title="Pulse", rowVersion=draft["rowVersion"]),
                        headers=h)
    assert edited.status_code == 200, edited.text
    s = edited.json()["data"]
    assert [q["questionType"] for q in s["questions"]] == ["single", "multiple", "rating", "paragraph"]
    assert [o["optionText"] for o in s["questions"][0]["options"]] == ["Happy", "Neutral", "Unhappy"]
    assert s["questions"][2]["scaleMaxLabel"] == "Great" and s["questions"][3]["options"] == []
    stale = client.put(f"{API}/surveys/{draft['id']}", json=fe.survey_body(rowVersion=draft["rowVersion"]), headers=h)
    assert stale.status_code == 409
    assert client.delete(f"{API}/surveys/{draft['id']}", params={"rowVersion": s["rowVersion"]}, headers=h).status_code == 204
    assert client.get(f"{API}/surveys/{draft['id']}", headers=h).status_code == 404


def test_publish_respond_results(db, client, world):
    h = world["admin"]["headers"]
    amna, babar, chand, dua = world["amna"], world["babar"], world["chand"], world["dua"]
    s = fe.survey(client, h, audience=[{"unitType": "department", "unitId": str(world["ops"])}])
    assert s["status"] == "published" and s["isOpen"] is True and s["audienceCount"] == 3
    assert s["audience"][0]["name"].startswith("Operations")
    assert fe.events(db, "engagement.survey_published", s["id"]) == 1
    for p in (amna, babar, chand):
        assert fe.notifications(db, p["employee_id"], "eng.survey", s["id"]) == 1
    assert fe.notifications(db, dua["employee_id"], "eng.survey", s["id"]) == 0

    # The popup: pending surveys for people in the audience only.
    assert s["id"] in _pending(client, babar)                         # sub-department
    assert s["id"] not in _pending(client, dua)
    assert client.get(f"{API}/my-surveys/{s['id']}", headers=dua["headers"]).status_code == 404
    assert client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)},
                       headers=dua["headers"]).status_code == 403

    mine = client.get(f"{API}/my-surveys/{s['id']}", headers=amna["headers"]).json()["data"]
    assert mine["myStatus"] == "pending" and len(mine["questions"]) == 4

    # Validation: required questions, one option for a single choice, the scale, foreign options.
    missing = client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)[1:]},
                          headers=amna["headers"])
    assert missing.status_code == 422 and f"answers[{s['questions'][0]['id']}]" in missing.json()["fieldErrors"]
    two = fe.answers_for(s)
    two[0]["optionIds"] = [o["id"] for o in s["questions"][0]["options"][:2]]
    assert client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": two},
                       headers=amna["headers"]).status_code == 422
    assert client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s, rating=9)},
                       headers=amna["headers"]).status_code == 422
    foreign = fe.answers_for(s)
    foreign[0]["optionIds"] = [s["questions"][1]["options"][0]["id"]]
    assert client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": foreign},
                       headers=amna["headers"]).status_code == 422

    # One response per person.
    done = client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)}, headers=amna["headers"])
    assert done.status_code == 201, done.text
    assert done.json()["data"]["myStatus"] == "answered" and done.json()["data"]["respondedAt"]
    again = client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)},
                        headers=amna["headers"])
    assert again.status_code == 409 and again.json()["code"] == "SURVEY_ALREADY_ANSWERED"
    assert s["id"] not in _pending(client, amna)
    assert fe.events(db, "engagement.survey_response_submitted", s["id"]) == 1

    # Skip, then answer after all.
    skipped = client.post(f"{API}/my-surveys/{s['id']}/skip", headers=babar["headers"])
    assert skipped.status_code == 200 and skipped.json()["data"]["myStatus"] == "skipped"
    assert s["id"] not in _pending(client, babar)
    later = client.post(f"{API}/my-surveys/{s['id']}/response",
                        json={"answers": fe.answers_for(s, choice=1, perks=(1,), rating=2, text=None)},
                        headers=babar["headers"])
    assert later.status_code == 201
    client.post(f"{API}/my-surveys/{s['id']}/skip", headers=chand["headers"])

    results = client.get(f"{API}/surveys/{s['id']}/results", headers=h).json()["data"]
    assert (results["audienceCount"], results["responseCount"], results["skippedCount"]) == (3, 2, 1)
    assert results["responseRate"] == "66.67"
    q1, q2, q3, q4 = results["questions"]
    assert [(o["optionText"], o["count"]) for o in q1["options"]] == [("Happy", 1), ("Neutral", 1), ("Unhappy", 0)]
    assert q1["options"][0]["percent"] == "50.00"
    assert [(o["optionText"], o["count"]) for o in q2["options"]] == [("Gym", 1), ("Lunch", 2), ("Transport", 0)]
    assert q3["averageRating"] == "3.00" and q3["ratings"] == [{"value": 2, "count": 1}, {"value": 4, "count": 1}]
    assert q4["textAnswers"] == ["Keep it up"] and q4["answerCount"] == 1

    # Named survey: HR reads each person's answers.
    responses = client.get(f"{API}/surveys/{s['id']}/responses", headers=h).json()
    assert responses["meta"]["total"] == 2
    assert {r["employeeName"].split()[0] for r in responses["data"]} == {"Amna", "Babar"}
    csv = client.get(f"{API}/surveys/{s['id']}/export", headers=h)
    assert csv.status_code == 200 and "text/csv" in csv.headers["content-type"]
    assert "Employee" in csv.text and "Amna" in csv.text and "Gym; Lunch" in csv.text

    # Published surveys keep their questions; their closing date moves.
    current = client.get(f"{API}/surveys/{s['id']}", headers=h).json()["data"]
    locked = client.put(f"{API}/surveys/{s['id']}", json=fe.survey_body(rowVersion=current["rowVersion"]), headers=h)
    assert locked.status_code == 409 and locked.json()["code"] == "SURVEY_NOT_DRAFT"
    assert client.delete(f"{API}/surveys/{s['id']}", params={"rowVersion": current["rowVersion"]},
                         headers=h).json()["code"] == "SURVEY_HAS_RESPONSES"
    moved = client.patch(f"{API}/surveys/{s['id']}/closing-date",
                         json={"closesOn": "2098-01-31", "rowVersion": current["rowVersion"]}, headers=h)
    assert moved.status_code == 200 and moved.json()["data"]["closesOn"] == "2098-01-31"
    stale = client.patch(f"{API}/surveys/{s['id']}/close", json={"rowVersion": current["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    closed = client.patch(f"{API}/surveys/{s['id']}/close", json={"rowVersion": moved.json()["data"]["rowVersion"]},
                          headers=h)
    assert closed.status_code == 200 and closed.json()["data"]["status"] == "closed"
    assert fe.events(db, "engagement.survey_closed", s["id"]) == 1
    late = client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)},
                       headers=chand["headers"])
    assert late.status_code == 409 and late.json()["code"] == "SURVEY_CLOSED"
    history = client.get(f"{API}/my-surveys", params={"filter": "all"}, headers=chand["headers"]).json()["data"]
    assert next(x for x in history if x["id"] == s["id"])["myStatus"] == "missed"


def test_closing_date_passed(db, client, world):
    h = world["admin"]["headers"]
    s = fe.survey(client, h)
    fe.execute(db, "UPDATE eng.survey SET closes_on = DATEADD(DAY, -1, CAST(SYSUTCDATETIME() AS DATE)) WHERE id = ?",
               int(s["id"]))
    got = client.get(f"{API}/surveys/{s['id']}", headers=h).json()["data"]
    assert got["status"] == "closed" and got["isOpen"] is False
    assert s["id"] not in _pending(client, world["dua"])
    r = client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)},
                    headers=world["dua"]["headers"])
    assert r.status_code == 409
    assert client.get(f"{API}/surveys", params={"status": "closed", "q": s["title"]},
                      headers=h).json()["meta"]["total"] == 1


def test_anonymous_survey(db, client, world):
    h = world["admin"]["headers"]
    s = fe.survey(client, h, isAnonymous=True, audience=[{"unitType": "employee", "unitId": str(world["dua"]["employee_id"])},
                                                         {"unitType": "department", "unitId": str(world["finance"])}])
    assert s["isAnonymous"] is True and s["audienceCount"] == 1
    dua = world["dua"]
    assert client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s, text="Honest view")},
                       headers=dua["headers"]).status_code == 201
    again = client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)},
                        headers=dua["headers"])
    assert again.status_code == 409
    # The answers carry nobody's identity; participation is kept apart.
    row = fe.scalar(db, "SELECT CONCAT(ISNULL(CAST(employee_id AS NVARCHAR(30)), N'-'), N'|', "
                        "ISNULL(CAST(created_by AS NVARCHAR(30)), N'-'), N'|', CONVERT(NVARCHAR(8), submitted_at, 108)) "
                        "FROM eng.survey_response WHERE survey_id = ?", int(s["id"]))
    assert row == "-|-|00:00:00"
    assert fe.scalar(db, "SELECT COUNT(*) FROM eng.survey_answer WHERE created_by IS NOT NULL AND survey_response_id IN "
                         "(SELECT id FROM eng.survey_response WHERE survey_id = ?)", int(s["id"])) == 0
    assert fe.scalar(db, "SELECT COUNT(*) FROM eng.survey_participant WHERE survey_id = ? AND responded_at IS NOT NULL",
                     int(s["id"])) == 1
    payload = fe.scalar(db, "SELECT payload FROM core.outbox_event WHERE event_type = N'engagement.survey_response_submitted' "
                            "AND entity_id = ?", int(s["id"]))
    assert "employeeId" not in payload

    refused = client.get(f"{API}/surveys/{s['id']}/responses", headers=h)
    assert refused.status_code == 403 and refused.json()["code"] == "SURVEY_ANONYMOUS"
    results = client.get(f"{API}/surveys/{s['id']}/results", headers=h).json()["data"]
    assert results["responseCount"] == 1 and results["questions"][3]["textAnswers"] == ["Honest view"]
    csv = client.get(f"{API}/surveys/{s['id']}/export", headers=h).text
    assert "Honest view" in csv and "Employee" not in csv and "Dua" not in csv


def test_permissions(db, client, world):
    staff = world["amna"]
    assert client.post(f"{API}/surveys", json=fe.survey_body(), headers=staff["headers"]).status_code == 403
    assert client.get(f"{API}/surveys", headers=staff["headers"]).status_code == 403
    s = fe.survey(client, world["admin"]["headers"])
    assert client.get(f"{API}/surveys/{s['id']}/results", headers=staff["headers"]).status_code == 403
    assert client.get(f"{API}/surveys/{s['id']}/responses", headers=staff["headers"]).status_code == 403
    # A role with no engagement codes (the Employee role answers surveys).
    nobody = fe.person(db, client, world["company"], world["ops"], role_codes="recruiter", granted=False)
    assert client.get(f"{API}/my-surveys", headers=nobody["headers"]).status_code == 403
    # A department head reads named answers of their own department only.
    head = fe.person(db, client, world["company"], world["finance"], role_codes="department_head")
    fe.grant(db, head["user_id"], ("engagement.survey_responses.view", "engagement.surveys.view"), scope="department")
    client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)}, headers=staff["headers"])
    client.post(f"{API}/my-surveys/{s['id']}/response", json={"answers": fe.answers_for(s)},
                headers=world["dua"]["headers"])
    seen = client.get(f"{API}/surveys/{s['id']}/responses", headers=head["headers"]).json()
    assert [r["employeeName"].split()[0] for r in seen["data"]] == ["Dua"]
