"""Employee profile: personal details, photo, the tabs (emergency contacts, dependents, skills, education,
experience, contracts, documents) with files and scope, sensitive documents and contracts, document
expiry, the Update Information requests, and the employee events."""
from datetime import date, timedelta

from tests import factories
from tests import factories_organisation as fo


def _url(emp, segment: str, row_id=None) -> str:
    return f"/api/employees/{emp}/{segment}" + (f"/{row_id}" if row_id else "")


def _crud(client, h, emp, segment: str, body: dict, change: dict) -> dict:
    """Adds a row, finds it in the list, edits it, and checks a stale edit is refused. Returns the edited row."""
    created = client.post(_url(emp, segment), headers=h, json=body)
    assert created.status_code == 201, created.text
    row = created.json()["data"]
    assert row["id"] in {x["id"] for x in client.get(_url(emp, segment), headers=h).json()["data"]}
    edited = client.put(_url(emp, segment, row["id"]), headers=h, json={**body, **change, "rowVersion": row["rowVersion"]})
    assert edited.status_code == 200, edited.text
    stale = client.put(_url(emp, segment, row["id"]), headers=h, json={**body, "rowVersion": row["rowVersion"]})
    assert stale.status_code == 409
    return edited.json()["data"]


def _delete(client, h, emp, segment: str, row: dict) -> None:
    r = client.delete(_url(emp, segment, row["id"]), headers=h, params={"rowVersion": row["rowVersion"]})
    assert r.status_code == 204, r.text


def _foreign_file(db, client, name: str = "other.pdf", content: bytes = factories.PDF_BYTES) -> dict:
    """A file uploaded in another company."""
    other = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    return factories.upload(client, other, name, content, module="employees")


def test_personal_details_photo_and_events(client, db, company, admin):
    h = admin["headers"]
    city = fo.city(db)
    r = client.post("/api/employees", headers=h, json={
        "firstName": "Sana", "lastName": f"Iqbal{factories.tag()}", "branchId": factories.branch(db, company),
        "joiningDate": "2024-01-15", "dateOfBirth": "1994-05-02", "maritalStatus": "single",
        "homeAddress": "House 12, Street 4", "homeCityId": city})
    assert r.status_code == 201, r.text
    e = r.json()["data"]
    assert e["homeAddress"] == "House 12, Street 4" and e["homeCityId"] == str(city) and e["homeCityName"]
    assert e["tenureMonths"] >= 20 and e["photoUrl"] is None and e["emergencyContactPhone"] is None
    created = fo.events(db, company, "employees.created", int(e["id"]))
    assert len(created) == 1 and created[0]["code"] == e["code"] and "cnic" not in created[0]
    bad_city = client.put(f"/api/employees/{e['id']}", headers=h,
                          json={"firstName": "Sana", "lastName": e["lastName"], "branchId": e["branchId"],
                                "homeCityId": 999999999, "rowVersion": e["rowVersion"]})
    assert bad_city.status_code == 422 and "homeCityId" in bad_city.json()["fieldErrors"]

    png = factories.upload(client, h, "face.png", factories.PNG_BYTES, module="employees")
    ph = client.put(f"/api/employees/{e['id']}/photo", headers=h, json={"fileId": png["id"], "rowVersion": e["rowVersion"]})
    assert ph.status_code == 200, ph.text
    card = ph.json()["data"]
    assert card["photoFileId"] == png["id"] and card["photoUrl"].startswith(f"/api/files/{png['id']}/download")
    assert card["homeAddress"] == "House 12, Street 4"
    assert client.get(card["photoUrl"]).status_code == 200
    picker = client.get("/api/employees/lookup", params={"q": e["lastName"]}, headers=h).json()["data"]
    assert picker[0]["photoUrl"].startswith(f"/api/files/{png['id']}/download")
    listed = client.get("/api/employees", params={"q": e["lastName"]}, headers=h).json()["data"]
    assert listed[0]["photoUrl"]
    assert any(x["change"] == "photo" for x in fo.events(db, company, "employees.updated", int(e["id"])))

    pdf = factories.upload(client, h, "cv.pdf", module="employees")
    not_image = client.put(f"/api/employees/{e['id']}/photo", headers=h,
                           json={"fileId": pdf["id"], "rowVersion": card["rowVersion"]})
    assert not_image.status_code == 422 and not_image.json()["code"] == "PHOTO_NOT_IMAGE"
    foreign = _foreign_file(db, client, "x.png", factories.PNG_BYTES)
    refused = client.put(f"/api/employees/{e['id']}/photo", headers=h,
                         json={"fileId": foreign["id"], "rowVersion": card["rowVersion"]})
    assert refused.status_code == 422 and "fileId" in refused.json()["fieldErrors"]
    stale = client.put(f"/api/employees/{e['id']}/photo", headers=h, json={"fileId": None, "rowVersion": e["rowVersion"]})
    assert stale.status_code == 409
    cleared = client.put(f"/api/employees/{e['id']}/photo", headers=h,
                         json={"fileId": None, "rowVersion": card["rowVersion"]})
    assert cleared.status_code == 200 and cleared.json()["data"]["photoUrl"] is None

    # Staff change their own photo with employees.photo.edit (own scope), nobody else's.
    other = factories.employee(db, company)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=int(e["id"]))
    fo.grant(db, staff["user_id"], "employees.photo.edit")
    sh = staff["headers"]
    mine = client.get(f"/api/employees/{e['id']}", headers=sh).json()["data"]
    own_png = factories.upload(client, sh, "me.png", factories.PNG_BYTES, module="employees")
    assert client.put(f"/api/employees/{e['id']}/photo", headers=sh,
                      json={"fileId": own_png["id"], "rowVersion": mine["rowVersion"]}).status_code == 200
    assert client.put(f"/api/employees/{other}/photo", headers=sh,
                      json={"fileId": own_png["id"], "rowVersion": mine["rowVersion"]}).status_code == 404

    # Switching off and on publishes its events.
    current = client.get(f"/api/employees/{other}", headers=h).json()["data"]
    off = client.patch(f"/api/employees/{other}/deactivate", headers=h, json={"rowVersion": current["rowVersion"]})
    assert off.status_code == 200
    assert fo.events(db, company, "employees.deactivated", other)[0]["status"] == "inactive"
    client.patch(f"/api/employees/{other}/reactivate", headers=h, json={"rowVersion": off.json()["data"]["rowVersion"]})
    assert len(fo.events(db, company, "employees.reactivated", other)) == 1


