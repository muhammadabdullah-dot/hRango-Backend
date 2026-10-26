"""The worked example: every layer, the envelopes, field errors, row versions and the audit log."""
from tests import factories


def test_department_lifecycle(client, db, company, admin):
    h = admin["headers"]
    head = factories.employee(db, company, first_name="Hina", last_name="Raza")
    name = f"People {factories.tag()}"

    r = client.post("/api/organisation/departments", json={"name": name, "headId": str(head)}, headers=h)
    assert r.status_code == 201, r.text
    dept = r.json()["data"]
    assert dept["headName"] == "Hina Raza" and isinstance(dept["id"], str)

    child = client.post("/api/organisation/departments", json={"name": f"{name} Hiring", "parentId": dept["id"]},
                        headers=h).json()["data"]

    dup = client.post("/api/organisation/departments", json={"name": name.upper()}, headers=h)
    assert dup.status_code == 409
    assert dup.json()["code"] == "DEPARTMENT_DUPLICATE" and "name" in dup.json()["fieldErrors"]

    blank = client.post("/api/organisation/departments", json={"name": ""}, headers=h)
    assert blank.status_code == 422 and "name" in blank.json()["fieldErrors"]

    page = client.get("/api/organisation/departments", params={"q": name, "pageSize": 1}, headers=h).json()
    assert page["meta"] == {"page": 1, "pageSize": 1, "total": 2, "totalPages": 2}

    loop = client.put(f"/api/organisation/departments/{dept['id']}",
                      json={"name": name, "parentId": child["id"], "rowVersion": dept["rowVersion"]}, headers=h)
    assert loop.status_code == 422 and "parentId" in loop.json()["fieldErrors"]

    renamed = client.put(f"/api/organisation/departments/{dept['id']}",
                         json={"name": f"{name} 2", "rowVersion": dept["rowVersion"]}, headers=h)
    assert renamed.status_code == 200
    stale = client.put(f"/api/organisation/departments/{dept['id']}",
                       json={"name": "x", "rowVersion": dept["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    blocked = client.delete(f"/api/organisation/departments/{dept['id']}",
                            params={"rowVersion": renamed.json()["data"]["rowVersion"]}, headers=h)
    assert blocked.status_code == 409
    assert client.delete(f"/api/organisation/departments/{child['id']}", params={"rowVersion": child["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"/api/organisation/departments/{child['id']}", headers=h).status_code == 404

    cur = db.conn.cursor()
    actions = [r.action_name for r in cur.execute(
        "SELECT action_name FROM core.audit_log WHERE entity_type = N'org.department' AND entity_id = ? ORDER BY id",
        int(dept["id"])).fetchall()]
    cur.close()
    assert actions == ["create", "update", "update"]  # name and head_id changed


def test_other_company_cannot_see(client, db, admin):
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    mine = client.post("/api/organisation/departments", json={"name": f"Mine {factories.tag()}"},
                       headers=admin["headers"]).json()["data"]
    r = client.get(f"/api/organisation/departments/{mine['id']}", headers=other_admin["headers"])
    assert r.status_code == 404
    # Switching to a company the user does not belong to is refused.
    r = client.get("/api/organisation/departments", headers={**admin["headers"], "X-Company-Id": str(other)})
    assert r.status_code == 403
