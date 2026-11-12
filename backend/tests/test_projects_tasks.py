"""Project management tasks: lifecycle, workspace-role rules on tasks, dependencies, extensions, the
List view's filters, grouping and sorting, row version conflicts, and task codes from the workspace key."""
import re
import uuid

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
    ws = pm.workspace(client, people["owner"]["headers"], dept, people["owner"]["employee_id"],
                      members=[(people["manager"]["employee_id"], "manager"),
                               (people["lead"]["employee_id"], "team_leader"),
                               (people["contributor"]["employee_id"], "contributor"),
                               (people["other"]["employee_id"], "contributor")])
    return {"dept": dept, "ws": ws, **people}


def test_task_lifecycle(client, team):
    lead, contributor, owner = team["lead"], team["contributor"], team["owner"]
    ws = team["ws"]
    wid = ws["id"]
    tag = client.post(f"{API}/workspaces/{wid}/tags", json={"name": f"T{factories.tag()}"}, headers=lead["headers"]).json()["data"]
    lst = client.post(f"{API}/workspaces/{wid}/lists", json={"name": f"List {factories.tag()}"},
                      headers=owner["headers"]).json()["data"]

    task = pm.task(client, lead["headers"], wid, name="Write the brief", taskListId=lst["id"], priority="high",
                   dueDate="2030-05-10", timeEstimateMinutes=90, assigneeIds=[str(contributor["employee_id"])],
                   tagIds=[tag["id"]], description="Context")
    assert re.fullmatch(rf"{ws['key']}-\d+", task["code"])  # <workspace key>-<n>, e.g. WAB-1
    assert task["statusGroup"] == "not_started" and task["statusName"] == "To Do"
    assert [a["employeeId"] for a in task["assignees"]] == [str(contributor["employee_id"])]
    assert [t["name"] for t in task["tags"]] == [tag["name"]] and task["listName"] == lst["name"]
    assert task["myRole"] == "team_leader" and task["createdByName"].startswith("Lead")

    # A subtask takes its parent's due date; a contributor may add one under a task assigned to them.
    sub = pm.task(client, contributor["headers"], wid, name="Outline", parentTaskId=task["id"])
    assert sub["dueDate"] == "2030-05-10" and sub["parentTaskId"] == task["id"] and sub["taskListId"] == lst["id"]
    assert client.post(f"{API}/tasks", json={"workspaceId": wid, "name": "Mine"},
                       headers=contributor["headers"]).status_code == 403

    # Edit: the contributor cannot change the assigned task's fields, the team leader can.
    body = {"name": "Write the brief v2", "priority": "urgent", "dueDate": "2030-05-12", "description": "Context",
            "timeEstimateMinutes": 120, "rowVersion": task["rowVersion"],
            "recurrence": {"every": 1, "unit": "week", "weekdays": [1, 3], "ends": "after", "count": 4}}
    assert client.put(f"{API}/tasks/{task['id']}", json=body, headers=contributor["headers"]).status_code == 403
    r = client.put(f"{API}/tasks/{task['id']}", json=body, headers=lead["headers"])
    assert r.status_code == 200, r.text
    task = r.json()["data"]
    assert task["priority"] == "urgent" and task["recurrence"]["weekdays"] == [1, 3]
    # Remap Subtask Due Dates is on (Work Starter): the subtask moved two days too.
    assert client.get(f"{API}/tasks/{sub['id']}", headers=lead["headers"]).json()["data"]["dueDate"] == "2030-05-12"
    stale = client.put(f"{API}/tasks/{task['id']}", json={**body, "name": "Stale"}, headers=lead["headers"])
    assert stale.status_code == 409

    # Status: the assignee moves it along; closing stamps closedAt; reopening clears it.
    active = pm.status_id(ws, "active")
    r = client.patch(f"{API}/tasks/{task['id']}/status", json={"statusId": active, "rowVersion": task["rowVersion"]},
                     headers=contributor["headers"])
    assert r.status_code == 200 and r.json()["data"]["statusGroup"] == "active"
    task = r.json()["data"]
    closed = pm.status_id(ws, "closed")
    r = client.patch(f"{API}/tasks/{task['id']}/status", json={"statusId": closed, "rowVersion": task["rowVersion"]},
                     headers=contributor["headers"])
    task = r.json()["data"]
    assert task["closedAt"] and task["isClosedLate"] is False and task["isOverdue"] is False
    r = client.patch(f"{API}/tasks/{task['id']}/status", json={"statusId": active, "rowVersion": task["rowVersion"]},
                     headers=lead["headers"])
    task = r.json()["data"]
    assert task["closedAt"] is None
    other = team["other"]
    assert client.patch(f"{API}/tasks/{task['id']}/status", json={"statusId": closed, "rowVersion": task["rowVersion"]},
                        headers=other["headers"]).status_code == 404  # not assigned: not visible in a private workspace

    # Assignees with story points: team leaders and above.
    r = client.put(f"{API}/tasks/{task['id']}/assignees",
                   json={"assignees": [{"employeeId": contributor["employee_id"], "storyPoints": 5},
                                       {"employeeId": other["employee_id"], "storyPoints": 3}]}, headers=lead["headers"])
    assert r.status_code == 200 and r.json()["data"]["storyPointsTotal"] == 8
    assert client.put(f"{API}/tasks/{task['id']}/assignees", json={"assignees": []},
                      headers=contributor["headers"]).status_code == 403

    # Checklist (at most 20), attachments, move and convert, delete.
    item = client.post(f"{API}/tasks/{task['id']}/checklist", json={"itemText": "Draft"}, headers=contributor["headers"])
    assert item.status_code == 201
    done = client.put(f"{API}/checklist-items/{item.json()['data']['id']}",
                      json={"itemText": "Draft", "isDone": True, "rowVersion": item.json()["data"]["rowVersion"]},
                      headers=contributor["headers"])
    assert done.json()["data"]["isDone"] is True

    task = client.get(f"{API}/tasks/{task['id']}", headers=lead["headers"]).json()["data"]
    assert task["checklistDoneCount"] == 1 and task["subtaskCount"] == 1 and [s["id"] for s in task["subtasks"]] == [sub["id"]]
    moved = client.post(f"{API}/tasks/{task['id']}/move", json={"taskListId": None, "rowVersion": task["rowVersion"]},
                        headers=lead["headers"])
    assert moved.status_code == 200 and moved.json()["data"]["taskListId"] is None
    assert client.get(f"{API}/tasks/{sub['id']}", headers=lead["headers"]).json()["data"]["taskListId"] is None

    history = client.get(f"{API}/tasks/{task['id']}/activity", params={"pageSize": 100}, headers=lead["headers"]).json()
    actions = {a["actionName"] for a in history["data"]}
    assert {"create", "update", "status", "assign", "move"} <= actions

    task = moved.json()["data"]
    assert client.delete(f"{API}/tasks/{task['id']}", params={"rowVersion": task["rowVersion"]},
                         headers=contributor["headers"]).status_code == 403
    assert client.delete(f"{API}/tasks/{task['id']}", params={"rowVersion": task["rowVersion"]},
                         headers=team["manager"]["headers"]).status_code == 204
    assert client.get(f"{API}/tasks/{sub['id']}", headers=lead["headers"]).status_code == 404