def test_profile_tabs_lifecycle(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company)

    # Emergency contacts: the first is primary; marking another primary moves it; it shows on the card.
    first = _crud(client, h, emp, "emergency-contacts",
                  {"name": "Ayesha Khan", "relation": "spouse", "phone": "+92 300 1234567"}, {"address": "Lahore"})
    assert first["isPrimary"] and first["address"] == "Lahore"
    second = client.post(_url(emp, "emergency-contacts"), headers=h,
                         json={"name": "Imran Khan", "relation": "brother", "phone": "0321-7654321", "isPrimary": True})
    assert second.status_code == 201
    contacts = client.get(_url(emp, "emergency-contacts"), headers=h).json()["data"]
    assert [c["name"] for c in contacts if c["isPrimary"]] == ["Imran Khan"]
    assert client.get(f"/api/employees/{emp}", headers=h).json()["data"]["emergencyContactPhone"] == "0321-7654321"
    _delete(client, h, emp, "emergency-contacts", second.json()["data"])
    assert client.get(_url(emp, "emergency-contacts"), headers=h).json()["data"][0]["isPrimary"]
    bad_phone = client.post(_url(emp, "emergency-contacts"), headers=h,
                            json={"name": "X", "relation": "friend", "phone": "call me"})
    assert bad_phone.status_code == 422

    # Dependents.
    dep = _crud(client, h, emp, "dependents",
                {"firstName": "Hira", "lastName": "Khan", "relation": "daughter", "dateOfBirth": "2015-04-01"},
                {"occupation": "Student"})
    assert dep["occupation"] == "Student" and dep["name"] == "Hira Khan"
    future = client.post(_url(emp, "dependents"), headers=h,
                         json={"firstName": "Z", "relation": "son", "dateOfBirth": str(date.today() + timedelta(days=5))})
    assert future.status_code == 422
    assert client.post(_url(emp, "dependents"), headers=h, json={"firstName": "Z", "relation": "cousin"}).status_code == 422
    _delete(client, h, emp, "dependents", dep)

    # Skills: one row per title.
    skill = _crud(client, h, emp, "skills", {"skillTitle": "SQL Server", "skillLevel": "intermediate"},
                  {"skillLevel": "expert"})
    assert skill["skillLevel"] == "expert"
    dup = client.post(_url(emp, "skills"), headers=h, json={"skillTitle": "SQL Server", "skillLevel": "beginner"})
    assert dup.status_code == 409 and dup.json()["code"] == "SKILL_DUPLICATE"

    # Education with its document; a course in process has no end date.
    degree = factories.upload(client, h, "degree.pdf", module="employees")
    edu = _crud(client, h, emp, "education",
                {"title": "BS Computer Science", "institute": "FAST", "fromDate": "2012-09-01", "toDate": "2016-06-30",
                 "fileId": degree["id"]}, {"institute": "FAST-NUCES"})
    assert edu["file"]["id"] == degree["id"] and edu["file"]["name"] == "degree.pdf"
    assert client.get(edu["file"]["url"]).status_code == 200
    in_process = client.post(_url(emp, "education"), headers=h,
                             json={"title": "MS", "institute": "LUMS", "isInProcess": True, "toDate": "2027-01-01"})
    assert in_process.status_code == 422
    assert client.post(_url(emp, "education"), headers=h,
                       json={"title": "MS", "institute": "LUMS", "isInProcess": True}).status_code == 201
    foreign = _foreign_file(db, client)
    refused = client.post(_url(emp, "education"), headers=h,
                          json={"title": "MBA", "institute": "IBA", "fileId": foreign["id"]})
    assert refused.status_code == 422 and "fileId" in refused.json()["fieldErrors"]

    # Experience: no To date is the current job.
    exp = _crud(client, h, emp, "experience",
                {"companyName": "HData Systems", "jobTitle": "App Developer", "fromDate": "2018-01-01",
                 "toDate": "2020-01-31"}, {"jobTitle": "Senior App Developer"})
    assert exp["jobTitle"] == "Senior App Developer" and not exp["isCurrent"] and exp["months"] == 24
    current = client.post(_url(emp, "experience"), headers=h,
                          json={"companyName": "iTechArt", "jobTitle": "Lead", "fromDate": "2020-02-01"}).json()["data"]
    assert current["isCurrent"]
    backwards = client.post(_url(emp, "experience"), headers=h,
                            json={"companyName": "A", "jobTitle": "B", "fromDate": "2020-02-01", "toDate": "2019-01-01"})
    assert backwards.status_code == 422

    # Every change is in the History popup and published, never as the employee's own change here.
    changed = fo.events(db, company, "employees.profile_changed", emp)
    assert {x["tab"] for x in changed} >= {"emergency_contact", "dependent", "skill", "education", "experience"}
    assert not any(x["bySelf"] for x in changed)
    fields = {c["fieldName"] for c in client.get(f"/api/employees/{emp}/changes", params={"pageSize": 100},
                                                 headers=h).json()["data"]}
    assert {"dependent", "skill", "education"} <= fields

    stranger = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    assert client.get(_url(emp, "skills"), headers=stranger).status_code == 404
    assert client.delete(_url(emp, "skills", skill["id"]), headers=h, params={"rowVersion": exp["rowVersion"]}).status_code == 409


