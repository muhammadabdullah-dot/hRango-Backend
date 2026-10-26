"""Assets: asset types, company assets with history, allocations, permissions and scope."""
from tests import factories
from tests import factories_events as fe
from tests import factories_offboarding as fo


def test_asset_type_lifecycle(client, admin):
    h = admin["headers"]
    name = f"Laptop {factories.tag()}"
    r = client.post("/api/assets/types", json={"name": name, "description": "Portable computers"}, headers=h)
    assert r.status_code == 201, r.text
    t = r.json()["data"]
    assert t["code"].startswith("AITP-") and t["isActive"] is True and t["assetCount"] == 0

    dup = client.post("/api/assets/types", json={"name": name}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "ASSET_TYPE_DUPLICATE"
    assert client.post("/api/assets/types", json={"name": ""}, headers=h).status_code == 422

    page = client.get("/api/assets/types", params={"q": name}, headers=h).json()
    assert page["meta"]["total"] == 1 and page["data"][0]["id"] == t["id"]

    edited = client.put(f"/api/assets/types/{t['id']}", json={"name": name, "isActive": False,
                                                              "rowVersion": t["rowVersion"]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["isActive"] is False
    stale = client.put(f"/api/assets/types/{t['id']}", json={"name": name, "rowVersion": t["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    # An inactive type takes no new assets.
    r = client.post("/api/assets/company-assets", json={"name": "X", "assetTypeId": t["id"], "assetCondition": "new"},
                    headers=h)
    assert r.status_code == 422 and "assetTypeId" in r.json()["fieldErrors"]

    in_use = fo.asset_type(client, h)
    fo.asset(client, h, in_use["id"])
    in_use = client.get(f"/api/assets/types/{in_use['id']}", headers=h).json()["data"]
    used = client.delete(f"/api/assets/types/{in_use['id']}", params={"rowVersion": in_use["rowVersion"]}, headers=h)
    assert used.status_code == 409 and used.json()["code"] == "ASSET_TYPE_IN_USE"
    assert "Deactivate" in used.json()["message"]
    assert client.delete(f"/api/assets/types/{t['id']}", params={"rowVersion": edited.json()["data"]["rowVersion"]},
                         headers=h).status_code == 204


def test_asset_lifecycle_and_history(client, db, admin):
    h = admin["headers"]
    invoice = factories.upload(client, h, name="Invoice.pdf", module="assets")
    a = fo.asset(client, h, manufacturer="Dell", model="Latitude 5440", fileId=int(invoice["id"]))
    assert a["code"].startswith("AST-") and a["status"] == "active" and a["availability"] == "available"
    assert a["currentValue"] == 150000
    assert a["fileId"] == invoice["id"] and a["file"]["name"] == "Invoice.pdf"
    assert client.get(a["file"]["url"]).content == factories.PDF_BYTES
    elsewhere = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    foreign = factories.upload(client, elsewhere, module="assets")
    bad_file = client.post("/api/assets/company-assets", json={"name": "F", "assetTypeId": a["assetTypeId"],
                                                               "assetCondition": "new", "fileId": int(foreign["id"])},
                           headers=h)
    assert bad_file.status_code == 422 and "fileId" in bad_file.json()["fieldErrors"]

    dup = client.post("/api/assets/company-assets", json={"name": "Copy", "assetTypeId": a["assetTypeId"],
                                                          "assetCondition": "new",
                                                          "identificationNo": a["identificationNo"]}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "ASSET_DUPLICATE"
    bad = client.post("/api/assets/company-assets", json={"name": "Bad", "assetTypeId": a["assetTypeId"],
                                                          "assetCondition": "shiny"}, headers=h)
    assert bad.status_code == 422 and "assetCondition" in bad.json()["fieldErrors"]

    body = {"name": a["name"], "assetTypeId": a["assetTypeId"], "assetCondition": "fair",
            "identificationNo": a["identificationNo"], "currentValue": 120000, "acquiredDate": "2024-01-15",
            "manufacturer": "Dell", "model": "Latitude 5440", "fileId": int(invoice["id"]), "rowVersion": a["rowVersion"]}
    r = client.put(f"/api/assets/company-assets/{a['id']}", json=body, headers=h)
    assert r.status_code == 200, r.text
    a2 = r.json()["data"]
    assert client.put(f"/api/assets/company-assets/{a['id']}", json=body, headers=h).status_code == 409

    off = client.patch(f"/api/assets/company-assets/{a['id']}/deactivate", json={"rowVersion": a2["rowVersion"]},
                       headers=h)
    assert off.status_code == 200 and off.json()["data"]["status"] == "decommissioned"
    assert off.json()["data"]["availability"] == "unavailable"
    on = client.patch(f"/api/assets/company-assets/{a['id']}/activate",
                      json={"rowVersion": off.json()["data"]["rowVersion"]}, headers=h)
    assert on.json()["data"]["status"] == "active"

    history = client.get(f"/api/assets/company-assets/{a['id']}/history", headers=h).json()["data"]
    seen = {(x["action"], x["fieldName"]) for x in history}
    assert {("create", None), ("update", "asset_condition"), ("update", "current_value"),
            ("deactivate", "status"), ("activate", "status")} <= seen

    listed = client.get("/api/assets/company-assets", params={"q": a["identificationNo"]}, headers=h).json()
    assert listed["meta"]["total"] == 1
    assert client.delete(f"/api/assets/company-assets/{a['id']}", params={"rowVersion": on.json()["data"]["rowVersion"]},
                         headers=h).status_code == 204


def test_allocation_rules(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company, first_name="Asma")
    factories.user(db, company, employee_id=emp, role_codes="employee")
    other = factories.employee(db, company)
    a = fo.asset(client, h)

    receipt = factories.upload(client, h, name="Handover.pdf", module="assets")
    al = fo.allocate(client, h, a["id"], emp, on="2024-02-01", fileId=int(receipt["id"]))
    assert al["status"] == "allocated" and al["employeeName"].startswith("Asma") and al["deallocatedOn"] is None
    assert al["file"]["id"] == receipt["id"] and al["file"]["name"] == "Handover.pdf"
    allocated = fe.events(db, company, "assets.allocated", int(al["id"]))
    assert len(allocated) == 1 and allocated[0]["data"]["employeeId"] == str(emp)
    assert allocated[0]["data"]["assetCode"] == a["code"]
    told = fe.notifications(db, company, emp, "sep.asset_allocation", int(al["id"]))
    assert len(told) == 1 and told[0]["title"].startswith("An asset was handed to you")
    held = client.get(f"/api/assets/company-assets/{a['id']}", headers=h).json()["data"]
    assert held["availability"] == "allocated" and held["holderId"] == str(emp)

    again = client.post("/api/assets/allocations", json={"assetId": a["id"], "employeeId": str(other),
                                                         "allocatedOn": "2024-03-01"}, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "ASSET_ALLOCATED"
    assert client.patch(f"/api/assets/company-assets/{a['id']}/deactivate", json={"rowVersion": held["rowVersion"]},
                        headers=h).json()["code"] == "ASSET_ALLOCATED"
    assert client.delete(f"/api/assets/company-assets/{a['id']}", params={"rowVersion": held["rowVersion"]},
                         headers=h).status_code == 409
    early = client.post("/api/assets/allocations", json={"assetId": fo.asset(client, h)["id"], "employeeId": str(emp),
                                                         "allocatedOn": "2023-01-01"}, headers=h)
    assert early.status_code == 422 and "allocatedOn" in early.json()["fieldErrors"]

    before = client.patch(f"/api/assets/allocations/{al['id']}/deallocate",
                          json={"deallocatedOn": "2024-01-01", "rowVersion": al["rowVersion"]}, headers=h)
    assert before.status_code == 422 and "deallocatedOn" in before.json()["fieldErrors"]
    back = client.patch(f"/api/assets/allocations/{al['id']}/deallocate",
                        json={"deallocatedOn": "2024-06-30", "returnCondition": "damaged", "remarks": "Cracked screen",
                              "rowVersion": al["rowVersion"]}, headers=h)
    assert back.status_code == 200, back.text
    assert back.json()["data"]["status"] == "deallocated" and back.json()["data"]["returnCondition"] == "damaged"
    returned = fe.events(db, company, "assets.returned", int(al["id"]))
    assert len(returned) == 1 and returned[0]["data"]["returnCondition"] == "damaged"
    assert returned[0]["data"]["deallocatedOn"] == "2024-06-30"
    assert len(fe.notifications(db, company, emp, "sep.asset_allocation", int(al["id"]))) == 2
    stale = client.patch(f"/api/assets/allocations/{al['id']}/deallocate",
                         json={"deallocatedOn": "2024-06-30", "rowVersion": al["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    damaged = client.get(f"/api/assets/company-assets/{a['id']}", headers=h).json()["data"]
    assert damaged["status"] == "damaged" and damaged["availability"] == "unavailable"
    refused = client.post("/api/assets/allocations", json={"assetId": a["id"], "employeeId": str(other),
                                                           "allocatedOn": "2024-07-01"}, headers=h)
    assert refused.status_code == 409 and refused.json()["code"] == "ASSET_UNAVAILABLE"

    left = factories.employee(db, company)
    cur = db.conn.cursor()
    cur.execute("UPDATE hr.employee SET status = N'left' WHERE id = ?", left)
    cur.close()
    gone = client.post("/api/assets/allocations", json={"assetId": fo.asset(client, h)["id"], "employeeId": str(left),
                                                        "allocatedOn": "2024-07-01"}, headers=h)
    assert gone.status_code == 422 and "employeeId" in gone.json()["fieldErrors"]

    page = client.get("/api/assets/allocations", params={"employeeId": str(emp), "status": "deallocated"},
                      headers=h).json()
    assert page["meta"]["total"] == 1 and page["data"][0]["id"] == al["id"]
    history = client.get(f"/api/assets/company-assets/{a['id']}/history", headers=h).json()["data"]
    assert {"allocate", "deallocate"} <= {x["action"] for x in history}


def test_permissions_and_scope(client, db, company, admin):
    h = admin["headers"]
    manager = factories.employee(db, company, first_name="Manager")
    report = factories.employee(db, company, line_manager_id=manager)
    stranger = factories.employee(db, company)
    mine = fo.allocate(client, h, fo.asset(client, h)["id"], report)
    theirs = fo.allocate(client, h, fo.asset(client, h)["id"], stranger)

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=report)
    sh = staff["headers"]
    own = client.get("/api/assets/allocations", headers=sh).json()
    assert [x["id"] for x in own["data"]] == [mine["id"]]
    assert client.get(f"/api/assets/allocations/{theirs['id']}", headers=sh).status_code == 404
    # Own scope does not reach company records, and allocating is not an employee action.
    assert client.post("/api/assets/types", json={"name": f"Mine {factories.tag()}"}, headers=sh).status_code == 403
    assert client.get("/api/assets/company-assets", headers=sh).status_code == 403
    assert client.post("/api/assets/allocations", json={"assetId": fo.asset(client, h)["id"], "employeeId": str(report),
                                                        "allocatedOn": "2024-02-01"}, headers=sh).status_code == 403

    boss = factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)
    team = client.get("/api/assets/allocations", headers=boss["headers"]).json()
    assert {x["id"] for x in team["data"]} == {mine["id"]}
    assert client.get(f"/api/assets/allocations/{theirs['id']}", headers=boss["headers"]).status_code == 404

    nobody = factories.login_as(db, client, company)
    assert client.get("/api/assets/allocations", headers=nobody["headers"]).status_code == 403


def test_other_company_cannot_see(client, db, admin):
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    a = fo.asset(client, admin["headers"])
    assert client.get(f"/api/assets/company-assets/{a['id']}", headers=other_admin["headers"]).status_code == 404
    r = client.post("/api/assets/company-assets", json={"name": "X", "assetTypeId": a["assetTypeId"],
                                                        "assetCondition": "new"}, headers=other_admin["headers"])
    assert r.status_code == 422 and "assetTypeId" in r.json()["fieldErrors"]
