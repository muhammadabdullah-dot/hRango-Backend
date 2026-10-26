"""Control Panel: general settings, companies, locations, areas, branches, job titles, simple masters,
announcements and the picker lists."""
from tests import factories
from tests import factories_organisation as fo


def _general(name: str, **extra) -> dict:
    return {"organizationName": name, "legalName": f"{name} (Private) Limited", "email": "hr@example.com",
            "phone": "+92 42 1234567", "website": "https://example.com", "address": "Gulberg, Lahore",
            "timezone": "Asia/Karachi", "currency": "PKR", "dateFormat": "dd/MM/yyyy", "weekStartsOn": "monday",
            "fiscalYearStartMonth": 7, **extra}


def test_general_settings(client, db):
    company = factories.company(db)
    h = factories.login_as(db, client, company, role_codes="company_admin")["headers"]

    current = client.get("/api/organisation/general", headers=h)
    assert current.status_code == 200, current.text
    g = current.json()["data"]
    assert g["id"] == str(company) and g["currency"] == "PKR" and g["fiscalYearStartMonth"] == 7

    name = f"Top Edge {factories.tag()}"
    pk = next(c for c in client.get("/api/organisation/geo/countries", params={"q": "Pakistan"},
                                    headers=h).json()["data"] if c["code"] == "PK")
    saved = client.put("/api/organisation/general", headers=h,
                       json=_general(name, countryId=pk["id"], rowVersion=g["rowVersion"]))
    assert saved.status_code == 200, saved.text
    assert saved.json()["data"]["organizationName"] == name and saved.json()["data"]["countryName"] == "Pakistan"

    stale = client.put("/api/organisation/general", headers=h, json=_general(name, rowVersion=g["rowVersion"]))
    assert stale.status_code == 409

    bad = client.put("/api/organisation/general", headers=h,
                     json=_general(name, currency="rupees", rowVersion=saved.json()["data"]["rowVersion"]))
    assert bad.status_code == 422 and "currency" in bad.json()["fieldErrors"]
    bad_tz = client.put("/api/organisation/general", headers=h,
                        json=_general(name, timezone="karachi", rowVersion=saved.json()["data"]["rowVersion"]))
    assert bad_tz.status_code == 422 and "timezone" in bad_tz.json()["fieldErrors"]

    # An HR Officer holds no organisation.* permission.
    officer = factories.login_as(db, client, company, role_codes="hr_officer")["headers"]
    assert client.get("/api/organisation/general", headers=officer).status_code == 403


def test_create_company_and_switch(client, db):
    home = factories.company(db)
    admin = factories.login_as(db, client, home, role_codes="company_admin")
    h = admin["headers"]
    name = f"Top Edge FZ-LLC {factories.tag()}"

    r = client.post("/api/organisation/companies", headers=h,
                    json=_general(name, timezone="Asia/Dubai", currency="AED", fiscalYearStartMonth=1))
    assert r.status_code == 201, r.text
    new_id = r.json()["data"]["id"]

    mine = client.get("/api/organisation/lookups/companies", headers=h).json()["data"]
    assert {c["id"] for c in mine} == {str(home), new_id}
    assert next(c for c in mine if c["id"] == str(home))["isCurrent"]

    # The creator is the new company's administrator, with its default roles and employment types.
    there = client.get("/api/organisation/general", headers={**h, "X-Company-Id": new_id})
    assert there.status_code == 200 and there.json()["data"]["currency"] == "AED"
    types = client.get("/api/organisation/lookups/employment-types", headers={**h, "X-Company-Id": new_id}).json()["data"]
    assert {t["name"] for t in types} == {"Permanent", "Contractual", "Daily Wager", "Management Trainee"}

    dup = client.post("/api/organisation/companies", headers=h, json=_general(name.upper()))
    assert dup.status_code == 409 and dup.json()["code"] == "COMPANY_DUPLICATE"

    # Someone else cannot read it.
    stranger = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    assert client.get(f"/api/organisation/companies/{new_id}", headers=stranger).status_code == 404


