"""Notification links open pages the web app has (Test Run 18-19 Nov 2026, rows 3.35, 6.18, 7B.41 and
15.36: /requests/approvals/<id>, /requests/<type>/<id>, /employees/update-requests, /profile ... opened
"Page not found"). Procedures write the links (core.usp_notification_add*); every one of them starts with
one of WEB_LINKS, a page of the web app with the record in a search parameter. Keep WEB_LINKS in line with
the frontend's src/features/inbox/notification-links.test.ts, which checks that each opens a route of the
app and that the route reads the record's parameter. Migration 0009 rewrote the links already sent."""
import re
from datetime import date, timedelta
from pathlib import Path

from tests import factories_requests as fr

BACKEND = Path(__file__).resolve().parents[1]
PROCEDURES = BACKEND / "db" / "procedures"

# The start of every link literal in the procedures (N'/...'), as the SQL spells it.
WEB_LINKS = {
    # Requests (req.fn_request_link): each type's page, ?tab=approvals&request=<id> or ?request=<id>.
    "/requests/punch", "/requests/shift", "/requests/transfer", "/requests/leave", "/requests/loan-advances",
    "/requests/work-from-home", "/requests/official-visits", "/requests/promotion", "/requests/relaxation",
    "/requests/rest-days", "/requests/travel", "/requests/resignation", "/requests/expense",
    "/requests/air-tickets", "/requests/requisition", "/attendance/overtime?tab=",
    # Records opened on their list page.
    "/talent-management/update-requests?request=", "/my-profile", "/my-profile?tab=documents",
    "/performance/reviews?review=", "/recruitment/applications?view=", "/recruitment/interviews?view=",
    "/recruitment/offers?view=", "/project-management/workspaces/",
    # List pages.
    "/assets/allocations", "/attendance/time-sheet", "/benefits/employees", "/leaves/my-leaves",
    "/manpower-planning/e-budgeting", "/payroll/pay-slips/my", "/payroll/vouchers/employee",
}
# Engagement and Training have no web pages yet (frontend docs/qa-findings-2026-11-12.md, finding 14):
# their links name the record for when they do; the web app's inbox does not offer to open a link that
# matches none of its routes.
NO_WEB_PAGE_YET = {"/engagement/posts/", "/engagement/my-posts", "/engagement/my-surveys/", "/training/enrolments/",
                   "/training/sessions/"}


def _link_literals() -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for f in PROCEDURES.rglob("*.sql"):
        for m in re.finditer(r"N'(/[^']*)'", f.read_text(encoding="utf-8")):
            found.setdefault(m.group(1), set()).add(f.relative_to(PROCEDURES).as_posix())
    return found


def test_procedures_link_only_to_pages_the_web_app_has():
    found = _link_literals()
    unknown = {link: sorted(files) for link, files in found.items() if link not in WEB_LINKS | NO_WEB_PAGE_YET}
    assert not unknown, f"Links to pages the web app does not have (add the page, or list it here): {unknown}"
    # The shapes that opened "Page not found" are gone.
    for old in ("/requests/approvals/", "/employees/update-requests", "/profile", "/profile/documents",
                "/performance/reviews/", "/recruitment/applications/", "/recruitment/offers/",
                "/recruitment/interviews/", "/requests/requisition/"):
        assert old not in found, old


def _notify(db, user_id: int, company_id: int, link: str, ntype: str, entity_type: str, entity_id: int) -> int:
    return fr._scalar(db, "SET NOCOUNT ON; INSERT core.notification (company_id, user_account_id, notification_type, "
                          "title, link, entity_type, entity_id) OUTPUT INSERTED.id VALUES (?, ?, ?, N'Old', ?, ?, ?)",
                      company_id, user_id, ntype, link, entity_type, entity_id)


def test_links_already_sent_are_rewritten(client, db):
    org = fr.org(db, client)
    r = client.post("/api/requests/travel", json=fr.travel_body(date.today() + timedelta(days=60)),
                    headers=org.staff.headers)
    assert r.status_code == 201, r.text
    rid = int(r.json()["data"]["id"])
    user = org.manager.user_id
    cases = {
        (f"/requests/approvals/{rid}", "request_approval", "req.request", rid):
            f"/requests/travel?tab=approvals&request={rid}",
        (f"/requests/travel/{rid}", "request_update", "req.request", rid): f"/requests/travel?request={rid}",
        ("/employees/update-requests", "employee_update_request", "hr.employee_change_request", 77):
            "/talent-management/update-requests?request=77",
        ("/profile", "employee_update_request", "hr.employee_change_request", 78): "/my-profile",
        ("/profile/documents", "employee_document", "hr.employee_document", 79): "/my-profile?tab=documents",
        ("/performance/reviews/38", "performance", "perf.appraisal", 38): "/performance/reviews?review=38",
        ("/recruitment/applications/5", "recruitment", "rec.application", 5): "/recruitment/applications?view=5",
        ("/recruitment/interviews/6", "recruitment", "rec.interview", 6): "/recruitment/interviews?view=6",
        ("/recruitment/offers/7", "recruitment", "rec.offer", 7): "/recruitment/offers?view=7",
        # Not touched: no web page yet, and links that already work.
        ("/engagement/my-surveys/2", "engagement", "eng.survey", 2): "/engagement/my-surveys/2",
        ("/payroll/pay-slips/my", "payslip", "pay.payslip", 3): "/payroll/pay-slips/my",
    }
    ids = {key: _notify(db, user, org.company_id, key[0], key[1], key[2], key[3]) for key in cases}
    fr.execute(db, (BACKEND / "db" / "migrations" / "0009_notification_links.sql").read_text(encoding="utf-8"))
    for key, want in cases.items():
        assert fr._scalar(db, "SELECT link FROM core.notification WHERE id = ?", ids[key]) == want, key


def test_each_request_type_links_to_its_page(db):
    """req.fn_request_link: every request type with screens (app/catalogue/requests.py) has a page; overtime is
    decided on Attendance -> Overtime; a type without one (task_extension) gets no link."""
    from app.catalogue.requests import REQUEST_TYPES

    def link(code: str, side: str) -> str | None:
        return fr._scalar(db, "SELECT req.fn_request_link(?, 14, ?)", code, side)

    for code, _label, _sensitive in REQUEST_TYPES:
        approver, requester = link(code, "approvals"), link(code, "requests")
        assert approver and requester, code
        assert any(approver.startswith(start) for start in WEB_LINKS), approver
    assert link("promotion", "approvals") == "/requests/promotion?tab=approvals&request=14"
    assert link("shift_swap", "consents") == "/requests/shift?tab=approvals&view=consents&request=14"
    assert link("leave", "cancellations") == "/requests/leave?tab=approvals&view=cancellations&request=14"
    assert link("loan", "requests") == "/requests/loan-advances?request=14"
    assert link("requisition", "all") == "/requests/requisition?scope=all&request=14"
    assert link("overtime", "approvals") == "/attendance/overtime?tab=applications&request=14"
    assert link("overtime", "consents") == "/attendance/overtime?tab=applications&box=consents&request=14"
    assert link("overtime", "requests") == "/attendance/overtime?tab=my&request=14"
    assert link("task_extension", "approvals") is None
