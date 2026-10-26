"""Project management collaboration: comments (threads, mentions, assign, resolve, reactions),
attachments, time tracking, reminders, sharing and workspace history."""
import pytest

from tests import factories
from tests import factories_events as fe
from tests import factories_projects as pm

API = "/api/projects"


@pytest.fixture(scope="module")
def team(db, client, company):
    dept = factories.department(db, company)
    people = {k: pm.person(db, client, company, dept, first_name=k.title())
              for k in ("owner", "manager", "lead", "contributor", "other")}
    ws = pm.workspace(client, people["owner"]["headers"], dept, people["owner"]["employee_id"], privacy="workspace",
                      members=[(people["manager"]["employee_id"], "manager"),
                               (people["lead"]["employee_id"], "team_leader"),
                               (people["contributor"]["employee_id"], "contributor"),
                               (people["other"]["employee_id"], "contributor")])
    task = pm.task(client, people["lead"]["headers"], ws["id"], name="Usability test", dueDate="2030-06-30",
                   assigneeIds=[str(people["contributor"]["employee_id"])])
    return {"dept": dept, "ws": ws, "task": task, **people}


def test_comments(db, client, company, team):
    lead, contributor, other = team["lead"], team["contributor"], team["other"]
    tid = team["task"]["id"]
    linked = pm.task(client, lead["headers"], team["ws"]["id"], name="Recruit testers")

    r = client.post(f"{API}/tasks/{tid}/comments",
                    json={"body": "@Contributor complete this ASAP", "assignedToId": str(contributor["employee_id"]),
                          "mentions": [{"employeeId": contributor["employee_id"]}, {"taskId": linked["id"]}]},
                    headers=lead["headers"])
    assert r.status_code == 201, r.text
    top = r.json()["data"]
    assert top["assignedToId"] == str(contributor["employee_id"]) and top["assignedByName"].startswith("Lead")
    assert {m.get("taskCode") for m in top["mentions"]} >= {linked["code"]}
    # The mentioned person is told; the author is not.
    mention = fe.events(db, company, "projects.comment_mention", int(top["id"]))
    assert len(mention) == 1 and mention[0]["data"]["mentioned"] == [{"employeeId": str(contributor["employee_id"])}]
    told = fe.notifications(db, company, contributor["employee_id"], "pm.task_comment", int(top["id"]))
    assert len(told) == 1 and told[0]["title"].startswith("Lead ") and told[0]["title"].endswith(team["task"]["code"])
    assert f"?task={tid}" in told[0]["link"]
    edited = client.put(f"{API}/comments/{top['id']}", json={
        "body": "@Contributor @Other complete this ASAP", "rowVersion": top["rowVersion"],
        "mentions": [{"employeeId": contributor["employee_id"]}, {"employeeId": other["employee_id"]}]},
        headers=lead["headers"])
    assert edited.status_code == 200, edited.text
    top = edited.json()["data"]
    mention = fe.events(db, company, "projects.comment_mention", int(top["id"]))
    assert len(mention) == 2 and mention[1]["data"]["mentioned"] == [{"employeeId": str(other["employee_id"])}]
    assert len(fe.notifications(db, company, contributor["employee_id"], "pm.task_comment", int(top["id"]))) == 1
    assert len(fe.notifications(db, company, other["employee_id"], "pm.task_comment", int(top["id"]))) == 1

    # Contributors comment and reply, but do not assign comments.
    reply = client.post(f"{API}/tasks/{tid}/comments", json={"body": "On it", "parentId": top["id"]},
                        headers=contributor["headers"])
    assert reply.status_code == 201
    assert client.post(f"{API}/tasks/{tid}/comments", json={"body": "You do it", "assignedToId": str(other["employee_id"])},
                       headers=contributor["headers"]).status_code == 403
    assert client.patch(f"{API}/comments/{top['id']}/assign", json={"assignedToId": str(other["employee_id"])},
                        headers=contributor["headers"]).status_code == 403

    # Only the author edits; the assignee resolves; anyone in the workspace reacts.
    edit = {"body": "Changed", "rowVersion": top["rowVersion"]}
    assert client.put(f"{API}/comments/{top['id']}", json=edit, headers=contributor["headers"]).status_code == 403
    edited = client.put(f"{API}/comments/{top['id']}", json=edit, headers=lead["headers"])
    assert edited.status_code == 200 and edited.json()["data"]["editedAt"] and edited.json()["data"]["mentions"] == []
    stale = client.put(f"{API}/comments/{top['id']}", json=edit, headers=lead["headers"])
    assert stale.status_code == 409
    resolved = client.patch(f"{API}/comments/{top['id']}/resolve", json={"resolved": True}, headers=contributor["headers"])
    assert resolved.json()["data"]["isResolved"] is True
    assert resolved.json()["data"]["resolvedByName"].startswith("Contributor")
    liked = client.put(f"{API}/comments/{top['id']}/reaction", json={"reaction": "like"}, headers=other["headers"])
    assert liked.json()["data"]["reactions"] == [{"employeeId": str(other["employee_id"]), "reaction": "like"}]

    thread = client.get(f"{API}/tasks/{tid}/comments", headers=other["headers"]).json()["data"]
    assert [c["body"] for c in thread] == ["Changed", "On it"] and thread[0]["replyCount"] == 1
    task = client.get(f"{API}/tasks/{tid}", headers=lead["headers"]).json()["data"]
    assert task["commentCount"] == 2 and task["latestComment"]["body"] == "On it"

    # Non-members of a workspace they can read do not comment.
    outsider = pm.person(db, client, company, team["dept"])
    assert client.post(f"{API}/tasks/{tid}/comments", json={"body": "Hi"},
                       headers=outsider["headers"]).status_code == 403

    # The author deletes their own; deleting a comment takes its replies too.
    rv = edited.json()["data"]["rowVersion"]
    current = next(c for c in thread if c["id"] == top["id"])
    assert client.delete(f"{API}/comments/{top['id']}", params={"rowVersion": current["rowVersion"]},
                         headers=other["headers"]).status_code == 403
    assert client.delete(f"{API}/comments/{top['id']}", params={"rowVersion": current["rowVersion"]},
                         headers=lead["headers"]).status_code == 204
    assert client.get(f"{API}/tasks/{tid}/comments", headers=lead["headers"]).json()["data"] == []
    assert rv


