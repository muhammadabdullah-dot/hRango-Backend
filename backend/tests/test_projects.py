"""Project management: the Create Workspace wizard, workspace roles, members, statuses, features,
column permissions, custom fields, folders, lists, views, favourites and company RBAC refusal."""
import pytest

from tests import factories
from tests import factories_projects as pm

API = "/api/projects"


@pytest.fixture(scope="module")
def team(db, client, company):
    dept = factories.department(db, company)
    people = {k: pm.person(db, client, company, dept, first_name=k.title())
              for k in ("owner", "hr", "manager", "lead", "contributor", "outsider")}
    ws = pm.workspace(client, people["owner"]["headers"], dept, people["owner"]["employee_id"],
                      members=[(people["hr"]["employee_id"], "hr"), (people["manager"]["employee_id"], "manager"),
                               (people["lead"]["employee_id"], "team_leader"),
                               (people["contributor"]["employee_id"], "contributor")])
    return {"dept": dept, "ws": ws, **people}


def test_templates(client, team):
    h = team["owner"]["headers"]
    workflows = client.get(f"{API}/templates", headers=h).json()["data"]
    assert [t["code"] for t in workflows] == ["work_starter", "project_management", "marketing_team", "product_engineering"]
    starter = workflows[0]
    assert [v["viewType"] for v in starter["views"]] == ["list", "board"]
    assert [s["name"] for s in starter["statuses"]] == ["To Do", "In-Progress", "Completed"]
    assert len(starter["features"]) == 12
    statuses = client.get(f"{API}/templates", params={"kind": "status"}, headers=h).json()["data"]
    assert {t["code"] for t in statuses} == {"custom", "content", "kanban", "marketing", "scrum"}


def test_wizard_creates_full_workspace(db, client, company, team):
    owner, dept = team["owner"], team["dept"]
    other = pm.person(db, client, company, dept)
    ws = pm.workspace(
        client, owner["headers"], dept, owner["employee_id"], members=[(other["employee_id"], "manager")],
        description="Design work", workflowTemplate="product_engineering", statusMode="custom",
        statuses=[{"name": "Backlog", "color": "#979797", "statusGroup": "not_started"},
                  {"name": "Building", "color": "#2F639A", "statusGroup": "active", "wipLimit": 3},
                  {"name": "Shipped", "color": "#318845", "statusGroup": "closed"}],
        views=[{"viewType": "list"}, {"viewType": "board", "isDefault": True}, {"viewType": "calendar"}],
        features=[{"featureCode": "priority"}, {"featureCode": "tags"}, {"featureCode": "wip_limits"}])
    assert ws["workflowTemplate"] == "product_engineering" and ws["statusMode"] == "custom"
    assert [s["name"] for s in ws["statuses"]] == ["Backlog", "Building", "Shipped"]
    assert ws["statuses"][1]["wipLimit"] == 3
    assert {v["viewType"]: v["isDefault"] for v in ws["views"]} == {"list": False, "board": True, "calendar": False}
    assert next(v for v in ws["views"] if v["viewType"] == "list")["isRequired"] is True
    assert {f["featureCode"] for f in ws["features"]} == {"priority", "tags", "wip_limits"}
    assert {m["employeeId"]: m["memberRole"] for m in ws["members"]} == {
        str(owner["employee_id"]): "workspace_admin", str(other["employee_id"]): "manager"}
    assert ws["myRole"] == "workspace_admin" and ws["rowVersion"]

    # Leaving statuses, views and features out takes the template's; a status template can seed custom statuses.
    plain = pm.workspace(client, owner["headers"], dept, owner["employee_id"], privacy="workspace")
    assert [s["name"] for s in plain["statuses"]] == ["To Do", "In-Progress", "Completed"]
    assert [v["viewType"] for v in plain["views"]] == ["list", "board"] and len(plain["features"]) == 12
    scrum = pm.workspace(client, owner["headers"], dept, owner["employee_id"], privacy="public", statusMode="custom",
                         statusTemplate="scrum")
    assert scrum["statusTemplate"] == "scrum" and "Blocked" in [s["name"] for s in scrum["statuses"]]

    base = {"privacy": "public", "departmentId": str(dept), "ownerId": str(owner["employee_id"])}
    dup = client.post(f"{API}/workspaces", json={**base, "name": ws["name"].upper()}, headers=owner["headers"])
    assert dup.status_code == 409 and dup.json()["code"] == "WORKSPACE_DUPLICATE"
    short = client.post(f"{API}/workspaces", json={**base, "name": "ab"}, headers=owner["headers"])
    assert short.status_code == 422
    lonely = client.post(f"{API}/workspaces", json={**base, "name": f"Solo {factories.tag()}", "privacy": "private"},
                         headers=owner["headers"])
    assert lonely.status_code == 422 and "members" in lonely.json()["fieldErrors"]
    bad = client.post(f"{API}/workspaces", json={**base, "name": f"Bad {factories.tag()}", "statuses": [
        {"name": "Doing", "statusGroup": "active"}]}, headers=owner["headers"])
    assert bad.status_code == 422 and "statuses" in bad.json()["fieldErrors"]