def test_profile_tabs_scope(client, db, company, admin):
    manager = factories.employee(db, company)
    emp = factories.employee(db, company, line_manager_id=manager)
    other = factories.employee(db, company)

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    fo.grant(db, staff["user_id"], "employees.dependents.view", "employees.dependents.edit")
    sh = staff["headers"]
    own = client.post(_url(emp, "dependents"), headers=sh, json={"firstName": "Ali", "relation": "son"})
    assert own.status_code == 201, own.text
    assert fo.events(db, company, "employees.profile_changed", emp)[0]["bySelf"] is True
    assert client.get(_url(other, "dependents"), headers=sh).status_code == 404
    assert client.post(_url(other, "dependents"), headers=sh, json={"firstName": "X", "relation": "son"}).status_code == 404
    assert client.get(_url(emp, "skills"), headers=sh).status_code == 200  # the Employee role reads its own tabs

    # A line manager reads the team's dependents but does not edit them.
    lead = factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)
    fo.grant(db, lead["user_id"], "employees.dependents.view", scope="team")
    lh = lead["headers"]
    assert [d["firstName"] for d in client.get(_url(emp, "dependents"), headers=lh).json()["data"]] == ["Ali"]
    assert client.get(_url(other, "dependents"), headers=lh).status_code == 404
    # Editing reaches only their own record (Employee self-service), so a report's tab is not found.
    assert client.post(_url(emp, "dependents"), headers=lh, json={"firstName": "X", "relation": "son"}).status_code == 404

    # Executives read non-sensitive tabs company-wide; contracts are sensitive and held back.
    executive = factories.login_as(db, client, company, role_codes="executive")["headers"]
    assert client.get(_url(emp, "dependents"), headers=executive).status_code == 200
    assert client.get(_url(emp, "contracts"), headers=executive).status_code == 403