def test_dependencies_block_completion(client, team):
    lead, ws = team["lead"], team["ws"]
    first = pm.task(client, lead["headers"], ws["id"], name="Design")
    second = pm.task(client, lead["headers"], ws["id"], name="Build")
    r = client.post(f"{API}/tasks/{second['id']}/dependencies", json={"otherTaskId": first["id"], "kind": "waiting_on"},
                    headers=lead["headers"])
    assert r.status_code == 200 and r.json()["data"]["openDependencyCount"] == 1
    second = r.json()["data"]
    assert second["dependencies"][0]["kind"] == "waiting_on"
    loop = client.post(f"{API}/tasks/{second['id']}/dependencies", json={"otherTaskId": first["id"], "kind": "blocking"},
                       headers=lead["headers"])
    assert loop.status_code == 409  # already linked
    first_seen = client.get(f"{API}/tasks/{first['id']}", headers=lead["headers"]).json()["data"]
    assert first_seen["blockingCount"] == 1 and first_seen["dependencies"][0]["kind"] == "blocking"

    blocked = client.patch(f"{API}/tasks/{second['id']}/status",
                           json={"statusId": pm.status_id(ws, "active"), "rowVersion": second["rowVersion"]},
                           headers=lead["headers"])
    assert blocked.status_code == 409 and blocked.json()["code"] == "DEPENDENCY_OPEN"
    client.patch(f"{API}/tasks/{first['id']}/status",
                 json={"statusId": pm.status_id(ws, "closed"), "rowVersion": first_seen["rowVersion"]},
                 headers=lead["headers"])
    ok = client.patch(f"{API}/tasks/{second['id']}/status",
                      json={"statusId": pm.status_id(ws, "closed"), "rowVersion": second["rowVersion"]},
                      headers=lead["headers"])
    assert ok.status_code == 200
    dep_id = second["dependencies"][0]["id"]
    assert client.delete(f"{API}/dependencies/{dep_id}", headers=lead["headers"]).status_code == 204