def test_private_workspace_is_for_members(client, team):
    ws = team["ws"]
    assert client.get(f"{API}/workspaces/{ws['id']}", headers=team["outsider"]["headers"]).status_code == 404
    listed = client.get(f"{API}/workspaces", params={"pageSize": 100}, headers=team["outsider"]["headers"]).json()
    assert ws["id"] not in [w["id"] for w in listed["data"]]
    mine = client.get(f"{API}/workspaces", params={"q": ws["name"]}, headers=team["contributor"]["headers"]).json()
    assert mine["data"][0]["myRole"] == "contributor"


def test_private_workspace_needs_an_employee_creator(db, client, company, team):
    """An account without an employee record cannot be a member, so it could not open a private workspace it
    made: refused up front (nothing created). Workspace / public privacy still works for it."""
    account = factories.login_as(db, client, company, role_codes="employee")
    pm.grant_projects(db, account["user_id"])
    name = f"Ghost {factories.tag()}"
    body = {"name": name, "privacy": "private", "departmentId": str(team["dept"]),
            "ownerId": str(team["owner"]["employee_id"])}
    r = client.post(f"{API}/workspaces", json=body, headers=account["headers"])
    assert r.status_code == 422, r.text
    assert r.json()["code"] == "WORKSPACE_CREATOR_NOT_EMPLOYEE" and "privacy" in r.json()["fieldErrors"]
    owner_sees = client.get(f"{API}/workspaces", params={"q": name}, headers=team["owner"]["headers"]).json()
    assert owner_sees["meta"]["total"] == 0
    public = client.post(f"{API}/workspaces", json={**body, "privacy": "public"}, headers=account["headers"])
    assert public.status_code == 201, public.text