def test_documents_sensitivity_and_expiry(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company)

    def add(doc_type: str, headers=h, **extra) -> dict:
        f = factories.upload(client, headers, f"{doc_type}.pdf", module="employees")
        r = client.post(_url(emp, "documents"), headers=headers, json={"documentType": doc_type, "fileId": f["id"], **extra})
        assert r.status_code == 201, r.text
        return r.json()["data"]

    cnic = add("cnic", title="CNIC Front & Back", documentNumber="35202-1234567-1")
    degree = add("degree", title="BS degree")
    offer = add("offer_letter")
    assert cnic["category"] == "identity" and degree["category"] == "general" and offer["category"] == "pay"
    assert cnic["file"]["url"] and cnic["documentNumber"] == "35202-1234567-1"
    assert len(client.get(_url(emp, "documents"), headers=h).json()["data"]) == 3
    missing_file = client.post(_url(emp, "documents"), headers=h, json={"documentType": "other"})
    assert missing_file.status_code == 422
    backwards = client.post(_url(emp, "documents"), headers=h, json={
        "documentType": "passport", "fileId": degree["file"]["id"], "issueDate": "2024-01-01", "expiryDate": "2023-01-01"})
    assert backwards.status_code == 422

    # Without the CNIC and salary permissions, identity documents and pay letters are not there.
    clerk = factories.login_as(db, client, company)
    fo.grant(db, clerk["user_id"], "employees.documents.view", "employees.documents.edit", scope="company")
    ch = clerk["headers"]
    assert [d["id"] for d in client.get(_url(emp, "documents"), headers=ch).json()["data"]] == [degree["id"]]
    assert client.put(_url(emp, "documents", cnic["id"]), headers=ch,
                      json={"documentType": "cnic", "fileId": cnic["file"]["id"], "rowVersion": cnic["rowVersion"]}).status_code == 404
    assert client.delete(_url(emp, "documents", offer["id"]), headers=ch,
                         params={"rowVersion": offer["rowVersion"]}).status_code == 404
    f = factories.upload(client, ch, "passport.pdf", module="employees")
    assert client.post(_url(emp, "documents"), headers=ch, json={"documentType": "passport", "fileId": f["id"]}).status_code == 403
    edited = client.put(_url(emp, "documents", degree["id"]), headers=ch,
                        json={"documentType": "degree", "title": "BS (Hons)", "fileId": degree["file"]["id"],
                              "rowVersion": degree["rowVersion"]})
    assert edited.status_code == 200 and edited.json()["data"]["title"] == "BS (Hons)"
    retyped = client.put(_url(emp, "documents", degree["id"]), headers=ch,
                         json={"documentType": "cnic", "fileId": degree["file"]["id"],
                               "rowVersion": edited.json()["data"]["rowVersion"]})
    assert retyped.status_code == 403  # cannot turn a document into one they may not handle
    foreign = _foreign_file(db, client)
    assert client.post(_url(emp, "documents"), headers=ch,
                       json={"documentType": "certificate", "fileId": foreign["id"]}).status_code == 422
    fo.grant(db, clerk["user_id"], "employees.identity.view", scope="company")
    assert {d["id"] for d in client.get(_url(emp, "documents"), headers=ch).json()["data"]} == {cnic["id"], degree["id"]}

    # The employee sees their own CNIC copy and offer letter (they hold identity and salary for themselves).
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    fo.grant(db, staff["user_id"], "employees.documents.view", "employees.documents.edit")
    sh = staff["headers"]
    assert len(client.get(_url(emp, "documents"), headers=sh).json()["data"]) == 3

    # Expiry: the employee is told once, and the event is published.
    passport = add("passport", sh, expiryDate=str(date.today() + timedelta(days=10)), issueDate="2020-01-01")
    assert passport["isExpired"] is False
    reported = db.call_one("hr.usp_employee_document_expiry_notify", company_id=company, days_ahead=30)["reported"]
    assert reported >= 1
    assert "A document of yours expires soon" in fo.notification_titles(db, staff["user_id"])
    expiring = fo.events(db, company, "employees.document_expiring", int(passport["id"]))
    assert len(expiring) == 1 and expiring[0]["documentType"] == "passport"
    db.call_one("hr.usp_employee_document_expiry_notify", company_id=company, days_ahead=30)
    assert len(fo.events(db, company, "employees.document_expiring", int(passport["id"]))) == 1
    stale = client.delete(_url(emp, "documents", passport["id"]), headers=h, params={"rowVersion": passport["rowVersion"]})
    assert stale.status_code == 409  # the notice stamped the row
    reread = [d for d in client.get(_url(emp, "documents"), headers=h).json()["data"] if d["id"] == passport["id"]]
    _delete(client, h, emp, "documents", reread[0])


