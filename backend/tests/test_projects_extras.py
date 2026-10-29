"""Project management extras (gray structure, Backend Dependencies T1 to T11): docs, AI (unavailable), notepad,
reminder delivery, overdue settings and the story point penalty, the public share page, recents and dashboards,
location fields, external storage links and the personal list. One smoke test per group, plus the public
share limits and reminder delivery."""
from datetime import datetime

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.middlewares.errors import register_error_handlers
from app.services import projects_collab_service
from tests import factories
from tests import factories_events as fe
from tests import factories_projects as pm

API = "/api/projects"


@pytest.fixture(scope="module")
def team(db, client, company):
    dept = factories.department(db, company)
    people = {k: pm.person(db, client, company, dept, first_name=k.title())
              for k in ("owner", "manager", "lead", "contributor", "outsider")}
    ws = pm.workspace(client, people["owner"]["headers"], dept, people["owner"]["employee_id"], privacy="workspace",
                      members=[(people["manager"]["employee_id"], "manager"),
                               (people["lead"]["employee_id"], "team_leader"),
                               (people["contributor"]["employee_id"], "contributor")])
    task = pm.task(client, people["lead"]["headers"], ws["id"], name="Write the handbook",
                   assigneeIds=[str(people["contributor"]["employee_id"])])
    return {"dept": dept, "ws": ws, "task": task, **people}


