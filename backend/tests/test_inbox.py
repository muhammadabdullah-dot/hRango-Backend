"""Inbox: the signed-in user's own notifications, added by other modules through core procedures."""
from tests import factories


def test_inbox(client, db, company):
    emp = factories.employee(db, company)
    me = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    h = me["headers"]
    added = db.call_one("core.usp_notification_add_employee", company_id=company, employee_id=emp,
                        title="Aryan Kel has requested for leave", notification_type="request",
                        link="/requests/leave", entity_type="req.request", entity_id=1)
    assert added["added"] == 1
    for title in ("Password changed successfully!", "Announcement: public holiday on 30 September"):
        db.call("core.usp_notification_add", company_id=company, user_account_id=me["user_id"], title=title)

    other = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    theirs = db.call_one("core.usp_notification_add", company_id=company, user_account_id=other["user_id"],
                         title="Not yours")["id"]
    elsewhere = factories.company(db)
    db.call("core.usp_notification_add", company_id=elsewhere, user_account_id=me["user_id"], title="Other company")

    summary = client.get("/api/inbox", headers=h).json()["data"]
    assert summary["unread"] == 3 and len(summary["latest"]) == 3 and not summary["latest"][0]["read"]

    page = client.get("/api/inbox/notifications", params={"pageSize": 2}, headers=h).json()
    assert page["meta"]["total"] == 3 and len(page["data"]) == 2
    first = page["data"][0]["id"]
    assert client.patch(f"/api/inbox/notifications/{first}/read", headers=h).json()["data"]["changed"] == 1
    assert client.get("/api/inbox/notifications", params={"unreadOnly": True}, headers=h).json()["meta"]["total"] == 2
    assert client.patch(f"/api/inbox/notifications/{theirs}/read", headers=h).status_code == 404

    assert client.patch("/api/inbox/notifications/read-all", headers=h).json()["data"]["changed"] == 2
    assert client.get("/api/inbox", headers=h).json()["data"]["unread"] == 0
    assert client.patch(f"/api/inbox/notifications/{first}/clear", headers=h).json()["data"]["changed"] == 1
    assert client.get("/api/inbox/notifications", headers=h).json()["meta"]["total"] == 2
    assert client.patch("/api/inbox/notifications/clear-all", headers=h).json()["data"]["changed"] == 2
    assert client.get("/api/inbox/notifications", headers=h).json()["meta"]["total"] == 0
    assert client.get("/api/inbox", headers=other["headers"]).json()["data"]["unread"] == 1

    nobody = factories.login_as(db, client, company)["headers"]
    assert client.get("/api/inbox", headers=nobody).status_code == 403
    assert client.get("/api/inbox").status_code == 401