def test_contracts(client, db, company, admin):
    h = admin["headers"]
    emp = factories.employee(db, company)
    start = date.today() - timedelta(days=30)
    paper = factories.upload(client, h, "contract.pdf", module="employees")
    first = client.post(_url(emp, "contracts"), headers=h, json={
        "contractType": "temporary", "durationMonths": 12, "fromDate": str(start), "fileId": paper["id"]})
    assert first.status_code == 201, first.text
    c1 = first.json()["data"]
    assert c1["toDate"] == str(date(start.year + 1, start.month, start.day) - timedelta(days=1))
    assert c1["status"] == "active" and c1["file"]["id"] == paper["id"]
    overlap = client.post(_url(emp, "contracts"), headers=h,
                          json={"contractType": "permanent", "fromDate": str(start + timedelta(days=60))})
    assert overlap.status_code == 409 and overlap.json()["code"] == "CONTRACT_OVERLAP"
    later = date.fromisoformat(c1["toDate"]) + timedelta(days=1)
    custom = client.post(_url(emp, "contracts"), headers=h, json={
        "contractType": "contractual", "fromDate": str(later), "toDate": str(later + timedelta(days=90))})
    assert custom.status_code == 201 and custom.json()["data"]["status"] == "upcoming"
    assert custom.json()["data"]["durationMonths"] is None and custom.json()["data"]["file"] is None
    renewed = client.put(_url(emp, "contracts", c1["id"]), headers=h, json={
        "contractType": "temporary", "fromDate": str(start), "toDate": str(start + timedelta(days=20)),
        "remarks": "Ended early", "rowVersion": c1["rowVersion"]})
    assert renewed.status_code == 200 and renewed.json()["data"]["status"] == "expired"
    assert client.post(_url(emp, "contracts"), headers=h, json={
        "contractType": "temporary", "fromDate": "2020-01-01", "fileId": _foreign_file(db, client)["id"]}).status_code == 422
    rows = client.get(_url(emp, "contracts"), headers=h).json()["data"]
    assert [r["status"] for r in rows] == ["upcoming", "expired"]

    officer = factories.login_as(db, client, company, role_codes="hr_officer")["headers"]
    assert len(client.get(_url(emp, "contracts"), headers=officer).json()["data"]) == 2
    lead = factories.login_as(db, client, company, role_codes="line_manager")["headers"]
    # Contracts are sensitive: a line manager holds them for their own record only.
    assert client.get(_url(emp, "contracts"), headers=lead).status_code == 404
    _delete(client, h, emp, "contracts", custom.json()["data"])