def test_member_roles_allow_and_deny(db, client, company, team):
    ws, dept = team["ws"], team["dept"]
    wid = ws["id"]
    newcomer = pm.person(db, client, company, dept)

    # Team leaders cannot manage members; HR can, but cannot make admins; admins can.
    r = client.post(f"{API}/workspaces/{wid}/members", json={"members": [{"employeeId": str(newcomer["employee_id"])}]},
                    headers=team["lead"]["headers"])
    assert r.status_code == 403
    r = client.post(f"{API}/workspaces/{wid}/members",
                    json={"members": [{"employeeId": str(newcomer["employee_id"]), "memberRole": "workspace_admin"}]},
                    headers=team["hr"]["headers"])
    assert r.status_code == 403
    r = client.post(f"{API}/workspaces/{wid}/members", json={"members": [{"employeeId": str(newcomer["employee_id"])}]},
                    headers=team["hr"]["headers"])
    assert r.status_code == 200 and str(newcomer["employee_id"]) in [m["employeeId"] for m in r.json()["data"]]
    r = client.patch(f"{API}/workspaces/{wid}/members/{newcomer['employee_id']}", json={"memberRole": "team_leader"},
                     headers=team["owner"]["headers"])
    assert {m["employeeId"]: m["memberRole"] for m in r.json()["data"]}[str(newcomer["employee_id"])] == "team_leader"
    owner_out = client.delete(f"{API}/workspaces/{wid}/members/{team['owner']['employee_id']}",
                              headers=team["owner"]["headers"])
    assert owner_out.status_code == 409
    assert client.delete(f"{API}/workspaces/{wid}/members/{newcomer['employee_id']}",
                         headers=team["hr"]["headers"]).status_code == 204

    # Settings: admins and HR edit; managers do not; only an admin deletes the workspace.
    current = client.get(f"{API}/workspaces/{wid}", headers=team["owner"]["headers"]).json()["data"]
    body = {"name": current["name"], "privacy": "private", "departmentId": str(dept),
            "ownerId": str(team["owner"]["employee_id"]), "rowVersion": current["rowVersion"]}
    assert client.put(f"{API}/workspaces/{wid}", json=body, headers=team["manager"]["headers"]).status_code == 403
    edited = client.put(f"{API}/workspaces/{wid}", json={**body, "description": "Now described"},
                        headers=team["hr"]["headers"])
    assert edited.status_code == 200 and edited.json()["data"]["description"] == "Now described"
    rv = edited.json()["data"]["rowVersion"]
    assert client.delete(f"{API}/workspaces/{wid}", params={"rowVersion": rv},
                         headers=team["hr"]["headers"]).status_code == 403

    # Folders and lists: managers and above.
    r = client.post(f"{API}/workspaces/{wid}/folders", json={"name": "Plans"}, headers=team["lead"]["headers"])
    assert r.status_code == 403
    folder = client.post(f"{API}/workspaces/{wid}/folders", json={"name": "Plans"}, headers=team["manager"]["headers"])
    assert folder.status_code == 201
    lst = client.post(f"{API}/workspaces/{wid}/lists", json={"name": "Sprint list", "folderId": folder.json()["data"]["id"],
                                                             "priority": "high", "color": "#7127EA"},
                      headers=team["manager"]["headers"])
    assert lst.status_code == 201 and lst.json()["data"]["progressPercent"] == 0
    dup = client.post(f"{API}/workspaces/{wid}/lists", json={"name": "Sprint list"}, headers=team["manager"]["headers"])
    assert dup.status_code == 409 and dup.json()["code"] == "LIST_DUPLICATE"


def test_statuses_features_and_row_versions(client, team):
    owner = team["owner"]
    ws = pm.workspace(client, owner["headers"], team["dept"], owner["employee_id"], privacy="workspace")
    wid, rv = ws["id"], ws["rowVersion"]
    statuses = [{"id": s["id"], "name": s["name"], "color": s["color"], "statusGroup": s["statusGroup"]}
                for s in ws["statuses"]]
    statuses.insert(2, {"name": "Review", "statusGroup": "active"})
    r = client.put(f"{API}/workspaces/{wid}/statuses", json={"statuses": statuses, "rowVersion": rv},
                   headers=owner["headers"])
    assert r.status_code == 200 and "Review" in [s["name"] for s in r.json()["data"]["statuses"]]
    stale = client.put(f"{API}/workspaces/{wid}/statuses", json={"statuses": statuses, "rowVersion": rv},
                       headers=owner["headers"])
    assert stale.status_code == 409

    # A status in use cannot be removed.
    ws = r.json()["data"]
    pm.task(client, owner["headers"], wid, statusId=pm.status_id(ws, "not_started"))
    keep = [{"id": s["id"], "name": s["name"], "statusGroup": s["statusGroup"]} for s in ws["statuses"]
            if s["statusGroup"] != "not_started"] + [{"name": "Fresh", "statusGroup": "not_started"}]
    used = client.put(f"{API}/workspaces/{wid}/statuses", json={"statuses": keep, "rowVersion": ws["rowVersion"]},
                      headers=owner["headers"])
    assert used.status_code == 409 and used.json()["code"] == "STATUS_IN_USE"

    r = client.put(f"{API}/workspaces/{wid}/features", json={"features": [{"featureCode": "priority"}],
                                                              "rowVersion": ws["rowVersion"]}, headers=owner["headers"])
    assert [f["featureCode"] for f in r.json()["data"]["features"]] == ["priority"]
    # Tags are now off: creating one is refused.
    off = client.post(f"{API}/workspaces/{wid}/tags", json={"name": "Bug"}, headers=owner["headers"])
    assert off.status_code == 409 and off.json()["code"] == "FEATURE_OFF"