def test_overdue_extension_and_late_completion(client, db, company, team):
    lead, contributor, manager, ws = team["lead"], team["contributor"], team["manager"], team["ws"]
    late = pm.task(client, lead["headers"], ws["id"], dueDate="2020-01-01", assigneeIds=[str(contributor["employee_id"])])
    assert late["isOverdue"] is True
    r = client.patch(f"{API}/tasks/{late['id']}/status",
                     json={"statusId": pm.status_id(ws, "closed"), "rowVersion": late["rowVersion"]},
                     headers=contributor["headers"])
    assert r.json()["data"]["isClosedLate"] is True

    task = pm.task(client, lead["headers"], ws["id"], dueDate="2030-01-10", assigneeIds=[str(contributor["employee_id"])])
    assert client.post(f"{API}/tasks/{task['id']}/extension-requests", json={"newDueDate": "2030-02-01", "reason": "Scope"},
                       headers=lead["headers"]).status_code == 403  # not an assignee
    r = client.post(f"{API}/tasks/{task['id']}/extension-requests", json={"newDueDate": "2030-02-01", "reason": "Scope"},
                    headers=contributor["headers"])
    assert r.status_code == 201
    ext = r.json()["data"]["extensions"][0]
    assert ext["status"] == "pending"
    # Managers and above in the workspace are told (the owner and the manager); a team leader and the
    # person asking are not.
    def told(key):
        return fe.notifications(db, company, team[key]["employee_id"], "pm.task_extension", int(ext["id"]))
    asked = told("manager")
    assert [n["notification_type"] for n in asked] == ["projects.extension_requested"]
    assert asked[0]["title"] == f"Extension requested: {task['code']} {task['name']}"
    assert asked[0]["link"] == f"/project-management/workspaces/{ws['id']}?task={task['id']}"
    assert "2030-01-10" in asked[0]["body"] and "2030-02-01" in asked[0]["body"]
    assert len(told("owner")) == 1 and told("lead") == [] and told("contributor") == []
    assert len(fe.events(db, company, "projects.extension_requested", int(ext["id"]))) == 1

    again = client.post(f"{API}/tasks/{task['id']}/extension-requests", json={"newDueDate": "2030-03-01", "reason": "More"},
                        headers=contributor["headers"])
    assert again.status_code == 409 and again.json()["code"] == "EXTENSION_EXISTS"
    assert client.patch(f"{API}/extension-requests/{ext['id']}/approve", json={"rowVersion": ext["rowVersion"]},
                        headers=lead["headers"]).status_code == 403
    r = client.patch(f"{API}/extension-requests/{ext['id']}/approve", json={"rowVersion": ext["rowVersion"]},
                     headers=manager["headers"])
    assert r.status_code == 200
    approved = r.json()["data"]
    assert approved["dueDate"] == "2030-02-01" and approved["originalDueDate"] == "2030-01-10"
    assert approved["extensions"][0]["status"] == "approved"
    # The person who asked hears the answer; the manager who decided hears nothing more.
    answer = told("contributor")
    assert [n["title"] for n in answer] == [f"Extension approved: {task['code']} {task['name']}"]
    assert answer[0]["notification_type"] == "projects.extension_decided" and "2030-02-01" in answer[0]["body"]
    assert len(told("manager")) == 1
    decided = fe.events(db, company, "projects.extension_decided", int(ext["id"]))
    assert len(decided) == 1 and decided[0]["data"]["status"] == "approved"