def _doc(client, headers, workspace_id, **extra) -> dict:
    body = {"title": "Onboarding guide", "content": {"type": "doc", "content": []},
            "contentHtml": "<h1>Welcome</h1><p>Read this first, then &amp; ask.</p>", "visibility": "workspace", **extra}
    r = client.post(f"{API}/workspaces/{workspace_id}/docs", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


# --------------------------------------------------------------------------- T1 docs

def test_docs(client, team):
    owner, manager, contributor, outsider = team["owner"], team["manager"], team["contributor"], team["outsider"]
    wid = team["ws"]["id"]
    doc = _doc(client, contributor["headers"], wid, settings={"fontFamily": "Poppins", "header": {"toc": True}})
    assert doc["ownerId"] == str(contributor["employee_id"]) and doc["wordCount"] == 7 and doc["readingMinutes"] == 1
    assert doc["content"] == {"type": "doc", "content": []} and doc["settings"]["header"] == {"toc": True}
    assert doc["linkedTaskIds"] == [] and doc["contributors"] == [] and doc["archived"] is False

    listed = client.get(f"{API}/workspaces/{wid}/docs", params={"q": "welcome"}, headers=owner["headers"]).json()
    assert [d["id"] for d in listed["data"]] == [doc["id"]] and listed["meta"]["total"] == 1

    edit = {"title": "Onboarding", "content": {"type": "doc"}, "contentHtml": "<p>Short</p>",
            "visibility": "workspace", "rowVersion": doc["rowVersion"]}
    assert client.put(f"{API}/docs/{doc['id']}", json=edit, headers=team["lead"]["headers"]).status_code == 403
    r = client.put(f"{API}/docs/{doc['id']}", json=edit, headers=manager["headers"])
    assert r.status_code == 200, r.text
    edited = r.json()["data"]
    assert edited["title"] == "Onboarding" and edited["wordCount"] == 1
    assert [p["id"] for p in edited["contributors"]] == [str(manager["employee_id"])]
    assert client.put(f"{API}/docs/{doc['id']}", json=edit, headers=manager["headers"]).status_code == 409

    linked = client.put(f"{API}/docs/{doc['id']}/tasks", json={"taskIds": [team["task"]["id"]]},
                        headers=contributor["headers"])
    assert linked.status_code == 200 and linked.json()["data"]["linkedTaskIds"] == [team["task"]["id"]]

    comment = client.post(f"{API}/docs/{doc['id']}/comments", json={"body": "Looks good"}, headers=owner["headers"])
    assert comment.status_code == 201, comment.text
    reply = client.post(f"{API}/docs/{doc['id']}/comments", json={"body": "Thanks", "parentId": comment.json()["data"]["id"]},
                        headers=contributor["headers"])
    assert reply.status_code == 201
    thread = client.get(f"{API}/docs/{doc['id']}/comments", headers=owner["headers"]).json()["data"]
    assert [c["body"] for c in thread] == ["Looks good", "Thanks"] and thread[0]["replyCount"] == 1

    copy = client.post(f"{API}/docs/{doc['id']}/duplicate", json={}, headers=owner["headers"])
    assert copy.status_code == 201 and copy.json()["data"]["title"] == "Copy of Onboarding"
    assert copy.json()["data"]["ownerId"] == str(owner["employee_id"])

    export = client.get(f"{API}/docs/{doc['id']}/export", params={"format": "docx"}, headers=owner["headers"])
    assert export.status_code == 501 and export.json()["code"] == "EXPORT_NOT_AVAILABLE"

    current = linked.json()["data"]
    archived = client.patch(f"{API}/docs/{doc['id']}/archive", json={"rowVersion": current["rowVersion"]},
                            headers=contributor["headers"])
    assert archived.status_code == 200 and archived.json()["data"]["archived"] is True
    ids = [d["id"] for d in client.get(f"{API}/workspaces/{wid}/docs", headers=owner["headers"]).json()["data"]]
    assert doc["id"] not in ids and copy.json()["data"]["id"] in ids

    # A private doc is its owner's alone.
    private = _doc(client, owner["headers"], wid, title="Salary notes", visibility="private")
    assert client.get(f"{API}/docs/{private['id']}", headers=manager["headers"]).status_code == 404
    assert client.get(f"{API}/docs/{private['id']}", headers=owner["headers"]).status_code == 200
    # Not a member of a private workspace's docs: outsiders cannot write in this one.
    assert client.post(f"{API}/workspaces/{wid}/docs", json={"title": "X", "contentHtml": ""},
                       headers=outsider["headers"]).status_code == 403

    rv = archived.json()["data"]["rowVersion"]
    assert client.delete(f"{API}/docs/{doc['id']}", params={"rowVersion": rv}, headers=manager["headers"]).status_code == 403
    assert client.delete(f"{API}/docs/{doc['id']}", params={"rowVersion": rv},
                         headers=contributor["headers"]).status_code == 204
    assert client.get(f"{API}/docs/{doc['id']}", headers=owner["headers"]).status_code == 404


# --------------------------------------------------------------------------- T2, T10 AI

def test_ai_routes_answer_unavailable(client, team):
    h = team["contributor"]["headers"]
    calls = [("post", "/ai/write", {"action": "improve", "text": "hello"}), ("get", "/ai/line-up", None),
             ("get", "/ai/standup?scope=team", None), ("post", "/ai/reminders/suggest", {"taskId": 1}),
             ("get", "/ai/at-risk", None), ("post", "/ai/assign/suggest", {"taskId": 1}),
             ("get", "/ai/dependency-risk", None), ("post", "/ai/doc-suggest", {"title": "Plan"}),
             ("get", "/ai/related?taskId=1", None), ("post", "/ai/comment-suggest", {"taskId": 1}),
             ("get", "/ai/extension-suggestions", None), ("get", "/ai/search?q=plan", None),
             ("get", "/ai/workload", None), ("get", "/ai/summary?workspaceId=1", None)]
    for method, path, body in calls:
        r = client.request(method.upper(), API + path, json=body, headers=h)
        assert r.status_code == 503 and r.json()["code"] == "AI_UNAVAILABLE", (path, r.text)
    assert client.post(f"{API}/ai/write", json={"action": "nonsense"}, headers=h).status_code == 422


# --------------------------------------------------------------------------- T3 notepad

def test_notes(client, team):
    lead, other = team["lead"], team["contributor"]
    r = client.post(f"{API}/notes", json={"title": "Ideas", "contentHtml": "<p>Plan the offsite</p>"},
                    headers=lead["headers"])
    assert r.status_code == 201, r.text
    note = r.json()["data"]
    assert note["archived"] is False and note["version"] == 1
    r = client.put(f"{API}/notes/{note['id']}", json={"title": "Ideas", "contentHtml": "<p>Plan the offsite in May</p>",
                                                     "rowVersion": note["rowVersion"]}, headers=lead["headers"])
    assert r.status_code == 200 and r.json()["data"]["version"] == 2
    assert client.put(f"{API}/notes/{note['id']}", json={"title": "Stale", "rowVersion": note["rowVersion"]},
                      headers=lead["headers"]).status_code == 409
    history = client.get(f"{API}/notes/{note['id']}/history", headers=lead["headers"]).json()["data"]
    assert [v["version"] for v in history] == [2, 1] and history[0]["editedByName"].startswith("Lead")
    # Notes are their owner's own.
    assert client.get(f"{API}/notes/{note['id']}/history", headers=other["headers"]).status_code == 404
    assert note["id"] not in [n["id"] for n in client.get(f"{API}/notes", headers=other["headers"]).json()["data"]]

    converted = client.post(f"{API}/notes/{note['id']}/convert",
                            json={"to": "task", "workspaceId": team["ws"]["id"], "original": "archive"},
                            headers=lead["headers"])
    assert converted.status_code == 200, converted.text
    task = client.get(f"{API}/tasks/{converted.json()['data']['taskId']}", headers=lead["headers"]).json()["data"]
    assert task["name"] == "Ideas" and task["description"] == "Plan the offsite in May"
    archived = client.get(f"{API}/notes", params={"archived": "true"}, headers=lead["headers"]).json()["data"]
    assert note["id"] in [n["id"] for n in archived]

    second = client.post(f"{API}/notes", json={"title": "Doc me", "contentHtml": "<p>Body</p>"},
                         headers=lead["headers"]).json()["data"]
    as_doc = client.post(f"{API}/notes/{second['id']}/convert",
                         json={"to": "doc", "workspaceId": team["ws"]["id"], "original": "delete"}, headers=lead["headers"])
    assert as_doc.status_code == 200, as_doc.text
    doc = client.get(f"{API}/docs/{as_doc.json()['data']['docId']}", headers=lead["headers"]).json()["data"]
    assert doc["title"] == "Doc me" and doc["contentHtml"] == "<p>Body</p>"
    assert client.get(f"{API}/notes/{second['id']}/history", headers=lead["headers"]).status_code == 404

    third = client.post(f"{API}/notes", json={"title": "Bin"}, headers=lead["headers"]).json()["data"]
    assert client.delete(f"{API}/notes/{third['id']}", params={"rowVersion": third["rowVersion"]},
                         headers=lead["headers"]).status_code == 204


# --------------------------------------------------------------------------- T4 reminder delivery

def test_reminder_delivery(db, client, company, team):
    contributor, task = team["contributor"], team["task"]
    due = client.post(f"{API}/reminders", json={"entityType": "task", "entityId": task["id"], "name": "Send the draft",
                                                 "remindAt": "2031-03-01T10:00:00", "notifyBeforeMinutes": 60},
                      headers=contributor["headers"])
    assert due.status_code == 201, due.text
    later = client.post(f"{API}/reminders", json={"entityType": "task", "entityId": task["id"], "name": "Not yet",
                                                   "remindAt": "2031-03-01T10:00:00"}, headers=contributor["headers"])
    assert later.status_code == 201

    sent = projects_collab_service.deliver_due_reminders(db, company, datetime(2031, 3, 1, 9, 30))
    assert sent >= 1
    told = [n for n in fe.notifications(db, company, contributor["employee_id"], "task", int(task["id"]))
            if n["notification_type"] == "projects.reminder"]
    assert [n["title"] for n in told] == ["Reminder: Send the draft"]
    assert told[0]["link"].endswith(f"?task={task['id']}")
    rows = client.get(f"{API}/reminders", params={"includeDone": "true", "entityType": "task", "entityId": task["id"]},
                      headers=contributor["headers"]).json()["data"]
    by_name = {r["name"]: r for r in rows}
    assert by_name["Send the draft"]["notifiedAt"] and by_name["Not yet"]["notifiedAt"] is None
    # Sent once only.
    projects_collab_service.deliver_due_reminders(db, company, datetime(2031, 3, 1, 9, 45))
    assert len([n for n in fe.notifications(db, company, contributor["employee_id"], "task", int(task["id"]))
                if n["notification_type"] == "projects.reminder"]) == 1


# --------------------------------------------------------------------------- T5 overdue settings

def test_overdue_settings_and_penalty(client, team):
    owner, manager, lead, contributor = team["owner"], team["manager"], team["lead"], team["contributor"]
    ws = pm.workspace(client, owner["headers"], team["dept"], owner["employee_id"], privacy="workspace",
                      members=[(manager["employee_id"], "manager"), (lead["employee_id"], "team_leader"),
                               (contributor["employee_id"], "contributor")])
    url = f"{API}/workspaces/{ws['id']}/settings/overdue"
    first = client.get(url, headers=lead["headers"]).json()["data"]
    assert first == {"workspaceId": ws["id"], "penaltyPercent": 0, "maxExtensions": 1, "rowVersion": None}
    assert client.put(url, json={"penaltyPercent": 25, "maxExtensions": 2}, headers=lead["headers"]).status_code == 403
    saved = client.put(url, json={"penaltyPercent": 25, "maxExtensions": 2}, headers=owner["headers"])
    assert saved.status_code == 200, saved.text
    assert saved.json()["data"]["penaltyPercent"] == 25 and saved.json()["data"]["rowVersion"]
    assert client.put(url, json={"penaltyPercent": 30, "maxExtensions": 2}, headers=owner["headers"]).status_code == 409

    late = pm.task(client, lead["headers"], ws["id"], dueDate="2020-01-01")
    r = client.put(f"{API}/tasks/{late['id']}/assignees",
                   json={"assignees": [{"employeeId": contributor["employee_id"], "storyPoints": 10}]},
                   headers=lead["headers"])
    assert r.status_code == 200, r.text
    assert r.json()["data"]["storyPointsPenalty"] == 0 and r.json()["data"]["storyPointsEffective"] == 10
    r = client.patch(f"{API}/tasks/{late['id']}/status",
                     json={"statusId": pm.status_id(ws, "closed"), "rowVersion": r.json()["data"]["rowVersion"]},
                     headers=contributor["headers"])
    closed = r.json()["data"]
    assert closed["isClosedLate"] is True
    assert closed["storyPointsPenalty"] == 2.5 and closed["storyPointsEffective"] == 7.5

    # Two extension requests allowed per task; the row carries the newest.
    task = pm.task(client, lead["headers"], ws["id"], dueDate="2030-01-10", assigneeIds=[str(contributor["employee_id"])])
    asks = []
    for new_due in ("2030-02-01", "2030-03-01"):
        r = client.post(f"{API}/tasks/{task['id']}/extension-requests", json={"newDueDate": new_due, "reason": "Scope"},
                        headers=contributor["headers"])
        assert r.status_code == 201, r.text
        ext = r.json()["data"]["extensions"][-1]
        asks.append(client.patch(f"{API}/extension-requests/{ext['id']}/reject", json={"rowVersion": ext["rowVersion"]},
                                 headers=manager["headers"]).status_code)
    assert asks == [200, 200]
    third = client.post(f"{API}/tasks/{task['id']}/extension-requests", json={"newDueDate": "2030-04-01", "reason": "X"},
                        headers=contributor["headers"])
    assert third.status_code == 409 and third.json()["code"] == "EXTENSION_EXISTS"
    rows = client.get(f"{API}/workspaces/{ws['id']}/tasks", params={"groupBy": "none"}, headers=lead["headers"]).json()
    row = next(t for t in rows["data"] if t["id"] == task["id"])
    assert row["latestExtension"] == {"status": "rejected", "newDueDate": "2030-03-01"}


# --------------------------------------------------------------------------- T6 public share page

def _share(client, headers, task_id, **extra) -> dict:
    body = {"entityType": "task", "entityId": task_id, "isPublic": True,
            "properties": ["assignee", "due_date", "description", "comments"], **extra}
    r = client.put(f"{API}/shares", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()["data"]


def test_public_share_page(client, team):
    lead, manager, contributor = team["lead"], team["manager"], team["contributor"]
    parent = pm.task(client, lead["headers"], team["ws"]["id"], name="Launch", dueDate="2030-05-01",
                     description="Go live", assigneeIds=[str(contributor["employee_id"])])
    child = pm.task(client, lead["headers"], team["ws"]["id"], name="Press release", parentTaskId=parent["id"])
    other = pm.task(client, lead["headers"], team["ws"]["id"], name="Unrelated")
    share = _share(client, manager["headers"], parent["id"], maxAccess=3)
    token = share["token"]

    page = client.get(f"/api/public/shares/{token}")  # no sign-in
    assert page.status_code == 200, page.text
    data = page.json()["data"]
    assert data["entityType"] == "task" and data["title"] == "Launch" and data["allowOpenTasks"] is True
    rows = {t["name"]: t for t in data["tasks"]}
    assert set(rows) == {"Launch", "Press release"}
    assert len(rows["Launch"]["assignees"]) == 1 and rows["Launch"]["assignees"][0].startswith("Contributor")
    assert rows["Launch"]["dueDate"] == "2030-05-01" and rows["Launch"]["priority"] is None

    detail = client.get(f"/api/public/shares/{token}/tasks/{parent['id']}")
    assert detail.status_code == 200, detail.text
    d = detail.json()["data"]
    assert d["description"] == "Go live" and d["comments"] == [] and d["subtasks"] is None
    # A task outside the shared page is not shown (and does not use up an access).
    assert client.get(f"/api/public/shares/{token}/tasks/{other['id']}").status_code == 404
    assert client.get(f"{API}/shares", params={"entityType": "task", "entityId": parent["id"]},
                      headers=manager["headers"]).json()["data"]["accessCount"] == 2

    assert client.get(f"/api/public/shares/{token}/tasks/{child['id']}").status_code == 200  # third access
    spent = client.get(f"/api/public/shares/{token}")
    assert spent.status_code == 410 and spent.json()["code"] == "SHARE_EXHAUSTED"

    # The sharing dialog can still save: visits do not change its row version.
    again = client.put(f"{API}/shares", json={"entityType": "task", "entityId": parent["id"], "isPublic": True,
                                              "maxAccess": 10, "rowVersion": share["rowVersion"]},
                       headers=manager["headers"])
    assert again.status_code == 200, again.text
    assert client.get(f"/api/public/shares/{token}").status_code == 200

    old = _share(client, manager["headers"], other["id"], validFrom="2020-01-01T00:00:00Z", validTo="2020-02-01T00:00:00Z")
    expired = client.get(f"/api/public/shares/{old['token']}")
    assert expired.status_code == 410 and expired.json()["code"] == "SHARE_EXPIRED"

    closed = _share(client, manager["headers"], child["id"], isPublic=False)
    for path in (f"/api/public/shares/{closed['token']}", "/api/public/shares/no-such-token-here"):
        r = client.get(path)
        assert r.status_code == 404 and r.json()["code"] == "SHARE_NOT_FOUND"


# --------------------------------------------------------------------------- T7 recents and dashboards

def test_recents_and_dashboards(client, team):
    owner, lead, contributor = team["owner"], team["lead"], team["contributor"]
    wid = team["ws"]["id"]
    folder = client.post(f"{API}/workspaces/{wid}/folders", json={"name": f"Project {factories.tag()}"},
                         headers=owner["headers"])
    assert folder.status_code == 201, folder.text
    folder = folder.json()["data"]
    lst = client.post(f"{API}/workspaces/{wid}/lists", json={"name": f"Sprint {factories.tag()}", "folderId": folder["id"]},
                      headers=owner["headers"])
    assert lst.status_code == 201, lst.text
    lst = lst.json()["data"]
    in_folder = pm.task(client, lead["headers"], wid, name="Folder work", taskListId=lst["id"], dueDate="2020-01-01",
                        assigneeIds=[str(contributor["employee_id"])])

    h = contributor["headers"]
    for entity_type, entity_id in (("workspace", wid), ("folder", folder["id"]), ("task", in_folder["id"]),
                                   ("task", team["task"]["id"])):
        r = client.post(f"{API}/recents", json={"entityType": entity_type, "entityId": entity_id}, headers=h)
        assert r.status_code == 204, r.text
    assert client.post(f"{API}/recents", json={"entityType": "task", "entityId": 999999999}, headers=h).status_code == 404
    recents = client.get(f"{API}/recents", headers=h).json()["data"]
    assert recents[0]["entityId"] == team["task"]["id"] and recents[0]["workspaceName"] == team["ws"]["name"]
    scoped = client.get(f"{API}/recents", params={"folderId": folder["id"]}, headers=h).json()["data"]
    assert {(r["entityType"], r["entityId"]) for r in scoped} == {("folder", folder["id"]), ("task", in_folder["id"])}

    home = client.get(f"{API}/dashboard/home", headers=h)
    assert home.status_code == 200, home.text
    home = home.json()["data"]
    assert {t["id"] for t in home["myWork"]} >= {in_folder["id"], team["task"]["id"]}
    assert home["recents"][0]["type"] == "task" and len(home["activity"]) == 14
    assert isinstance(home["agenda"], list) and isinstance(home["assignedComments"], list)

    board = client.get(f"{API}/workspaces/{wid}/dashboard", headers=owner["headers"])
    assert board.status_code == 200, board.text
    board = board.json()["data"]
    assert sum(s["count"] for s in board["byStatus"]) >= 2 and board["overdue"] >= 1
    project = client.get(f"{API}/folders/{folder['id']}/dashboard", headers=owner["headers"]).json()["data"]
    assert sum(s["count"] for s in project["byStatus"]) == 1 and project["overdue"] == 1
    assert project["byAssignee"] == [{"employeeId": str(contributor["employee_id"]), "name": project["byAssignee"][0]["name"],
                                      "open": 1, "total": 1}]
    assert client.get(f"{API}/folders/999999999/dashboard", headers=owner["headers"]).status_code == 404


# --------------------------------------------------------------------------- T8 location fields

def test_location_field_and_filter(client, team):
    owner, lead = team["owner"], team["lead"]
    wid = team["ws"]["id"]
    field = client.post(f"{API}/workspaces/{wid}/custom-fields", json={"name": f"Site {factories.tag()}",
                                                                       "fieldType": "location"},
                        headers=owner["headers"])
    assert field.status_code == 201, field.text
    fid = field.json()["data"]["id"]
    placed = pm.task(client, lead["headers"], wid, name="Site visit")
    url = f"{API}/tasks/{placed['id']}/fields/{fid}"
    bad = client.put(url, json={"value": {"address": "Lahore", "lat": 120, "lng": 74.3}}, headers=lead["headers"])
    assert bad.status_code == 422
    ok = client.put(url, json={"value": {"address": "Lahore", "lat": 31.5204, "lng": 74.3587}}, headers=lead["headers"])
    assert ok.status_code == 200, ok.text
    rows = client.get(f"{API}/workspaces/{wid}/tasks", params={"hasLocation": "true", "groupBy": "none"},
                      headers=lead["headers"]).json()["data"]
    assert [t["id"] for t in rows] == [placed["id"]]


# --------------------------------------------------------------------------- T9 external storage

def test_storage_and_link_attachments(client, team):
    from app.routers import integrations_storage

    app = FastAPI()
    register_error_handlers(app)
    app.include_router(integrations_storage.router, prefix="/api")
    storage = TestClient(app)
    h = team["contributor"]["headers"]
    listed = storage.get("/api/integrations/storage", headers=h)
    assert listed.status_code == 200, listed.text
    assert [p["provider"] for p in listed.json()["data"]] == ["google_drive", "dropbox", "box", "onedrive"]
    assert not any(p["connected"] for p in listed.json()["data"])
    for method, path, body in (("POST", "/api/integrations/storage/dropbox/connect", {"redirectPath": "/x"}),
                               ("GET", "/api/integrations/storage/box/callback?code=1", None),
                               ("GET", "/api/integrations/storage/onedrive/files", None)):
        r = storage.request(method, path, json=body, headers=h)
        assert r.status_code == 503 and r.json()["code"] == "STORAGE_NOT_CONFIGURED", (path, r.text)
    assert storage.delete("/api/integrations/storage/google_drive", headers=h).status_code == 204
    assert storage.get("/api/integrations/storage/icloud/files", headers=h).status_code == 422

    tid = team["task"]["id"]
    link = {"provider": "google_drive", "externalId": "1AbC", "name": "Brief.docx",
            "webUrl": "https://drive.google.com/file/d/1AbC/view"}
    r = client.post(f"{API}/tasks/{tid}/attachments/link", json=link, headers=h)
    assert r.status_code == 201, r.text
    att = r.json()["data"]
    assert att["id"].startswith("link-") and att["fileId"] is None and att["url"] == link["webUrl"]
    assert att["provider"] == "google_drive"
    assert client.post(f"{API}/tasks/{tid}/attachments/link", json=link, headers=h).status_code == 409
    listed = client.get(f"{API}/tasks/{tid}/attachments", headers=h).json()["data"]
    assert att["id"] in [a["id"] for a in listed]
    assert client.get(f"{API}/tasks/{tid}", headers=h).json()["data"]["attachmentCount"] >= 1
    assert client.delete(f"{API}/attachments/{att['id']}", headers=h).status_code == 204
    assert client.delete(f"{API}/attachments/link-x", headers=h).status_code == 404


# --------------------------------------------------------------------------- T11 personal list

def test_personal_list(client, team):
    h, other = team["lead"]["headers"], team["contributor"]["headers"]
    a = client.post(f"{API}/personal-list", json={"title": "Book a room", "dueDate": "2030-01-02"}, headers=h)
    assert a.status_code == 201, a.text
    b = client.post(f"{API}/personal-list", json={"title": "Reply to Bilal", "dueDate": None}, headers=h).json()["data"]
    assert client.post(f"{API}/personal-list", json={"title": "x" * 121}, headers=h).status_code == 422
    a = a.json()["data"]
    assert a["done"] is False and a["dueDate"] == "2030-01-02"

    done = client.patch(f"{API}/personal-list/{a['id']}", json={"done": True, "rowVersion": a["rowVersion"]}, headers=h)
    assert done.status_code == 200 and done.json()["data"]["done"] is True
    stale = client.patch(f"{API}/personal-list/{a['id']}", json={"done": False, "rowVersion": a["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    items = client.get(f"{API}/personal-list", headers=h).json()["data"]
    assert [i["id"] for i in items] == [b["id"], a["id"]]  # open items first
    assert client.get(f"{API}/personal-list", headers=other).json()["data"] == []
    assert client.delete(f"{API}/personal-list/{b['id']}", params={"rowVersion": b["rowVersion"]},
                         headers=other).status_code == 404
    assert client.delete(f"{API}/personal-list/{b['id']}", params={"rowVersion": b["rowVersion"]},
                         headers=h).status_code == 204