def test_custom_fields_and_column_permissions(client, team):
    owner, lead, contributor = team["owner"], team["lead"], team["contributor"]
    wid = team["ws"]["id"]
    bad = client.post(f"{API}/workspaces/{wid}/custom-fields", json={"name": "Stage", "fieldType": "dropdown"},
                      headers=owner["headers"])
    assert bad.status_code == 422 and "config" in bad.json()["fieldErrors"]
    assert client.post(f"{API}/workspaces/{wid}/custom-fields", json={"name": "Budget", "fieldType": "number"},
                       headers=lead["headers"]).status_code == 403
    stage = client.post(f"{API}/workspaces/{wid}/custom-fields",
                        json={"name": "Stage", "fieldType": "dropdown", "config": {"options": ["Draft", "Final"]}},
                        headers=owner["headers"]).json()["data"]
    assert stage["config"]["options"] == ["Draft", "Final"]
    dup = client.post(f"{API}/workspaces/{wid}/custom-fields", json={"name": "Stage", "fieldType": "text"},
                      headers=owner["headers"])
    assert dup.status_code == 409 and dup.json()["code"] == "FIELD_DUPLICATE"

    task = pm.task(client, lead["headers"], wid, assigneeIds=[str(contributor["employee_id"])])
    ok = client.put(f"{API}/tasks/{task['id']}/fields/{stage['id']}", json={"value": "Draft"}, headers=lead["headers"])
    assert ok.status_code == 200 and ok.json()["data"]["fieldValues"] == [{"customFieldId": stage["id"], "fieldValue": "Draft"}]
    wrong = client.put(f"{API}/tasks/{task['id']}/fields/{stage['id']}", json={"value": "Other"}, headers=lead["headers"])
    assert wrong.status_code == 422

    # Due date: read-only for team leaders; the custom field: private for contributors.
    r = client.put(f"{API}/workspaces/{wid}/column-permissions/due_date",
                   json={"roles": [{"memberRole": "team_leader", "permissionLevel": "can_view"}]}, headers=lead["headers"])
    assert r.status_code == 403
    r = client.put(f"{API}/workspaces/{wid}/column-permissions/due_date",
                   json={"roles": [{"memberRole": "team_leader", "permissionLevel": "can_view"}]}, headers=owner["headers"])
    assert r.status_code == 200 and r.json()["data"]["columns"][0]["roles"][0]["permissionLevel"] == "can_view"
    client.put(f"{API}/workspaces/{wid}/column-permissions/cf_{stage['id']}", json={"defaultLevel": "private"},
               headers=owner["headers"])

    fresh = client.get(f"{API}/tasks/{task['id']}", headers=lead["headers"]).json()["data"]
    edit = {"name": fresh["name"], "dueDate": "2030-01-31", "rowVersion": fresh["rowVersion"]}
    refused = client.put(f"{API}/tasks/{task['id']}", json=edit, headers=lead["headers"])
    assert refused.status_code == 403
    assert client.put(f"{API}/tasks/{task['id']}", json=edit, headers=owner["headers"]).status_code == 200
    seen = client.get(f"{API}/tasks/{task['id']}", headers=contributor["headers"]).json()["data"]
    assert f"cf_{stage['id']}" in seen["hiddenColumns"] and seen["fieldValues"] == []
    assert client.get(f"{API}/tasks/{task['id']}", headers=owner["headers"]).json()["data"]["fieldValues"]