def test_wip_limit(client, team):
    owner = team["owner"]
    ws = pm.workspace(client, owner["headers"], team["dept"], owner["employee_id"], privacy="workspace",
                      statuses=[{"name": "Open", "statusGroup": "not_started"},
                                {"name": "Doing", "statusGroup": "active", "wipLimit": 1},
                                {"name": "Done", "statusGroup": "closed"}],
                      features=[{"featureCode": "wip_limits"}])
    doing = pm.status_id(ws, "active")
    a = pm.task(client, owner["headers"], ws["id"])
    b = pm.task(client, owner["headers"], ws["id"])
    assert client.patch(f"{API}/tasks/{a['id']}/status", json={"statusId": doing, "rowVersion": a["rowVersion"]},
                        headers=owner["headers"]).status_code == 200
    full = client.patch(f"{API}/tasks/{b['id']}/status", json={"statusId": doing, "rowVersion": b["rowVersion"]},
                        headers=owner["headers"])
    assert full.status_code == 409 and full.json()["code"] == "WIP_LIMIT"
    # Priority is off in this workspace.
    off = client.post(f"{API}/tasks", json={"workspaceId": ws["id"], "name": "x", "priority": "high"},
                      headers=owner["headers"])
    assert off.status_code == 409 and off.json()["code"] == "FEATURE_OFF"


def test_convert_to_list(client, team):
    owner, ws = team["owner"], team["ws"]
    parent = pm.task(client, owner["headers"], ws["id"], name=f"Launch {factories.tag()}")
    child = pm.task(client, owner["headers"], ws["id"], name="Press kit", parentTaskId=parent["id"])
    assert client.post(f"{API}/tasks/{parent['id']}/convert-to-list", json={"rowVersion": parent["rowVersion"]},
                       headers=team["lead"]["headers"]).status_code == 403
    r = client.post(f"{API}/tasks/{parent['id']}/convert-to-list", json={"rowVersion": parent["rowVersion"]},
                    headers=owner["headers"])
    assert r.status_code == 200
    list_id = r.json()["data"]["taskListId"]
    moved = client.get(f"{API}/tasks/{child['id']}", headers=owner["headers"]).json()["data"]
    assert moved["taskListId"] == list_id and moved["parentTaskId"] is None
    assert client.get(f"{API}/tasks/{parent['id']}", headers=owner["headers"]).status_code == 404