def test_update_information_requests(client, db, company, admin):
    emp = factories.employee(db, company)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    fo.grant(db, staff["user_id"], "employees.update_requests.view", "employees.update_requests.create",
             "employees.update_requests.cancel")
    sh = staff["headers"]
    hr = factories.login_as(db, client, company, role_codes="hr_manager")
    hh = hr["headers"]
    city = fo.city(db)

    empty = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={"changes": {}})
    assert empty.status_code == 422
    asked = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={
        "changes": {"maritalStatus": "married", "homeAddress": "Flat 3, Gulberg", "homeCityId": city},
        "remarks": "Got married"})
    assert asked.status_code == 201, asked.text
    req = asked.json()["data"]
    assert req["status"] == "pending" and req["employeeId"] == str(emp)
    assert req["changes"] == {"maritalStatus": "married", "homeAddress": "Flat 3, Gulberg", "homeCityId": str(city)}
    assert req["previous"] == {"maritalStatus": None, "homeAddress": None, "homeCityId": None}
    assert any("asked to update their details" in t for t in fo.notification_titles(db, hr["user_id"]))
    assert fo.events(db, company, "employees.update_requested", int(req["id"]))[0]["employeeId"] == str(emp)
    again = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={"changes": {"phone1": "0300"}})
    assert again.status_code == 409 and again.json()["code"] == "UPDATE_REQUEST_PENDING"
    other = factories.employee(db, company)
    assert client.post(f"/api/employees/{other}/update-requests", headers=sh,
                       json={"changes": {"phone1": "0300"}}).status_code == 404
    assert client.patch(f"/api/employees/update-requests/{req['id']}/approve", headers=sh,
                        json={"rowVersion": req["rowVersion"]}).status_code == 403

    pending = client.get("/api/employees/update-requests", params={"status": "pending", "employeeId": emp},
                         headers=hh).json()
    assert [r["id"] for r in pending["data"]] == [req["id"]]
    approved = client.patch(f"/api/employees/update-requests/{req['id']}/approve", headers=hh,
                            json={"remarks": "Nikah nama seen", "rowVersion": req["rowVersion"]})
    assert approved.status_code == 200, approved.text
    assert approved.json()["data"]["status"] == "approved" and approved.json()["data"]["decidedByUserId"] == str(hr["user_id"])
    card = client.get(f"/api/employees/{emp}", headers=hh).json()["data"]
    assert card["maritalStatus"] == "married" and card["homeAddress"] == "Flat 3, Gulberg" and card["homeCityId"] == str(city)
    assert any(x["change"] == "update_request" for x in fo.events(db, company, "employees.updated", emp))
    assert fo.events(db, company, "employees.update_decided", int(req["id"]))[0]["status"] == "approved"
    assert "Your Update Information request was approved" in fo.notification_titles(db, staff["user_id"])
    twice = client.patch(f"/api/employees/update-requests/{req['id']}/approve", headers=hh,
                         json={"rowVersion": approved.json()["data"]["rowVersion"]})
    assert twice.status_code == 409 and twice.json()["code"] == "UPDATE_REQUEST_DECIDED"
    changes = client.get(f"/api/employees/{emp}/changes", params={"pageSize": 100}, headers=hh).json()["data"]
    assert any(c["fieldName"] == "marital_status" and c["actionName"] == "update_request" for c in changes)
    same = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={"changes": {"maritalStatus": "married"}})
    assert same.status_code == 422

    # Rejected: nothing changes. Cancelled by the employee.
    r2 = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={"changes": {"phone1": "0300 1112223"}})
    rejected = client.patch(f"/api/employees/update-requests/{r2.json()['data']['id']}/reject", headers=hh,
                            json={"remarks": "Use your official number", "rowVersion": r2.json()["data"]["rowVersion"]})
    assert rejected.status_code == 200 and rejected.json()["data"]["decisionRemarks"] == "Use your official number"
    assert client.get(f"/api/employees/{emp}", headers=hh).json()["data"]["phone1"] is None
    r3 = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={"changes": {"dateOfBirth": "1990-02-03"}})
    cancelled = client.patch(f"/api/employees/update-requests/{r3.json()['data']['id']}/cancel", headers=sh,
                             json={"rowVersion": r3.json()["data"]["rowVersion"]})
    assert cancelled.status_code == 200 and cancelled.json()["data"]["status"] == "cancelled"
    mine = client.get("/api/employees/update-requests", headers=sh).json()
    assert mine["meta"]["total"] == 3 and {r["employeeId"] for r in mine["data"]} == {str(emp)}
    future = client.post(f"/api/employees/{emp}/update-requests", headers=sh,
                         json={"changes": {"dateOfBirth": str(date.today() + timedelta(days=1))}})
    assert future.status_code == 422

    # Nobody decides their own request, even HR.
    hr_emp = factories.employee(db, company)
    hr_self = factories.login_as(db, client, company, role_codes="hr_manager", employee_id=hr_emp)["headers"]
    own = client.post(f"/api/employees/{hr_emp}/update-requests", headers=hr_self, json={"changes": {"phone2": "042 111"}})
    assert own.status_code == 201
    assert client.patch(f"/api/employees/update-requests/{own.json()['data']['id']}/approve", headers=hr_self,
                        json={"rowVersion": own.json()["data"]["rowVersion"]}).status_code == 403
    stranger = factories.login_as(db, client, factories.company(db), role_codes="company_admin")["headers"]
    assert client.get(f"/api/employees/update-requests/{own.json()['data']['id']}", headers=stranger).status_code == 404
