"""Project management test helpers: signed-in employees and workspaces made through the wizard.

Company roles only open the module; inside a workspace the workspace role decides. Until the default
Employee role holds the projects codes (see comparison/08-projects.md), these helpers give each test
user every projects code as a personal grant, as the Employee role is meant to.
"""
from tests import factories


def grant_projects(db, user_id: int) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute("INSERT auth.user_permission_override (company_id, user_account_id, permission_id, effect, scope, "
                    "reason) SELECT u.company_id, u.id, p.id, N'grant', N'own', N'test' FROM auth.permission p "
                    "JOIN auth.user_account u ON u.id = ? WHERE p.module = N'projects' "
                    "AND NOT EXISTS (SELECT 1 FROM auth.user_permission_override o "
                    "WHERE o.user_account_id = u.id AND o.company_id = u.company_id AND o.permission_id = p.id)", user_id)
    finally:
        cur.close()


def person(db, client, company: int, department_id: int | None = None, first_name: str = "Pm",
           role_codes: str = "employee", grant: bool = True) -> dict:
    """An employee with a sign-in: {"employee_id", "user_id", "headers", ...}."""
    employee_id = factories.employee(db, company, department_id=department_id, first_name=first_name)
    user = factories.login_as(db, client, company, role_codes=role_codes, employee_id=employee_id)
    if grant:
        grant_projects(db, user["user_id"])
    return {**user, "employee_id": employee_id}


def workspace(client, headers: dict, department_id: int, owner_id: int, members: list[tuple[int, str]] = (),
              privacy: str = "private", **extra) -> dict:
    body = {"name": f"Workspace {factories.tag()}", "privacy": privacy, "departmentId": str(department_id),
            "ownerId": str(owner_id),
            "members": [{"employeeId": str(e), "memberRole": r} for e, r in members], **extra}
    r = client.post("/api/projects/workspaces", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def status_id(ws: dict, group: str, index: int = 0) -> str:
    return [s for s in ws["statuses"] if s["statusGroup"] == group][index]["id"]


def task(client, headers: dict, workspace_id: str, name: str | None = None, **extra) -> dict:
    r = client.post("/api/projects/tasks", json={"workspaceId": workspace_id, "name": name or f"Task {factories.tag()}",
                                                 **extra}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]