def test_list_view_filters_grouping_sorting(client, team):
    owner, lead, contributor, other = team["owner"], team["lead"], team["contributor"], team["other"]
    ws = pm.workspace(client, owner["headers"], team["dept"], owner["employee_id"], privacy="workspace",
                      members=[(lead["employee_id"], "team_leader"), (contributor["employee_id"], "contributor"),
                               (other["employee_id"], "contributor")])
    wid = ws["id"]
    h = lead["headers"]
    bug = client.post(f"{API}/workspaces/{wid}/tags", json={"name": "Bug"}, headers=h).json()["data"]
    c_id, o_id = str(contributor["employee_id"]), str(other["employee_id"])
    alpha = pm.task(client, h, wid, name="Alpha", priority="urgent", dueDate="2020-02-01", assigneeIds=[c_id],
                    tagIds=[bug["id"]])
    beta = pm.task(client, h, wid, name="Beta", priority="low", dueDate="2031-01-01", assigneeIds=[c_id, o_id])
    gamma = pm.task(client, h, wid, name="Gamma")
    child = pm.task(client, h, wid, name="Alpha child", parentTaskId=alpha["id"], assigneeIds=[o_id])
    client.patch(f"{API}/tasks/{gamma['id']}/status", json={"statusId": pm.status_id(ws, "closed"),
                                                            "rowVersion": gamma["rowVersion"]}, headers=h)

    def ids(**params):
        r = client.get(f"{API}/workspaces/{wid}/tasks", params={"pageSize": 100, **params}, headers=h)
        assert r.status_code == 200, r.text
        return r.json()

    page = ids(groupBy="none", sortBy="name")
    assert [t["name"] for t in page["data"]] == ["Alpha", "Alpha child", "Beta", "Gamma"]
    assert page["data"][1]["depth"] == 1 and page["data"][1]["rootId"] == alpha["id"]
    assert page["meta"]["total"] == 4 and page["groups"] == [{"key": "all", "name": "All tasks", "count": 4}]

    assert [t["name"] for t in ids(groupBy="none", sortBy="name", subtasks="collapsed")["data"]] == ["Alpha", "Beta", "Gamma"]
    assert [t["name"] for t in ids(groupBy="none", sortBy="name", sortDir="desc", subtasks="separate")["data"]] == \
        ["Gamma", "Beta", "Alpha child", "Alpha"]
    assert [t["name"] for t in ids(groupBy="none", priorities=["urgent", "low"], sortBy="priority")["data"]] == \
        ["Alpha", "Beta"]
    assert [t["name"] for t in ids(groupBy="none", priorities="none", subtasks="separate", sortBy="name")["data"]] == \
        ["Alpha child", "Gamma"]
    assert [t["name"] for t in ids(groupBy="none", tagIds=bug["id"])["data"]] == ["Alpha"]
    # The subtask took its parent's (past) due date, so both are overdue.
    assert [t["name"] for t in ids(groupBy="none", overdue=True, subtasks="separate")["data"]] == ["Alpha", "Alpha child"]
    assert [t["name"] for t in ids(groupBy="none", includeClosed=False, sortBy="name", subtasks="separate")["data"]] == \
        ["Alpha", "Alpha child", "Beta"]
    assert [t["name"] for t in ids(groupBy="none", unassigned=True)["data"]] == ["Gamma"]
    assert [t["name"] for t in ids(groupBy="none", q="gam")["data"]] == ["Gamma"]
    assert [t["name"] for t in ids(groupBy="none", sortBy="due_date", sortDir="desc", subtasks="separate")["data"]][:2] \
        == ["Beta", "Alpha"]  # empty due dates last

    by_status = ids(groupBy="status", sortBy="name")
    assert [g["name"] for g in by_status["groups"]] == ["To Do", "Completed"]
    assert [g["count"] for g in by_status["groups"]] == [3, 1]

    by_assignee = ids(groupBy="assignee", sortBy="name", subtasks="separate")
    counts = {g["key"]: g["count"] for g in by_assignee["groups"]}
    assert counts == {c_id: 2, o_id: 2, "none": 1}  # Beta appears under both assignees
    assert by_assignee["groups"][-1]["name"] == "Unassigned"

    paged = client.get(f"{API}/workspaces/{wid}/tasks", params={"pageSize": 2, "page": 2, "groupBy": "none",
                                                                "sortBy": "name"}, headers=h).json()
    assert paged["meta"] == {"page": 2, "pageSize": 2, "total": 4, "totalPages": 2}
    assert [t["name"] for t in paged["data"]] == ["Beta", "Gamma"]

    # A Private Field column is blanked for whoever it is private to.
    client.put(f"{API}/workspaces/{wid}/column-permissions/priority",
               json={"roles": [{"memberRole": "contributor", "permissionLevel": "private"}]}, headers=owner["headers"])
    seen = client.get(f"{API}/workspaces/{wid}/tasks", params={"groupBy": "none", "q": "Beta"},
                      headers=contributor["headers"]).json()
    assert seen["hiddenColumns"] == ["priority"] and seen["data"][0]["priority"] is None
    assert child["parentTaskId"] == alpha["id"] and beta["storyPointsTotal"] is None