def test_attachments(client, db, company, team):
    contributor, other = team["contributor"], team["other"]
    tid = team["task"]["id"]
    ch = contributor["headers"]

    def attach(headers, file_id):
        return client.post(f"{API}/tasks/{tid}/attachments", json={"fileId": int(file_id)}, headers=headers)

    notes = factories.upload(client, ch, name="notes.txt", content=b"plain notes", module="projects")
    bad = attach(ch, notes["id"])
    assert bad.status_code == 422 and "fileId" in bad.json()["fieldErrors"]  # not a BRD type
    big = factories.upload(client, ch, name="big.pdf", module="projects")
    cur = db.conn.cursor()
    cur.execute("UPDATE core.stored_file SET size_bytes = ? WHERE id = ?", 11 * 1024 * 1024, int(big["id"]))
    cur.close()
    assert attach(ch, big["id"]).status_code == 422
    assert attach(ch, 999999999).status_code == 422
    findings = factories.upload(client, ch, name="Findings.PDF", module="projects")
    assert attach(other["headers"], findings["id"]).status_code == 403  # not assigned
    ok = attach(ch, findings["id"])
    assert ok.status_code == 201, ok.text
    assert ok.json()["data"]["uploadedByName"].startswith("Contributor") and ok.json()["data"]["fileId"] == findings["id"]
    assert attach(ch, findings["id"]).status_code == 409
    assert fe._rows(db, "SELECT company_id FROM core.attachment WHERE id = ?", int(ok.json()["data"]["id"])) == \
        [{"company_id": company}]
    files = client.get(f"{API}/tasks/{tid}/attachments", headers=other["headers"]).json()["data"]
    assert [f["name"] for f in files] == ["Findings.PDF"]
    assert client.get(files[0]["url"]).content == factories.PDF_BYTES
    assert client.delete(f"{API}/attachments/{files[0]['id']}", headers=other["headers"]).status_code == 403
    assert client.delete(f"{API}/attachments/{files[0]['id']}", headers=ch).status_code == 204
    # Detached, the file itself stays with the file service: its uploader can still see and delete it.
    assert client.get(f"/api/files/{findings['id']}", headers=ch).status_code == 200
    assert client.delete(f"/api/files/{findings['id']}", headers=ch).status_code == 204