def test_location_area_branch(client, db, company, admin):
    h = admin["headers"]
    loc = client.post("/api/organisation/locations", headers=h,
                      json={"name": f"Lahore {factories.tag()}", "employeePrefix": "LHR", "latitude": 31.5204,
                            "longitude": 74.3587}).json()["data"]
    other_loc = client.post("/api/organisation/locations", headers=h,
                            json={"name": f"Karachi {factories.tag()}"}).json()["data"]
    assert loc["latitude"] == 31.5204 and loc["companyName"]

    half = client.post("/api/organisation/locations", headers=h, json={"name": f"X {factories.tag()}", "latitude": 1})
    assert half.status_code == 422 and "longitude" in half.json()["fieldErrors"]

    area = client.post("/api/organisation/areas", headers=h,
                       json={"name": "Gulberg", "locationId": loc["id"]}).json()["data"]
    assert area["locationName"] == loc["name"]
    dup_area = client.post("/api/organisation/areas", headers=h, json={"name": "gulberg", "locationId": loc["id"]})
    assert dup_area.status_code == 409 and dup_area.json()["code"] == "AREA_DUPLICATE"

    pk_states = client.get("/api/organisation/geo/states", params={"country": "PK"}, headers=h).json()["data"]
    punjab = next(s for s in pk_states if s["code"] == "PK-PB")
    sindh = next(s for s in pk_states if s["code"] == "PK-SD")
    lahore = next(c for c in client.get("/api/organisation/geo/cities", params={"state": "PK-PB"},
                                        headers=h).json()["data"] if c["name"] == "Lahore")
    pk_id = punjab["countryId"]
    assert any(s["code"] == "AE-DU" for s in client.get("/api/organisation/geo/states", params={"country": "AE"},
                                                         headers=h).json()["data"])

    body = {"name": f"Main Boulevard {factories.tag()}", "employeePrefix": "MB", "locationId": loc["id"],
            "areaId": area["id"], "countryId": pk_id, "stateId": punjab["id"], "cityId": lahore["id"]}
    wrong_area = client.post("/api/organisation/branches", headers=h, json={**body, "locationId": other_loc["id"]})
    assert wrong_area.status_code == 422 and "areaId" in wrong_area.json()["fieldErrors"]
    wrong_city = client.post("/api/organisation/branches", headers=h, json={**body, "stateId": sindh["id"]})
    assert wrong_city.status_code == 422 and "cityId" in wrong_city.json()["fieldErrors"]

    branch = client.post("/api/organisation/branches", headers=h, json=body)
    assert branch.status_code == 201, branch.text
    b = branch.json()["data"]
    assert b["cityName"] == "Lahore" and b["stateCode"] == "PK-PB" and b["areaName"] == "Gulberg"

    listed = client.get("/api/organisation/branches", params={"locationId": loc["id"]}, headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["id"] == b["id"]
    picker = client.get("/api/organisation/lookups/branches", params={"parentId": loc["id"]}, headers=h).json()["data"]
    assert [p["name"] for p in picker] == [b["name"]]

    blocked = client.delete(f"/api/organisation/locations/{loc['id']}", params={"rowVersion": loc["rowVersion"]},
                            headers=h)
    assert blocked.status_code == 409
    moved = client.put(f"/api/organisation/areas/{area['id']}", headers=h,
                       json={"name": "Gulberg", "locationId": other_loc["id"], "rowVersion": area["rowVersion"]})
    assert moved.status_code == 409 and "locationId" in moved.json()["fieldErrors"]

    renamed = client.put(f"/api/organisation/branches/{b['id']}", headers=h,
                         json={**body, "name": b["name"] + " 2", "rowVersion": b["rowVersion"]})
    assert renamed.status_code == 200
    stale = client.put(f"/api/organisation/branches/{b['id']}", headers=h, json={**body, "rowVersion": b["rowVersion"]})
    assert stale.status_code == 409
    gone = client.delete(f"/api/organisation/branches/{b['id']}",
                         params={"rowVersion": renamed.json()["data"]["rowVersion"]}, headers=h)
    assert gone.status_code == 204

    other_admin = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    assert client.get(f"/api/organisation/locations/{loc['id']}", headers=other_admin).status_code == 404


def test_job_title_head_count(client, db, company, admin):
    h = admin["headers"]
    no_max = client.post("/api/organisation/job-titles", headers=h,
                         json={"name": f"Lead {factories.tag()}", "limitHeadCount": True})
    assert no_max.status_code == 422 and "maxHeadCount" in no_max.json()["fieldErrors"]

    jt = client.post("/api/organisation/job-titles", headers=h,
                     json={"name": f"Lead {factories.tag()}", "limitHeadCount": True, "maxHeadCount": 1}).json()["data"]
    assert jt["headCount"] == 0
    branch = factories.branch(db, company)
    first = client.post("/api/employees", headers=h, json={"firstName": "Ali", "lastName": "Khan", "branchId": branch,
                                                            "jobTitleId": jt["id"], "joiningDate": "2026-01-05"})
    assert first.status_code == 201, first.text
    second = client.post("/api/employees", headers=h, json={"firstName": "Sara", "lastName": "Ahmed",
                                                             "branchId": branch, "jobTitleId": jt["id"],
                                                             "joiningDate": "2026-01-05"})
    assert second.status_code == 409 and second.json()["code"] == "JOB_TITLE_FULL"

    full = client.get(f"/api/organisation/job-titles/{jt['id']}", headers=h).json()["data"]
    assert full["headCount"] == 1
    off = client.put(f"/api/organisation/job-titles/{jt['id']}", headers=h,
                     json={"name": jt["name"], "limitHeadCount": False, "maxHeadCount": 5,
                           "rowVersion": full["rowVersion"]})
    assert off.status_code == 200 and off.json()["data"]["maxHeadCount"] is None
    in_use = client.delete(f"/api/organisation/job-titles/{jt['id']}",
                           params={"rowVersion": off.json()["data"]["rowVersion"]}, headers=h)
    assert in_use.status_code == 409


def test_simple_masters(client, db, admin):
    h = admin["headers"]
    for segment in ("divisions", "cost-centers", "designations", "grades", "job-levels", "employee-groups",
                    "employment-types"):
        body = {"name": f"{segment} {factories.tag()}", "code": f"C{factories.tag()[:6]}", "sortOrder": 3}
        created = client.post(f"/api/organisation/{segment}", headers=h, json=body)
        assert created.status_code == 201, (segment, created.text)
        item = created.json()["data"]
        assert item["employeeCount"] == 0

        dup = client.post(f"/api/organisation/{segment}", headers=h, json={**body, "code": "OTHER"})
        assert dup.status_code == 409 and "name" in dup.json()["fieldErrors"], segment

        page = client.get(f"/api/organisation/{segment}", params={"q": body["name"]}, headers=h).json()
        assert page["meta"]["total"] == 1, segment

        edited = client.put(f"/api/organisation/{segment}/{item['id']}", headers=h,
                            json={**body, "name": body["name"] + " x", "rowVersion": item["rowVersion"]})
        assert edited.status_code == 200, segment
        stale = client.put(f"/api/organisation/{segment}/{item['id']}", headers=h,
                           json={**body, "rowVersion": item["rowVersion"]})
        assert stale.status_code == 409, segment
        assert client.delete(f"/api/organisation/{segment}/{item['id']}", headers=h,
                             params={"rowVersion": edited.json()["data"]["rowVersion"]}).status_code == 204

    no_code = client.post("/api/organisation/cost-centers", headers=h, json={"name": f"CC {factories.tag()}"})
    assert no_code.status_code == 422 and "code" in no_code.json()["fieldErrors"]
    grade = client.post("/api/organisation/grades", headers=h, json={"name": f"G {factories.tag()}", "sortOrder": 2})
    assert grade.json()["data"]["sortOrder"] == 2


def test_permissions_and_lookups(client, db, company):
    emp = factories.employee(db, company)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)["headers"]
    assert client.post("/api/organisation/locations", headers=staff, json={"name": "Nope"}).status_code == 403
    assert client.get("/api/organisation/designations", headers=staff).status_code == 403
    # Picker lists are open to any signed-in user.
    assert client.get("/api/organisation/lookups/departments", headers=staff).status_code == 200
    assert client.get("/api/organisation/lookups/nonsense", headers=staff).status_code == 404
    assert client.get("/api/organisation/geo/countries", headers=staff).status_code == 200
    assert client.get("/api/organisation/lookups/departments").status_code == 401