def test_assignment_is_announced(client, db, company, team):
    lead, contributor, other = team["lead"], team["contributor"], team["other"]
    task = pm.task(client, lead["headers"], team["ws"]["id"], name="Write the brief",
                   assigneeIds=[str(contributor["employee_id"])])
    tid = int(task["id"])
    first = fe.events(db, company, "projects.task_assigned", tid)
    assert len(first) == 1 and first[0]["data"]["assigned"] == [{"employeeId": str(contributor["employee_id"])}]
    told = fe.notifications(db, company, contributor["employee_id"], "pm.task", tid)
    assert len(told) == 1 and told[0]["title"] == f"Task assigned to you: {task['code']} Write the brief"

    # Only people newly assigned are told; whoever assigns themselves is not.
    r = client.put(f"{API}/tasks/{tid}/assignees", json={"assignees": [
        {"employeeId": contributor["employee_id"]}, {"employeeId": other["employee_id"]},
        {"employeeId": lead["employee_id"]}]}, headers=lead["headers"])
    assert r.status_code == 200, r.text
    second = fe.events(db, company, "projects.task_assigned", tid)
    assert len(second) == 2
    assert {a["employeeId"] for a in second[1]["data"]["assigned"]} == {str(other["employee_id"]), str(lead["employee_id"])}
    assert len(fe.notifications(db, company, contributor["employee_id"], "pm.task", tid)) == 1
    assert len(fe.notifications(db, company, other["employee_id"], "pm.task", tid)) == 1
    assert fe.notifications(db, company, lead["employee_id"], "pm.task", tid) == []


def test_covers(client, db, team):
    owner, lead, contributor = team["owner"], team["lead"], team["contributor"]
    wid = team["ws"]["id"]
    banner = factories.upload(client, owner["headers"], name="banner.png", content=factories.PNG_BYTES,
                              module="projects")
    ws = client.get(f"{API}/workspaces/{wid}", headers=owner["headers"]).json()["data"]
    pdf = factories.upload(client, owner["headers"], module="projects")
    not_image = client.put(f"{API}/workspaces/{wid}/cover", json={"fileId": int(pdf["id"]), "rowVersion": ws["rowVersion"]},
                           headers=owner["headers"])
    assert not_image.status_code == 422 and "fileId" in not_image.json()["fieldErrors"]
    r = client.put(f"{API}/workspaces/{wid}/cover", json={"fileId": int(banner["id"]), "rowVersion": ws["rowVersion"]},
                   headers=owner["headers"])
    assert r.status_code == 200, r.text
    ws = r.json()["data"]
    assert ws["coverFileId"] == banner["id"] and ws["cover"]["name"] == "banner.png"
    assert client.get(ws["cover"]["url"]).content == factories.PNG_BYTES
    listed = client.get(f"{API}/workspaces", headers=owner["headers"]).json()["data"]
    assert next(w for w in listed if w["id"] == wid)["cover"]["id"] == banner["id"]
    assert client.put(f"{API}/workspaces/{wid}/cover", json={"fileId": None, "rowVersion": ws["rowVersion"]},
                      headers=lead["headers"]).status_code == 403
    cleared = client.put(f"{API}/workspaces/{wid}/cover", json={"fileId": None, "rowVersion": ws["rowVersion"]},
                         headers=owner["headers"])
    assert cleared.status_code == 200 and cleared.json()["data"]["cover"] is None

    task = pm.task(client, lead["headers"], wid, name="With a cover")
    pic = factories.upload(client, lead["headers"], name="cover.png", content=factories.PNG_BYTES, module="projects")
    assert client.put(f"{API}/tasks/{task['id']}/cover", json={"fileId": int(pic["id"]), "rowVersion": task["rowVersion"]},
                      headers=contributor["headers"]).status_code in (403, 404)  # not theirs to edit
    r = client.put(f"{API}/tasks/{task['id']}/cover", json={"fileId": int(pic["id"]), "rowVersion": task["rowVersion"]},
                   headers=lead["headers"])
    assert r.status_code == 200, r.text
    assert r.json()["data"]["cover"]["name"] == "cover.png"
    stale = client.put(f"{API}/tasks/{task['id']}/cover", json={"fileId": None, "rowVersion": task["rowVersion"]},
                       headers=lead["headers"])
    assert stale.status_code == 409
    rows = client.get(f"{API}/workspaces/{wid}/tasks", headers=lead["headers"]).json()["data"]
    assert next(t for t in rows if t["id"] == task["id"])["cover"]["id"] == pic["id"]


