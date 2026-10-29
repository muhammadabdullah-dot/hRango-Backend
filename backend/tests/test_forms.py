"""Custom Form: the builder (sections, fields, options, audience), publish / close / duplicate / delete,
filling (assigned forms, answering, one response per person, My submissions), responses (list, summary,
one response), anonymous forms, the editing limits once there are answers, closing dates, permissions."""
import pytest

from tests import factories
from tests import factories_forms as ff

API = ff.API


@pytest.fixture(scope="module")
def world(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    ops = factories.department(db, company, name=f"Operations {factories.tag()}")
    ops_team = factories.department(db, company, name=f"Ops Team {factories.tag()}", parent_id=ops)
    finance = factories.department(db, company, name=f"Finance {factories.tag()}")
    people = {
        "amna": ff.person(db, client, company, ops, first_name="Amna"),
        "babar": ff.person(db, client, company, ops_team, first_name="Babar"),
        "dua": ff.person(db, client, company, finance, first_name="Dua"),
    }
    return {"company": company, "admin": admin, "ops": ops, "finance": finance, **people}


def _assigned(client, person) -> list[str]:
    r = client.get(f"{API}/assigned", params={"pageSize": 100}, headers=person["headers"])
    assert r.status_code == 200, r.text
    return [f["id"] for f in r.json()["data"]]


def _submit(client, person, form, answers):
    return client.post(f"{API}/{form['id']}/responses", json={"answers": answers}, headers=person["headers"])


# --------------------------------------------------------------------------- CF1

def test_builder(client, world):
    h = world["admin"]["headers"]
    r = client.post(API, json=ff.form_body(title="  "), headers=h)
    assert r.status_code == 422 and "title" in r.json()["fieldErrors"]
    body = ff.form_body()
    body["fields"][1]["options"] = []
    r = client.post(API, json=body, headers=h)
    assert r.status_code == 422 and "fields.1.options" in r.json()["fieldErrors"]
    body = ff.form_body()
    body["fields"][3]["max"] = 20
    assert "fields.3.max" in client.post(API, json=body, headers=h).json()["fieldErrors"]
    body = ff.form_body()
    body["sections"][0]["title"] = ""
    assert "sections.0.title" in client.post(API, json=body, headers=h).json()["fieldErrors"]
    r = client.post(API, json=ff.form_body(audience={"kind": "departments", "ids": []}), headers=h)
    assert r.status_code == 422 and "audience.ids" in r.json()["fieldErrors"]
    r = client.post(API, json=ff.form_body(closesOn="2001-01-01"), headers=h)
    assert r.status_code == 422 and "closesOn" in r.json()["fieldErrors"]
    body = ff.form_body()
    body["fields"][0]["type"] = "signature"
    r = client.post(API, json=body, headers=h)
    assert r.status_code == 422 and "fields.0.type" in r.json()["fieldErrors"]

    r = client.post(API, json=ff.form_body(audience={"kind": "departments", "ids": [world["ops"]]}), headers=h)
    assert r.status_code == 201, r.text
    f = r.json()["data"]
    assert f["status"] == "draft" and f["fieldCount"] == 5 and f["responseCount"] == 0 and f["publishedAt"] is None
    assert f["audience"]["kind"] == "departments" and f["audience"]["targets"][0]["id"] == str(world["ops"])
    assert f["audience"]["targets"][0]["name"].startswith("Operations")
    assert f["createdBy"]["id"] == str(world["admin"]["user_id"]) and f["oneResponsePerPerson"] is True
    assert [s["position"] for s in f["sections"]] == [0]
    assert [(x["sectionId"], x["position"]) for x in f["fields"]] == [(None, 0)] + [(f["sections"][0]["id"], i)
                                                                                    for i in range(4)]
    assert f["fields"][0]["max"] == 20 and f["fields"][3]["max"] == 5 and f["fields"][0]["options"] == []
    assert [o["label"] for o in f["fields"][1]["options"]] == ["Great", "Fine", "Hard"]

    # Edit: keep ids, reword, reorder options, add a section and a field, remove a field.
    kept = f["fields"][1]
    body = ff.as_input(f, title="Week one")
    body["sections"].append({"key": "new", "id": None, "title": "Extra", "description": "More"})
    body["fields"][1]["options"].reverse()
    body["fields"][1]["options"][0]["label"] = "Rough"
    body["fields"].pop(4)
    body["fields"].append({"id": None, "sectionKey": "new", "type": "date", "label": "Start date", "helpText": None,
                           "required": False, "options": [], "min": None, "max": None})
    r = client.put(f"{API}/{f['id']}", json=body, headers=h)
    assert r.status_code == 200, r.text
    e = r.json()["data"]
    assert e["title"] == "Week one" and len(e["sections"]) == 2 and e["fieldCount"] == 5
    assert e["fields"][1]["id"] == kept["id"]
    assert [o["id"] for o in e["fields"][1]["options"]] == [o["id"] for o in reversed(kept["options"])]
    assert e["fields"][1]["options"][0]["label"] == "Rough"
    assert e["fields"][4]["sectionId"] == e["sections"][1]["id"] and e["fields"][4]["position"] == 0
    stale = client.put(f"{API}/{f['id']}", json=ff.as_input(f), headers=h)
    assert stale.status_code == 409 and stale.json()["code"] == "STALE_ROW_VERSION"

    found = client.get(API, params={"q": "Week one", "status": "draft"}, headers=h).json()
    assert [x["id"] for x in found["data"]] == [f["id"]] and found["meta"]["total"] == 1
    assert found["data"][0]["audience"]["targets"][0]["id"] == str(world["ops"])
    assert client.get(API, params={"q": "Week one", "status": "published"}, headers=h).json()["meta"]["total"] == 0

    assert client.delete(f"{API}/{f['id']}", params={"rowVersion": f["rowVersion"]}, headers=h).status_code == 409
    assert client.delete(f"{API}/{f['id']}", params={"rowVersion": e["rowVersion"]}, headers=h).status_code == 204
    assert client.get(f"{API}/{f['id']}", headers=h).status_code == 404


def test_publish_close_duplicate(client, world):
    h = world["admin"]["headers"]
    empty = client.post(API, json=ff.form_body(fields=[], sections=[]), headers=h).json()["data"]
    r = client.post(f"{API}/{empty['id']}/publish", json={"rowVersion": empty["rowVersion"]}, headers=h)
    assert r.status_code == 422 and "fields" in r.json()["fieldErrors"]

    f = ff.create(client, h)
    assert f["status"] == "published" and f["publishedAt"]
    again = client.post(f"{API}/{f['id']}/publish", json={"rowVersion": f["rowVersion"]}, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "FORM_PUBLISHED"
    closed = client.post(f"{API}/{f['id']}/close", json={"rowVersion": f["rowVersion"]}, headers=h)
    assert closed.status_code == 200 and closed.json()["data"]["status"] == "closed"
    c = closed.json()["data"]
    assert c["closedAt"]
    again = client.post(f"{API}/{f['id']}/close", json={"rowVersion": c["rowVersion"]}, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "FORM_NOT_PUBLISHED"
    reopened = client.post(f"{API}/{f['id']}/publish", json={"rowVersion": c["rowVersion"]}, headers=h)
    assert reopened.status_code == 200 and reopened.json()["data"]["status"] == "published"
    assert reopened.json()["data"]["closedAt"] is None

    r = client.post(f"{API}/{f['id']}/duplicate", json={}, headers=h)
    assert r.status_code == 201, r.text
    d = r.json()["data"]
    assert d["title"] == f"Copy of {f['title']}" and d["status"] == "draft" and d["responseCount"] == 0
    assert d["fieldCount"] == 5 and len(d["sections"]) == 1
    assert not {x["id"] for x in d["fields"]} & {x["id"] for x in f["fields"]}
    assert d["fields"][1]["sectionId"] == d["sections"][0]["id"]
    assert [o["label"] for o in d["fields"][1]["options"]] == ["Great", "Fine", "Hard"]


# --------------------------------------------------------------------------- CF2 + CF3

def test_fill_and_responses(client, world):
    h = world["admin"]["headers"]
    amna, babar, dua = world["amna"], world["babar"], world["dua"]
    draft = ff.create(client, h, publish=False, audience={"kind": "departments", "ids": [world["ops"]]})
    f = ff.create(client, h, audience={"kind": "departments", "ids": [world["ops"]]})

    assert f["id"] in _assigned(client, amna) and f["id"] in _assigned(client, babar)   # sub-department
    assert f["id"] not in _assigned(client, dua) and draft["id"] not in _assigned(client, amna)
    assert client.get(f"{API}/assigned/{f['id']}", headers=dua["headers"]).status_code == 404
    assert _submit(client, dua, f, ff.answers_for(f)).status_code == 404
    nope = _submit(client, amna, draft, ff.answers_for(draft))
    assert nope.status_code == 409 and nope.json()["code"] == "FORM_NOT_PUBLISHED"

    mine = client.get(f"{API}/assigned/{f['id']}", headers=amna["headers"]).json()["data"]
    assert mine["canRespond"] is True and mine["myResponseCount"] == 0 and len(mine["fields"]) == 5
    assert mine["lastResponseId"] is None and len(mine["sections"]) == 1

    # Validation: required, a foreign option, the scale, a text too long, a bad type.
    fid = [x["id"] for x in f["fields"]]
    missing = _submit(client, amna, f, ff.answers_for(f, tag=None))
    assert missing.status_code == 422 and f"answers.{fid[0]}" in missing.json()["fieldErrors"]
    foreign = ff.answers_for(f)
    foreign[0]["value"] = f["fields"][2]["options"][0]["id"]
    assert f"answers.{fid[1]}" in _submit(client, amna, f, foreign).json()["fieldErrors"]
    assert f"answers.{fid[3]}" in _submit(client, amna, f, ff.answers_for(f, rating=9)).json()["fieldErrors"]
    assert f"answers.{fid[0]}" in _submit(client, amna, f, ff.answers_for(f, tag="x" * 21)).json()["fieldErrors"]
    wrong = ff.answers_for(f)
    wrong[1]["value"] = "Laptop"
    assert f"answers.{fid[2]}" in _submit(client, amna, f, wrong).json()["fieldErrors"]

    done = _submit(client, amna, f, ff.answers_for(f))
    assert done.status_code == 201, done.text
    resp = done.json()["data"]
    assert resp["formId"] == f["id"] and resp["respondent"]["name"].startswith("Amna")
    values = {a["fieldId"]: a["value"] for a in resp["answers"]}
    assert values[fid[0]] == "LT-001" and values[fid[1]] == f["fields"][1]["options"][0]["id"]
    assert values[fid[2]] == [o["id"] for o in f["fields"][2]["options"][:2]]
    assert values[fid[3]] == 4 and values[fid[4]] is True
    again = _submit(client, amna, f, ff.answers_for(f))
    assert again.status_code == 409 and again.json()["code"] == "ALREADY_RESPONDED"
    after = client.get(f"{API}/assigned/{f['id']}", headers=amna["headers"]).json()["data"]
    assert after["canRespond"] is False and after["myResponseCount"] == 1 and after["lastResponseId"] == resp["id"]
    assert _submit(client, babar, f, ff.answers_for(f, choice=1, picks=(2,), rating=2, ticked=False)).status_code == 201

    my = client.get(f"{API}/my-responses", headers=amna["headers"]).json()
    assert my["data"][0]["id"] == resp["id"] and my["data"][0]["formTitle"] == f["title"]
    assert my["data"][0]["anonymous"] is False

    # HR: the answers, a search by respondent, the counts, one response.
    page = client.get(f"{API}/{f['id']}/responses", headers=h).json()
    assert page["meta"]["total"] == 2 and page["data"][0]["respondent"]["name"].startswith("Babar")
    assert client.get(f"{API}/{f['id']}/responses", params={"q": "Amna"}, headers=h).json()["meta"]["total"] == 1
    summary = client.get(f"{API}/{f['id']}/responses/summary", headers=h).json()["data"]
    assert summary["total"] == 2
    by_field = {x["fieldId"]: x for x in summary["fields"]}
    assert [c["count"] for c in by_field[fid[1]]["counts"]] == [1, 1, 0]
    assert [c["count"] for c in by_field[fid[2]]["counts"]] == [1, 1, 1]
    assert by_field[fid[3]]["counts"] == [{"value": str(v), "count": int(v in (2, 4))} for v in range(1, 6)]
    assert by_field[fid[4]]["counts"] == [{"value": "true", "count": 1}, {"value": "false", "count": 1}]
    assert by_field[fid[0]]["answered"] == 2 and by_field[fid[0]]["counts"] == []

    detail = client.get(f"{API}/responses/{resp['id']}", headers=h)
    assert detail.status_code == 200 and detail.json()["data"]["form"]["id"] == f["id"]
    assert len(detail.json()["data"]["form"]["fields"]) == 5
    assert client.get(f"{API}/responses/{resp['id']}", headers=amna["headers"]).status_code == 200
    assert client.get(f"{API}/responses/{resp['id']}", headers=babar["headers"]).status_code == 404

    # Closing stops answers; the published form still shows as closed to its audience.
    closed = client.post(f"{API}/{f['id']}/close", json={"rowVersion": f["rowVersion"]}, headers=h).json()["data"]
    assert closed["responseCount"] == 2
    late = _submit(client, babar, f, ff.answers_for(f))
    assert late.status_code == 409 and late.json()["code"] == "FORM_CLOSED"
    assert f["id"] in _assigned(client, babar)


def test_anonymous_and_editing_limits(db, client, world):
    h = world["admin"]["headers"]
    f = ff.create(client, h, anonymous=True, oneResponsePerPerson=False)
    for _ in range(2):
        assert _submit(client, world["dua"], f, ff.answers_for(f)).status_code == 201
    rows = client.get(f"{API}/{f['id']}/responses", params={"q": "Dua"}, headers=h).json()
    assert rows["meta"]["total"] == 2 and all(r["respondent"] is None for r in rows["data"])
    detail = client.get(f"{API}/responses/{rows['data'][0]['id']}", headers=h).json()["data"]
    assert detail["respondent"] is None and detail["form"]["anonymous"] is True
    my = client.get(f"{API}/my-responses", headers=world["dua"]["headers"]).json()
    assert {r["formId"] for r in my["data"]} >= {f["id"]} and my["data"][0]["anonymous"] is True

    current = client.get(f"{API}/{f['id']}", headers=h).json()["data"]
    assert current["responseCount"] == 2
    gone = ff.as_input(current)
    gone["fields"].pop(1)
    r = client.put(f"{API}/{f['id']}", json=gone, headers=h)
    assert r.status_code == 409 and r.json()["code"] == "FORM_HAS_RESPONSES"
    retyped = ff.as_input(current)
    retyped["fields"][1]["type"] = "dropdown"
    assert "fields.1.type" in client.put(f"{API}/{f['id']}", json=retyped, headers=h).json()["fieldErrors"]
    fewer = ff.as_input(current)
    fewer["fields"][1]["options"].pop()
    assert "fields.1.options" in client.put(f"{API}/{f['id']}", json=fewer, headers=h).json()["fieldErrors"]
    named = ff.as_input(current, anonymous=False)
    assert "anonymous" in client.put(f"{API}/{f['id']}", json=named, headers=h).json()["fieldErrors"]
    reworded = ff.as_input(current)
    reworded["fields"][1]["label"] = "How was your first day?"
    reworded["fields"][1]["options"].append({"id": None, "label": "Awful"})
    r = client.put(f"{API}/{f['id']}", json=reworded, headers=h)
    assert r.status_code == 200, r.text
    current = r.json()["data"]
    assert current["fields"][1]["label"] == "How was your first day?" and len(current["fields"][1]["options"]) == 4

    blocked = client.delete(f"{API}/{f['id']}", params={"rowVersion": current["rowVersion"]}, headers=h)
    assert blocked.status_code == 409 and blocked.json()["code"] == "FORM_HAS_RESPONSES"
    closed = client.post(f"{API}/{f['id']}/close", json={"rowVersion": current["rowVersion"]}, headers=h).json()["data"]
    assert client.delete(f"{API}/{f['id']}", params={"rowVersion": closed["rowVersion"]}, headers=h).status_code == 204


def test_closing_date_reads_closed(db, client, world):
    h = world["admin"]["headers"]
    f = ff.create(client, h)
    ff.execute(db, "UPDATE frm.form SET closes_on = DATEADD(DAY, -1, CAST(SYSUTCDATETIME() AS DATE)) WHERE id = ?",
               int(f["id"]))
    current = client.get(f"{API}/{f['id']}", headers=h).json()["data"]
    assert current["status"] == "closed" and current["closedAt"]
    assert f["id"] in [x["id"] for x in client.get(API, params={"status": "closed", "pageSize": 100},
                                                   headers=h).json()["data"]]
    late = _submit(client, world["amna"], f, ff.answers_for(f))
    assert late.status_code == 409 and late.json()["code"] == "FORM_CLOSED"
    mine = client.get(f"{API}/assigned/{f['id']}", headers=world["amna"]["headers"]).json()["data"]
    assert mine["status"] == "closed" and mine["canRespond"] is False
    r = client.post(f"{API}/{f['id']}/publish", json={"rowVersion": current["rowVersion"]}, headers=h)
    assert r.status_code == 422 and "closesOn" in r.json()["fieldErrors"]


def test_file_answer(client, world):
    h = world["admin"]["headers"]
    body = ff.form_body(sections=[], fields=[
        {"id": None, "sectionKey": None, "type": "file", "label": "Upload your CNIC copy", "helpText": None,
         "required": True, "options": [], "min": None, "max": None},
        {"id": None, "sectionKey": None, "type": "date", "label": "Joining date", "helpText": None,
         "required": False, "options": [], "min": None, "max": None},
        {"id": None, "sectionKey": None, "type": "number", "label": "Years of experience", "helpText": None,
         "required": False, "options": [], "min": 0, "max": 50}])
    r = client.post(API, json=body, headers=h)
    assert r.status_code == 201, r.text
    f = r.json()["data"]
    f = client.post(f"{API}/{f['id']}/publish", json={"rowVersion": f["rowVersion"]}, headers=h).json()["data"]
    amna = world["amna"]
    upload = factories.upload(client, amna["headers"], module="forms")
    fid = [x["id"] for x in f["fields"]]
    bad = _submit(client, amna, f, [{"fieldId": fid[0], "value": upload["id"]}, {"fieldId": fid[2], "value": 51}])
    assert bad.status_code == 422 and f"answers.{fid[2]}" in bad.json()["fieldErrors"]
    bad = _submit(client, amna, f, [{"fieldId": fid[0], "value": 999999999}])
    assert f"answers.{fid[0]}" in bad.json()["fieldErrors"]
    r = _submit(client, amna, f, [{"fieldId": fid[0], "value": upload["id"]}, {"fieldId": fid[1], "value": "2026-11-02"},
                                  {"fieldId": fid[2], "value": 3.5}])
    assert r.status_code == 201, r.text
    answers = {a["fieldId"]: a for a in r.json()["data"]["answers"]}
    assert answers[fid[0]]["value"] == upload["id"] and answers[fid[0]]["file"]["url"].startswith("/api/files/")
    assert answers[fid[1]]["value"] == "2026-11-02" and answers[fid[2]]["value"] == 3.5


def test_permissions(db, client, world):
    company = world["company"]
    # Filling forms is self-service: the Employee role holds forms.my_forms.*; a user with no role does not.
    staff = ff.person(db, client, company, world["ops"], granted=False)
    assert client.get(f"{API}/assigned", headers=staff["headers"]).status_code == 200
    no_role = factories.login_as(db, client, company, role_codes="", employee_id=staff["employee_id"])
    assert client.get(f"{API}/assigned", headers=no_role["headers"]).status_code == 403
    assert client.get(API, headers=world["amna"]["headers"]).status_code == 403
    assert client.post(API, json=ff.form_body(), headers=world["amna"]["headers"]).status_code == 403
    f = ff.create(client, world["admin"]["headers"])
    assert client.get(f"{API}/{f['id']}/responses", headers=world["amna"]["headers"]).status_code == 403
    other = factories.company(db)
    outsider = factories.login_as(db, client, other, role_codes="company_admin")
    assert client.get(f"{API}/{f['id']}", headers=outsider["headers"]).status_code == 404