def test_announcements(client, db, company, admin):
    h = admin["headers"]
    event = client.post("/api/organisation/announcements", headers=h, json={"kind": "event", "title": "Iftar dinner"})
    assert event.status_code == 422 and "eventDate" in event.json()["fieldErrors"]
    notice = client.post("/api/organisation/announcements", headers=h,
                         json={"kind": "notice", "title": f"Office timings changed {factories.tag()}",
                               "body": "From Monday the office opens at 9."})
    assert notice.status_code == 201, notice.text
    n = notice.json()["data"]
    current = client.get("/api/organisation/announcements", params={"currentOnly": True, "q": n["title"]},
                         headers=h).json()
    assert current["meta"]["total"] == 1
    edited = client.put(f"/api/organisation/announcements/{n['id']}", headers=h,
                        json={"kind": "notice", "title": n["title"], "publishFrom": "2020-01-01",
                              "publishTo": "2020-01-31", "rowVersion": n["rowVersion"]})
    assert edited.status_code == 200
    assert client.get("/api/organisation/announcements", params={"currentOnly": True, "q": n["title"]},
                      headers=h).json()["meta"]["total"] == 0
    assert client.delete(f"/api/organisation/announcements/{n['id']}", headers=h,
                         params={"rowVersion": edited.json()["data"]["rowVersion"]}).status_code == 204
    staff = factories.login_as(db, client, company, role_codes="employee",
                               employee_id=factories.employee(db, company))["headers"]
    assert client.post("/api/organisation/announcements", headers=staff, json={"title": "x"}).status_code == 403
    assert fo.scalar(db, "SELECT COUNT(*) FROM core.audit_log WHERE entity_type = N'eng.announcement' AND entity_id = ?",
                     int(n["id"])) == 3


def test_company_logo_reaches_the_session(client, db, company):
    """The organisation's logo (General Settings) heads the sidebar: it comes with /auth/me."""
    from tests import factories as f

    admin = f.login_as(db, client, company, role_codes="company_admin")
    h = admin["headers"]
    pdf = f.upload(client, h, name="letter.pdf", module="organisation")
    assert client.put("/api/organisation/general/logo", json={"fileId": pdf["id"]}, headers=h).status_code == 422
    logo = f.upload(client, h, name="logo.png", content=f.PNG_BYTES, module="organisation")
    r = client.put("/api/organisation/general/logo", json={"fileId": logo["id"]}, headers=h)
    assert r.status_code == 200 and r.json()["data"]["logoUrl"].startswith(f"/api/files/{logo['id']}/download")
    me = client.get("/api/auth/me", headers=h).json()["data"]
    assert me["companyName"] and me["companyLogoUrl"].startswith(f"/api/files/{logo['id']}/download")
    assert client.put("/api/organisation/general/logo", json={"fileId": None}, headers=h).json()["data"]["logoUrl"] is None