def _number() -> str:
    """Digits only, so a workspace name stays one word for its key (digits separate words)."""
    return str(uuid.uuid4().int)[:8]


def test_task_codes_use_the_workspace_key(client, team):
    owner = team["owner"]
    h = owner["headers"]

    def workspace(name):
        return pm.workspace(client, h, team["dept"], owner["employee_id"], privacy="workspace", name=name)

    def edit(ws, **changes):
        body = {"name": ws["name"], "privacy": ws["privacy"], "departmentId": ws["departmentId"],
                "ownerId": ws["ownerId"], "rowVersion": ws["rowVersion"], **changes}
        return client.put(f"{API}/workspaces/{ws['id']}", json=body, headers=h)

    # The key comes from the name: a one-word name's first three letters; the same again gets a letter more.
    first, second = workspace(f"Onboarding {_number()}"), workspace(f"Onboarding {_number()}")
    assert first["key"] == "ONB" and second["key"] == "ONBA"
    a = pm.task(client, h, first["id"])
    b = pm.task(client, h, first["id"])
    sub = pm.task(client, h, first["id"], parentTaskId=a["id"])
    elsewhere = pm.task(client, h, second["id"])
    assert [a["code"], b["code"], sub["code"], elsewhere["code"]] == ["ONB-1", "ONB-2", "ONB-3", "ONBA-1"]

    # Search and #task mentions work with the short codes.
    found = client.get(f"{API}/workspaces/{first['id']}/tasks", params={"q": "ONB-2", "groupBy": "none"}, headers=h)
    assert [t["id"] for t in found.json()["data"]] == [b["id"]]
    c = client.post(f"{API}/tasks/{a['id']}/comments", json={"body": "See #ONB-2", "mentions": [{"taskId": b["id"]}]},
                    headers=h)
    assert c.status_code == 201 and [m["taskCode"] for m in c.json()["data"]["mentions"]] == ["ONB-2"]

    # Editing the key: 2 to 5 letters A-Z, unique in the company; tasks keep their codes, the count goes on.
    for bad in ("O", "PEOPLE", "ON1", "Ö N"):
        r = edit(first, key=bad)
        assert r.status_code == 422 and "key" in r.json()["fieldErrors"], (bad, r.text)
    taken = edit(first, key="onba")
    assert taken.status_code == 409 and taken.json()["code"] == "WORKSPACE_KEY_DUPLICATE"
    assert "key" in taken.json()["fieldErrors"]
    r = edit(first, key="hire")
    assert r.status_code == 200, r.text
    first = r.json()["data"]
    assert first["key"] == "HIRE"
    assert pm.task(client, h, first["id"])["code"] == "HIRE-4"
    assert client.get(f"{API}/tasks/{a['id']}", headers=h).json()["data"]["code"] == "ONB-1"
    kept = edit(first, description="Key left out")
    assert kept.status_code == 200 and kept.json()["data"]["key"] == "HIRE"

    # A key given up and taken by another workspace carries on above the codes it left: ONB-1 to 3 stay unique.
    r = edit(second, key="ONB")
    assert r.status_code == 200, r.text
    assert pm.task(client, h, second["id"])["code"] == "ONB-4"

    # Sorting by code goes by number: ...-9 before ...-10.
    third = workspace(f"Sorting {_number()}")
    for _ in range(10):
        pm.task(client, h, third["id"])
    by_code = {"groupBy": "none", "sortBy": "code", "pageSize": 100}
    rows = client.get(f"{API}/workspaces/{third['id']}/tasks", params=by_code, headers=h)
    assert [t["code"] for t in rows.json()["data"]] == [f"{third['key']}-{n}" for n in range(1, 11)]
    rows = client.get(f"{API}/workspaces/{third['id']}/tasks", params={**by_code, "sortDir": "desc"}, headers=h)
    assert [t["code"] for t in rows.json()["data"]] == [f"{third['key']}-{n}" for n in range(10, 0, -1)]
