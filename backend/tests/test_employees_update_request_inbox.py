"""Update Information requests as the web app uses them (Test Run 18-19 Nov 2026, rows 3.34 and 3.35):
HR's notification opens Talent Management -> Update Requests on the request, HR lists and searches them,
and the employee sees their own waiting request on My Profile and cancels it (then may ask again)."""
from tests import factories
from tests import factories_organisation as fo


def _links(db, user_id: int, entity_id: int) -> list[str]:
    cur = db.conn.cursor()
    try:
        return [r[0] for r in cur.execute("SELECT link FROM core.notification WHERE user_account_id = ? "
                                          "AND entity_type = N'hr.employee_change_request' AND entity_id = ? "
                                          "ORDER BY id", user_id, entity_id).fetchall()]
    finally:
        cur.close()


def test_hr_is_told_where_to_decide_and_the_employee_can_cancel(client, db, company):
    emp = factories.employee(db, company, first_name="Areeba", last_name=f"Hameed{factories.tag()}")
    code = fo.scalar(db, "SELECT code FROM hr.employee WHERE id = ?", emp)
    # The default Employee role: Update Information requests of their own (view, create, cancel).
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    sh = staff["headers"]
    hr = factories.login_as(db, client, company, role_codes="hr_manager")
    hh = hr["headers"]

    asked = client.post(f"/api/employees/{emp}/update-requests", headers=sh,
                        json={"changes": {"phone2": "+92 321 5550101"}, "remarks": "My new second number"})
    assert asked.status_code == 201, asked.text
    req = asked.json()["data"]
    assert _links(db, hr["user_id"], int(req["id"])) == [f"/talent-management/update-requests?request={req['id']}"]

    # HR's list: by status, and by the employee's code or name.
    for q in (code, "Areeba Hameed", code.lower()):
        found = client.get("/api/employees/update-requests", params={"status": "pending", "q": q}, headers=hh)
        assert found.status_code == 200, found.text
        assert [r["id"] for r in found.json()["data"]] == [req["id"]], q
    none = client.get("/api/employees/update-requests", params={"q": "no such person [x]"}, headers=hh).json()
    assert none["meta"]["total"] == 0 and none["data"] == []

    # The employee's own waiting request (My Profile) and Cancel; then they may ask again.
    mine = client.get("/api/employees/update-requests", params={"employeeId": emp, "status": "pending"},
                      headers=sh).json()["data"]
    assert [(r["id"], r["changes"]) for r in mine] == [(req["id"], {"phone2": "+92 321 5550101"})]
    again = client.post(f"/api/employees/{emp}/update-requests", headers=sh, json={"changes": {"phone2": "+92 321 5550202"}})
    assert again.status_code == 409 and again.json()["code"] == "UPDATE_REQUEST_PENDING"
    cancelled = client.patch(f"/api/employees/update-requests/{req['id']}/cancel", headers=sh,
                             json={"rowVersion": req["rowVersion"]})
    assert cancelled.status_code == 200 and cancelled.json()["data"]["status"] == "cancelled"
    assert client.get("/api/employees/update-requests", params={"employeeId": emp, "status": "pending"},
                      headers=sh).json()["data"] == []
    second = client.post(f"/api/employees/{emp}/update-requests", headers=sh,
                         json={"changes": {"phone2": "+92 321 5550202"}})
    assert second.status_code == 201, second.text

    # HR approves it: the profile changes and the employee is told, with a link to My Profile.
    req2 = second.json()["data"]
    approved = client.patch(f"/api/employees/update-requests/{req2['id']}/approve", headers=hh,
                            json={"rowVersion": req2["rowVersion"]})
    assert approved.status_code == 200, approved.text
    assert client.get(f"/api/employees/{emp}", headers=hh).json()["data"]["phone2"] == "+92 321 5550202"
    assert _links(db, staff["user_id"], int(req2["id"])) == ["/my-profile"]
    # A cancelled request is not decided again.
    stale = client.patch(f"/api/employees/update-requests/{req['id']}/approve", headers=hh,
                         json={"rowVersion": cancelled.json()["data"]["rowVersion"]})
    assert stale.status_code == 409 and stale.json()["code"] == "UPDATE_REQUEST_DECIDED"