def test_time_tracking(client, team):
    contributor, other, manager = team["contributor"], team["other"], team["manager"]
    tid = team["task"]["id"]
    entry = client.post(f"{API}/tasks/{tid}/time-entries",
                        json={"startAt": "2030-06-01T09:00:00", "endAt": "2030-06-01T10:30:00", "notes": "Sessions"},
                        headers=contributor["headers"])
    assert entry.status_code == 201 and entry.json()["data"]["minutes"] == 90
    by_minutes = client.post(f"{API}/tasks/{tid}/time-entries", json={"startAt": "2030-06-02T09:00:00", "minutes": 45},
                             headers=contributor["headers"])
    assert by_minutes.json()["data"]["minutes"] == 45
    assert client.post(f"{API}/tasks/{tid}/time-entries", json={"startAt": "2030-06-02T09:00:00", "minutes": 5},
                       headers=other["headers"]).status_code == 403  # not assigned
    backwards = client.post(f"{API}/tasks/{tid}/time-entries",
                            json={"startAt": "2030-06-01T10:00:00", "endAt": "2030-06-01T09:00:00"},
                            headers=contributor["headers"])
    assert backwards.status_code == 422

    started = client.post(f"{API}/tasks/{tid}/timer/start", headers=contributor["headers"])
    assert started.status_code == 201 and started.json()["data"]["isRunning"] is True
    again = client.post(f"{API}/tasks/{tid}/timer/start", headers=contributor["headers"])
    assert again.status_code == 409 and again.json()["code"] == "TIMER_RUNNING"
    stopped = client.post(f"{API}/timer/stop", json={"notes": "Quick"}, headers=contributor["headers"])
    assert stopped.status_code == 200 and stopped.json()["data"]["minutes"] == 1 and stopped.json()["data"]["isRunning"] is False

    entries = client.get(f"{API}/tasks/{tid}/time-entries", headers=other["headers"]).json()["data"]
    assert sum(e["minutes"] for e in entries) == 136
    assert client.get(f"{API}/tasks/{tid}", headers=other["headers"]).json()["data"]["timeTrackedMinutes"] == 136

    first = entry.json()["data"]
    assert client.put(f"{API}/time-entries/{first['id']}", json={"startAt": "2030-06-01T09:00:00", "minutes": 60,
                                                                 "rowVersion": first["rowVersion"]},
                      headers=other["headers"]).status_code == 403
    fixed = client.put(f"{API}/time-entries/{first['id']}", json={"startAt": "2030-06-01T09:00:00", "minutes": 60,
                                                                  "rowVersion": first["rowVersion"]},
                       headers=contributor["headers"])
    assert fixed.status_code == 200 and fixed.json()["data"]["minutes"] == 60
    assert client.delete(f"{API}/time-entries/{first['id']}", headers=other["headers"]).status_code == 403
    assert client.delete(f"{API}/time-entries/{first['id']}", headers=manager["headers"]).status_code == 204