def test_views_favorites_and_tags(client, team):
    owner, contributor = team["owner"], team["contributor"]
    wid = team["ws"]["id"]
    mine = client.post(f"{API}/workspaces/{wid}/views", json={"viewType": "list", "name": "My urgent", "isPrivate": True,
                                                              "config": {"filters": {"priorities": ["urgent"]}}},
                       headers=contributor["headers"])
    assert mine.status_code == 201 and mine.json()["data"]["config"]["filters"]["priorities"] == ["urgent"]
    shared = client.post(f"{API}/workspaces/{wid}/views", json={"viewType": "board", "name": "Team board"},
                         headers=contributor["headers"])
    assert shared.status_code == 403
    owner_views = client.get(f"{API}/workspaces/{wid}/views", headers=owner["headers"]).json()["data"]
    assert "My urgent" not in [v["name"] for v in owner_views]
    lst = next(v for v in owner_views if v["viewType"] == "list")
    assert client.delete(f"{API}/views/{lst['id']}", params={"rowVersion": lst["rowVersion"]},
                         headers=owner["headers"]).status_code == 409

    assert client.put(f"{API}/favorites", json={"entityType": "workspace", "entityId": int(wid)},
                      headers=contributor["headers"]).status_code == 204
    favs = client.get(f"{API}/favorites", headers=contributor["headers"]).json()["data"]
    assert [f["entityId"] for f in favs] == [wid]
    only = client.get(f"{API}/workspaces", params={"favorites": True}, headers=contributor["headers"]).json()
    assert [w["id"] for w in only["data"]] == [wid] and only["data"][0]["isFavorite"] is True

    tag = client.post(f"{API}/workspaces/{wid}/tags", json={"name": "Bug Issue", "color": "#DC3545"},
                      headers=team["lead"]["headers"])
    assert tag.status_code == 201
    assert client.post(f"{API}/workspaces/{wid}/tags", json={"name": "Revamp"},
                       headers=contributor["headers"]).status_code == 403
    dup = client.post(f"{API}/workspaces/{wid}/tags", json={"name": "bug issue"}, headers=owner["headers"])
    assert dup.status_code == 409 and dup.json()["code"] == "TAG_DUPLICATE"


def test_company_permission_refusal(db, client, company, team):
    # A signed-in user whose roles hold no projects codes (a Recruiter) cannot edit tasks.
    plain = pm.person(db, client, company, team["dept"], role_codes="recruiter", grant=False)
    task = pm.task(client, team["owner"]["headers"], team["ws"]["id"])
    r = client.put(f"{API}/tasks/{task['id']}", json={"name": "x", "rowVersion": task["rowVersion"]},
                   headers=plain["headers"])
    assert r.status_code == 403 and r.json()["code"] == "FORBIDDEN"
    assert client.delete(f"{API}/workspaces/{team['ws']['id']}", params={"rowVersion": task["rowVersion"]},
                         headers=plain["headers"]).status_code == 403

    # Another company's workspace is not found.
    other = factories.company(db)
    stranger = pm.person(db, client, other)
    assert client.get(f"{API}/workspaces/{team['ws']['id']}", headers=stranger["headers"]).status_code == 404


def test_delete_workspace(client, team):
    owner = team["owner"]
    ws = pm.workspace(client, owner["headers"], team["dept"], owner["employee_id"], privacy="workspace")
    parent = pm.task(client, owner["headers"], ws["id"])
    pm.task(client, owner["headers"], ws["id"], parentTaskId=parent["id"])
    client.post(f"{API}/tasks/{parent['id']}/comments", json={"body": "Bye"}, headers=owner["headers"])
    assert client.delete(f"{API}/workspaces/{ws['id']}", params={"rowVersion": "0000000000000000"},
                         headers=owner["headers"]).status_code == 409
    assert client.delete(f"{API}/workspaces/{ws['id']}", params={"rowVersion": ws["rowVersion"]},
                         headers=owner["headers"]).status_code == 204
    assert client.get(f"{API}/workspaces/{ws['id']}", headers=owner["headers"]).status_code == 404
    assert client.get(f"{API}/tasks/{parent['id']}", headers=owner["headers"]).status_code == 404