def test_reminders(client, team):
    contributor, lead = team["contributor"], team["lead"]
    tid = team["task"]["id"]
    late = client.post(f"{API}/reminders", json={"entityType": "task", "entityId": int(tid),
                                                 "remindAt": "2030-07-05T09:00:00"}, headers=contributor["headers"])
    assert late.status_code == 422 and "remindAt" in late.json()["fieldErrors"]
    mine = client.post(f"{API}/reminders", json={"entityType": "task", "entityId": int(tid), "remindAt": "2030-06-29T09:00:00",
                                                 "notifyBeforeMinutes": 60, "reminderKind": "soft"},
                       headers=contributor["headers"])
    assert mine.status_code == 201
    assert mine.json()["data"]["name"] == "Usability test" and mine.json()["data"]["entityName"] == "Usability test"
    assert client.post(f"{API}/reminders", json={"entityType": "workspace", "entityId": int(team["ws"]["id"]),
                                                 "name": "Plan", "remindAt": "2030-06-01T09:00:00",
                                                 "assigneeId": lead["employee_id"]},
                       headers=contributor["headers"]).status_code == 403
    delegated = client.post(f"{API}/reminders", json={"entityType": "workspace", "entityId": int(team["ws"]["id"]),
                                                      "name": "Plan", "remindAt": "2030-06-01T09:00:00",
                                                      "assigneeId": contributor["employee_id"]}, headers=lead["headers"])
    assert delegated.status_code == 201

    listed = client.get(f"{API}/reminders", headers=contributor["headers"]).json()
    assert [r["name"] for r in listed["data"]] == ["Plan", "Usability test"] and listed["meta"]["total"] == 2
    rem = mine.json()["data"]
    upd = client.put(f"{API}/reminders/{rem['id']}", json={"entityType": "task", "entityId": int(tid), "name": "Check",
                                                           "remindAt": "2030-06-28T09:00:00",
                                                           "rowVersion": rem["rowVersion"]}, headers=contributor["headers"])
    assert upd.status_code == 200 and upd.json()["data"]["name"] == "Check"
    assert client.delete(f"{API}/reminders/{rem['id']}", headers=lead["headers"]).status_code == 404
    assert client.delete(f"{API}/reminders/{rem['id']}", headers=contributor["headers"]).status_code == 204


def test_sharing(client, team):
    lead, manager = team["lead"], team["manager"]
    tid = int(team["task"]["id"])
    default = client.get(f"{API}/shares", params={"entityType": "task", "entityId": tid}, headers=lead["headers"]).json()["data"]
    assert default["id"] is None and default["isPublic"] is False and "task_name_status" in default["properties"]
    body = {"entityType": "task", "entityId": tid, "isPublic": True, "validFrom": "2030-01-01T00:00:00",
            "validTo": "2030-02-01T00:00:00", "maxAccess": 5, "properties": ["assignee", "due_date"],
            "members": [{"employeeId": team["contributor"]["employee_id"], "accessLevel": "full_edit"},
                        {"email": "guest@example.com", "accessLevel": "commenter"}]}
    assert client.put(f"{API}/shares", json=body, headers=lead["headers"]).status_code == 403
    saved = client.put(f"{API}/shares", json=body, headers=manager["headers"])
    assert saved.status_code == 200, saved.text
    share = saved.json()["data"]
    assert share["link"] == f"/shared/{share['token']}" and share["maxAccess"] == 5
    assert share["properties"] == ["task_name_status", "assignee", "due_date"]
    assert [m["accessLevel"] for m in share["members"]] == ["full_edit", "commenter"]
    stale = client.put(f"{API}/shares", json={**body, "maxAccess": 9}, headers=manager["headers"])
    assert stale.status_code == 409
    again = client.put(f"{API}/shares", json={**body, "maxAccess": 9, "rowVersion": share["rowVersion"]},
                       headers=manager["headers"])
    assert again.json()["data"]["maxAccess"] == 9 and again.json()["data"]["token"] == share["token"]
    assert client.delete(f"{API}/shares/{share['id']}", headers=manager["headers"]).status_code == 204


def test_workspace_history(client, team):
    owner = team["owner"]
    wid = team["ws"]["id"]
    page = client.get(f"{API}/workspaces/{wid}/activity", params={"pageSize": 100}, headers=owner["headers"]).json()
    actions = {a["actionName"] for a in page["data"]}
    assert {"create", "comment", "time"} <= actions
    only = client.get(f"{API}/workspaces/{wid}/activity", params={"action": "comment"}, headers=owner["headers"]).json()
    assert only["data"] and {a["actionName"] for a in only["data"]} == {"comment"}
    found = client.get(f"{API}/workspaces/{wid}/activity", params={"q": "Usability"}, headers=owner["headers"]).json()
    assert all(a["itemName"] == "Usability test" for a in found["data"])
