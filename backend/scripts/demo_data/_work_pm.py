"""Work part, Project Management: three workspaces made through the Create Workspace flow, with statuses,
folders (projects), lists (sprints / modules), tasks and subtasks, and the collaboration around them.
Each action is done by the person who would do it, so the workspace roles in the pm procedures apply."""
import re
from datetime import date, datetime, timedelta
from typing import Any

from scripts.demo_data import World
from scripts.demo_data._work_util import at, day, iso, pdf, png, upload

# --------------------------------------------------------------------------- the workspaces

HRANGO = dict(
    key="product", name="hRango Product", owner="Haroon Rashid", dept="Software Development",
    privacy="workspace", template="product_engineering",
    description="The hRango HR suite: web app, mobile app, design system and release QA.",
    statuses=[("Backlog", "not_started", "#979797"), ("In Progress", "active", "#2F639A"),
              ("Code Review", "active", "#762AFD"), ("QA Testing", "active", "#E9540D"),
              ("Done", "done", "#4DDC00"), ("Released", "closed", "#318845")],
    members=[("Faisal Javed", "manager"), ("Rabia Anwar", "manager"), ("Omer Farooq", "team_leader"),
             ("Areeba Hameed", "team_leader"), ("Zain Abbas", "contributor"), ("Hira Shahid", "contributor"),
             ("Saad Qureshi", "contributor"), ("Danish Iqbal", "contributor"), ("Mehwish Akram", "contributor"),
             ("Maham Zafar", "contributor"), ("Nadia Hussain", "contributor"), ("Shelley Kannes", "hr")],
    tags=[("frontend", "#2F639A"), ("backend", "#562F9A"), ("mobile", "#0E9F6E"), ("bug", "#DC3545"),
          ("ux", "#E9540D"), ("payroll", "#9A782F"), ("attendance", "#2E64E2"), ("security", "#9A2F2F"),
          ("tech-debt", "#979797"), ("customer-request", "#B2B22F")],
    fields=[("Module", "dropdown", {"options": ["Attendance", "Leaves", "Payroll", "Recruitment", "Projects",
                                                "Core HR", "Mobile"]}),
            ("Release", "text", None)],
    overdue=(20, 2),
)

POS = dict(
    key="pos", name="Client – Retail POS", owner="Faisal Javed", dept="Software Development",
    privacy="private", template="project_management",
    description="Point of sale for a 40-store retail chain: tills, inventory sync and FBR invoicing.",
    statuses=None,
    members=[("Haroon Rashid", "manager"), ("Asad Mirza", "team_leader"), ("Areeba Hameed", "team_leader"),
             ("Zain Abbas", "contributor"), ("Danish Iqbal", "contributor"), ("Omer Farooq", "contributor"),
             ("Maham Zafar", "contributor"), ("Komal Shah", "contributor")],
    tags=[("client-feedback", "#B2B22F"), ("integration", "#562F9A"), ("blocker", "#DC3545"),
          ("ui", "#E9540D"), ("api", "#2F639A")],
    fields=[("Client Sign-off", "checkbox", None)],
    overdue=(10, 1),
)

ITOPS = dict(
    key="it", name="IT Operations", owner="Waqas Butt", dept="IT & Network Support",
    privacy="workspace", template="work_starter", status_template="kanban",
    description="Network, servers, security and the helpdesk for both offices.",
    statuses=None,
    members=[("Junaid Akhtar", "team_leader"), ("Haroon Rashid", "manager"), ("Bilal Ahmed", "contributor")],
    tags=[("network", "#2F639A"), ("hardware", "#9A782F"), ("security", "#DC3545"), ("onboarding", "#0E9F6E")],
    fields=[],
    overdue=None,
)

# Folders and lists: (folder, by, [(list, by, start offset, end offset, colour, priority, description)])
STRUCTURE = {
    "product": [
        ("Web App", "Haroon Rashid", [
            ("Sprint 21", "Faisal Javed", -24, -11, "#979797", None, "Attendance sync, payroll bank file, leave UI."),
            ("Sprint 22", "Faisal Javed", -10, 3, "#2F639A", "high", "Self-service updates, PM list view, dashboards."),
            ("Sprint 23", "Faisal Javed", 4, 17, "#762AFD", None, "Performance reviews, training calendar, v2.5."),
        ]),
        ("Mobile App", "Haroon Rashid", [
            ("Mobile v1.3", "Faisal Javed", -14, 10, "#0E9F6E", "high", "Face check-in, push approvals, dark mode."),
            ("Mobile Backlog", "Faisal Javed", None, None, "#979797", None, "Ideas and requests not yet planned."),
        ]),
        ("Design & UX", "Haroon Rashid", [
            ("Design System", "Haroon Rashid", -20, 15, "#E9540D", None, "Tokens, components and handoff."),
        ]),
        ("Quality", "Haroon Rashid", [
            ("Regression & Release QA", "Rabia Anwar", -30, 20, "#DC3545", None, "Release regression and test automation."),
        ]),
    ],
    "pos": [
        ("Phase 1 – Discovery", "Faisal Javed", [
            ("Requirements", "Faisal Javed", -40, -15, "#762AFD", None, "Workshops, SRS and business rules."),
            ("UX Design", "Faisal Javed", -30, 10, "#E9540D", None, "Touch-first POS screens."),
        ]),
        ("Phase 2 – Build", "Faisal Javed", [
            ("Backend API", "Faisal Javed", -20, 25, "#2F639A", "high", "Catalogue, sales, returns, FBR."),
            ("POS Frontend", "Faisal Javed", -10, 25, "#0E9F6E", None, "Cashier app for branch tills."),
            ("UAT & Go-live", "Faisal Javed", 0, 30, "#318845", "urgent", "Client testing and the pilot launch."),
        ]),
    ],
    "it": [
        ("Infrastructure", "Waqas Butt", [
            ("Network & Servers", "Waqas Butt", -30, 30, "#2F639A", None, "Switching, VPN, firewall and servers."),
            ("Backups & Security", "Waqas Butt", -30, 30, "#DC3545", "high", "Backups, MFA and access reviews."),
        ]),
        ("Helpdesk", "Waqas Butt", [
            ("Laptop Refresh 2026", "Waqas Butt", -10, 25, "#9A782F", None, "Eight developer laptops."),
            ("Onboarding Setups", "Waqas Butt", None, None, "#0E9F6E", None, "Laptops and accounts for new joiners."),
        ]),
    ],
}


def T(key: str, name: str, by: str, lst: str | None, status: str, **kw: Any) -> dict:
    """A task. kw: who (list of names or (name, story points)), prio, start, due (day offsets), est (hours),
    tags, desc, late (closed after its due date), subs (subtasks), comments [(author, text[, reactors])],
    time [(who, days ago, minutes, note)], check [(text, done)], field {name: value}, ext, milestone, rec, url."""
    return dict(key=key, name=name, by=by, list=lst, status=status, **kw)


PRODUCT_TASKS = [
    # Sprint 21: finished
    T("p_bio_sync", "Biometric device sync: retry failed punches", "Faisal Javed", "Sprint 21", "Released",
      who=[("Zain Abbas", 5)], prio="high", start=-24, due=-14, est=16, tags=["backend", "attendance"],
      field={"Module": "Attendance", "Release": "v2.4"},
      desc="ZKTeco devices drop punches when the link flaps. Queue failed pushes and retry with back-off.",
      time=[("Zain Abbas", 23, 240, "Device SDK spike"), ("Zain Abbas", 22, 300, "Retry queue"),
            ("Zain Abbas", 20, 180, "Tests against the Lahore device")],
      comments=[("Zain Abbas", "Retry queue is in. @Danish Iqbal can you test with the device in the server room?"),
                ("Danish Iqbal", "Tested with 300 punches and the cable pulled twice: nothing lost.", ["Zain Abbas", "Faisal Javed"])]),
    T("p_leave_card", "Leave balance card redesign", "Faisal Javed", "Sprint 21", "Released",
      who=[("Areeba Hameed", 3), ("Maham Zafar", 2)], prio="normal", start=-23, due=-15, est=10,
      tags=["frontend", "ux"], field={"Module": "Leaves", "Release": "v2.4"},
      time=[("Areeba Hameed", 18, 210, "Card component"), ("Maham Zafar", 21, 120, "Figma variants")]),
    T("p_bank_file", "Payroll run: export bank file (HBL format)", "Faisal Javed", "Sprint 21", "Done",
      who=[("Zain Abbas", 8)], prio="urgent", start=-22, due=-13, est=20, tags=["backend", "payroll"], late=True,
      field={"Module": "Payroll", "Release": "v2.4"},
      desc="Fixed-width HBL bulk transfer file from an approved payroll run.",
      time=[("Zain Abbas", 16, 300, "File layout"), ("Zain Abbas", 13, 240, "Totals and trailer record"),
            ("Zain Abbas", 9, 180, "Fixes after bank feedback")],
      comments=[("Nadia Hussain", "The bank rejected the test file: the trailer total must be in paisa. @Zain Abbas"),
                ("Zain Abbas", "Fixed and re-sent. Closing this late, sorry, the bank took four days to reply.")]),
    T("p_tz_fix", "Fix timezone drift on attendance time sheet", "Faisal Javed", "Sprint 21", "Released",
      who=[("Areeba Hameed", 2)], prio="high", start=-20, due=-16, est=4, tags=["bug", "attendance"],
      field={"Module": "Attendance"}, time=[("Areeba Hameed", 17, 150, "Root cause: UTC dates on the client")]),
    T("p_roster_dnd", "Roster screen: drag to assign shifts", "Faisal Javed", "Sprint 21", "Done",
      who=[("Areeba Hameed", 5)], prio="normal", start=-21, due=-12, est=14, tags=["frontend"],
      field={"Module": "Attendance"}),
    # Sprint 22: the current sprint
    T("p_self_service", "Employee self-service: update information request", "Faisal Javed", "Sprint 22", "In Progress",
      who=[("Zain Abbas", 8)], prio="high", start=-9, due=2, est=24, tags=["backend", "customer-request"],
      field={"Module": "Core HR", "Release": "v2.5"},
      desc="Employees request changes to personal details; HR approves and the change is applied.",
      subs=[T("p_ss_api", "API: update request endpoints", "Zain Abbas", None, "Done", who=["Zain Abbas"], due=-4),
            T("p_ss_flow", "Approval flow wiring", "Zain Abbas", None, "In Progress", who=["Zain Abbas"], due=1),
            T("p_ss_tests", "Unit tests for update requests", "Faisal Javed", None, "Backlog", who=["Saad Qureshi"], due=2)],
      time=[("Zain Abbas", 8, 240, "Schema and procedures"), ("Zain Abbas", 6, 300, "Endpoints"),
            ("Zain Abbas", 2, 180, "Approval flow")],
      check=[("Field-level diff in the approval screen", True), ("Audit log rows", True),
             ("Notify the employee on decision", False)],
      comments=[("Shelley Kannes", "Please make CNIC and bank details always need HR approval. @Zain Abbas"),
                ("Zain Abbas", "Yes, those two go through the HR queue; phone and address too unless you say otherwise.",
                 ["Shelley Kannes"]),
                ("Faisal Javed", "@Saad Qureshi pick up the unit tests once the flow is merged.")]),
    T("p_pm_list", "Projects module: List view grouping", "Faisal Javed", "Sprint 22", "Code Review",
      who=[("Areeba Hameed", 5)], prio="normal", start=-8, due=1, est=16, tags=["frontend"],
      field={"Module": "Projects"},
      time=[("Areeba Hameed", 7, 270, "Group by status / assignee"), ("Areeba Hameed", 3, 200, "Collapsed subtasks")],
      comments=[("Faisal Javed", "PR looks good, two small comments on the virtualised rows."),
                ("Areeba Hameed", "Addressed, @Faisal Javed please re-review.", ["Faisal Javed"])]),
    T("p_dash_widgets", "Dashboard widgets: headcount and attrition", "Faisal Javed", "Sprint 22", "In Progress",
      who=[("Areeba Hameed", 3), ("Maham Zafar", 2)], prio="normal", start=-6, due=3, est=12, tags=["frontend", "ux"],
      field={"Module": "Core HR"}, time=[("Maham Zafar", 5, 150, "Chart styles"), ("Areeba Hameed", 1, 120, "API wiring")]),
    T("p_urdu_pdf", "Payslip PDF: Urdu name rendering", "Rabia Anwar", "Sprint 22", "QA Testing",
      who=[("Zain Abbas", 3), ("Danish Iqbal", 1)], prio="high", start=-7, due=-1, est=6, tags=["bug", "payroll"],
      field={"Module": "Payroll"},
      comments=[("Danish Iqbal", "Names render correctly now but the right-to-left alignment is off in the header."),
                ("Zain Abbas", "Pushed a fix for the header, @Danish Iqbal please retest.")]),
    T("p_encash", "Leave encashment calculation", "Faisal Javed", "Sprint 22", "In Progress",
      who=[("Zain Abbas", 5)], prio="urgent", start=-10, due=-3, est=16, tags=["backend", "payroll"],
      field={"Module": "Leaves"},
      ext=("pending", "Zain Abbas", 4, "Waiting on Finance to confirm whether encashment uses basic or gross salary."),
      time=[("Zain Abbas", 9, 180, "Rules"), ("Zain Abbas", 4, 120, "Draft calculation")],
      comments=[("Zain Abbas", "@Nadia Hussain is encashment on basic or gross? The policy document says both."),
                ("Nadia Hussain", "Basic, but the board is reviewing it on Monday. I will confirm after that.")]),
    T("p_pipeline", "Recruitment: candidate pipeline Kanban", "Faisal Javed", "Sprint 22", "In Progress",
      who=[("Saad Qureshi", 3), ("Areeba Hameed", 1)], prio="normal", start=-5, due=3, est=12, tags=["frontend"],
      field={"Module": "Recruitment"}, time=[("Saad Qureshi", 4, 240, "Board layout"), ("Saad Qureshi", 1, 210, "Drag and drop")],
      comments=[("Areeba Hameed", "Nice progress @Saad Qureshi. Reuse the board from the roster screen for drag and drop.")]),
    T("p_mark_read", "Notifications inbox: mark all as read", "Faisal Javed", "Sprint 22", "Done",
      who=[("Saad Qureshi", 2)], prio="low", start=-9, due=-2, est=4, tags=["frontend"],
      time=[("Saad Qureshi", 7, 150, "Endpoint and button")]),
    T("p_rate_limit", "API rate limiting for public share links", "Faisal Javed", "Sprint 22", "Backlog",
      who=[("Zain Abbas", 3)], prio="normal", due=3, est=8, tags=["backend", "security"]),
    T("p_test_plan", "Test plan: update information requests", "Rabia Anwar", "Sprint 22", "In Progress",
      who=[("Mehwish Akram", 2)], prio="normal", start=-4, due=2, est=8,
      time=[("Mehwish Akram", 3, 180, "Positive cases"), ("Mehwish Akram", 1, 120, "Approval matrix")],
      comments=[("Rabia Anwar", "Good start @Mehwish Akram. Add cases for an employee on probation."),
                ("Mehwish Akram", "Added six probation cases.")]),
    T("p_playwright", "Automate sign-in and RBAC smoke tests (Playwright)", "Rabia Anwar", "Sprint 22", "In Progress",
      who=[("Danish Iqbal", 5)], prio="high", start=-10, due=-2, est=20, tags=["tech-debt"],
      ext=("approved", "Danish Iqbal", 5, "The staging environment was down for two days during the migration."),
      time=[("Danish Iqbal", 9, 240, "Framework set-up"), ("Danish Iqbal", 5, 300, "Role matrix tests"),
            ("Danish Iqbal", 0, 90, "CI job")]),
    T("p_swap_bug", "Shift swap request shows the wrong date", "Rabia Anwar", "Sprint 22", "Code Review",
      who=[("Zain Abbas", 2)], prio="high", start=-3, due=0, est=3, tags=["bug", "attendance"],
      comments=[("Danish Iqbal", "Reproduced with a night shift crossing midnight.")]),
    # Sprint 23: planned
    T("p_360", "Performance reviews: 360 feedback form", "Faisal Javed", "Sprint 23", "Backlog",
      who=[("Areeba Hameed", 8)], prio="normal", start=4, due=14, est=30, tags=["frontend", "customer-request"]),
    T("p_training_cal", "Training calendar view", "Faisal Javed", "Sprint 23", "Backlog",
      who=[("Saad Qureshi", 3)], prio="low", start=5, due=12, est=10, tags=["frontend"]),
    T("p_audit_csv", "Audit log export to CSV", "Faisal Javed", "Sprint 23", "Backlog",
      who=[("Zain Abbas", 3)], prio="normal", start=6, due=10, est=6, tags=["backend"]),
    T("p_s23_regr", "Sprint 23 regression plan", "Rabia Anwar", "Sprint 23", "Backlog",
      who=[("Danish Iqbal", 2)], prio="normal", due=16, est=6),
    T("p_v25", "v2.5 release", "Haroon Rashid", "Sprint 23", "Backlog", milestone=True, due=17, prio="high",
      who=["Haroon Rashid", "Faisal Javed"], desc="Self-service updates, performance reviews and the new dashboards."),
    # Mobile
    T("m_face", "Mobile: face check-in with geofence", "Faisal Javed", "Mobile v1.3", "In Progress",
      who=[("Hira Shahid", 8)], prio="high", start=-12, due=6, est=32, tags=["mobile", "attendance"],
      field={"Module": "Mobile"},
      subs=[T("m_face_cam", "Camera permission flow", "Hira Shahid", None, "Done", who=["Hira Shahid"], due=-5),
            T("m_face_geo", "Geofence radius setting per branch", "Hira Shahid", None, "In Progress", who=["Hira Shahid"], due=4),
            T("m_face_offline", "Offline punch queue", "Faisal Javed", None, "Backlog", who=["Saad Qureshi"], due=6)],
      time=[("Hira Shahid", 11, 300, "Camera flow"), ("Hira Shahid", 6, 240, "Liveness check spike"),
            ("Hira Shahid", 2, 180, "Geofence")],
      comments=[("Haroon Rashid", "Attendance stays biometric first; face check-in is for the field staff only. @Hira Shahid"),
                ("Hira Shahid", "Understood, it is behind a per-branch switch.", ["Haroon Rashid"])]),
    T("m_push", "Mobile: push notifications for approvals", "Faisal Javed", "Mobile v1.3", "Code Review",
      who=[("Hira Shahid", 5)], prio="normal", start=-8, due=2, est=12, tags=["mobile"],
      time=[("Hira Shahid", 7, 240, "FCM set-up")]),
    T("m_payslip", "Mobile: payslip download", "Faisal Javed", "Mobile v1.3", "Done",
      who=[("Hira Shahid", 3)], prio="normal", start=-12, due=-4, est=8, tags=["mobile", "payroll"], late=True,
      time=[("Hira Shahid", 9, 200, "Download and share sheet")]),
    T("m_dark", "Mobile: dark mode", "Faisal Javed", "Mobile v1.3", "In Progress",
      who=[("Hira Shahid", 2), ("Maham Zafar", 1)], prio="low", start=-6, due=-1, est=10, tags=["mobile", "ux"],
      comments=[("Maham Zafar", "Dark palette is in Figma, @Hira Shahid the contrast on chips still needs a pass.")]),
    T("m_crash", "Android 14 crash on the leave form", "Rabia Anwar", "Mobile v1.3", "QA Testing",
      who=[("Hira Shahid", 2), ("Mehwish Akram", 1)], prio="urgent", start=-2, due=0, est=4, tags=["mobile", "bug"],
      comments=[("Mehwish Akram", "Crash log attached in the ticket: date picker on Samsung devices.")]),
    T("m_fingerprint", "Mobile: fingerprint sign-in", "Faisal Javed", "Mobile Backlog", "Backlog", prio="normal",
      tags=["mobile", "security"]),
    T("m_ipad", "Tablet layout for managers", "Faisal Javed", "Mobile Backlog", "Backlog", prio="low", tags=["mobile"]),
    # Design
    T("d_tokens", "Design tokens v2 (colours, spacing)", "Omer Farooq", "Design System", "In Progress",
      who=[("Omer Farooq", 5)], prio="normal", start=-7, due=5, est=16, tags=["ux"],
      time=[("Omer Farooq", 6, 180, "Colour scales"), ("Omer Farooq", 2, 150, "Spacing")]),
    T("d_empty", "Empty state illustrations", "Omer Farooq", "Design System", "Done",
      who=[("Maham Zafar", 2)], prio="low", start=-15, due=-6, est=8, tags=["ux"]),
    T("d_usability", "Usability test: onboarding wizard", "Omer Farooq", "Design System", "Backlog",
      who=[("Maham Zafar", 3), ("Omer Farooq", 1)], prio="normal", start=5, due=9, est=8, tags=["ux"]),
    T("d_pm_handoff", "Figma handoff: Project Management screens", "Omer Farooq", "Design System", "Done",
      who=[("Omer Farooq", 3)], prio="high", start=-14, due=-6, est=12, tags=["ux"], late=True,
      comments=[("Areeba Hameed", "Thanks @Omer Farooq, the specs for the column menu are exactly what we needed.")]),
    # Quality
    T("q_v24", "v2.4 release regression", "Rabia Anwar", "Regression & Release QA", "Released",
      who=[("Danish Iqbal", 3), ("Mehwish Akram", 2)], prio="high", start=-16, due=-11, est=24,
      time=[("Danish Iqbal", 14, 360, "Payroll and attendance"), ("Mehwish Akram", 13, 300, "Leaves and requests")]),
    T("q_load", "Load test: payroll run with 500 employees", "Rabia Anwar", "Regression & Release QA", "In Progress",
      who=[("Danish Iqbal", 5)], prio="normal", start=-3, due=4, est=12, tags=["payroll"],
      time=[("Danish Iqbal", 2, 180, "k6 scripts")]),
    T("q_bugbash", "Bug bash: attendance module", "Rabia Anwar", "Regression & Release QA", "Backlog",
      who=["Rabia Anwar", "Danish Iqbal", "Mehwish Akram"], prio="normal", start=8, due=8, est=6,
      check=[("Book the meeting room", False), ("Prepare test accounts", False), ("Bring the biometric device", False)]),
]

POS_TASKS = [
    T("r_workshops", "Stakeholder workshops with the client", "Faisal Javed", "Requirements", "Completed",
      who=["Asad Mirza", "Faisal Javed"], prio="high", start=-40, due=-30, est=16, tags=["client-feedback"],
      comments=[("Asad Mirza", "Three workshops done: store ops, finance and IT. Notes are in the shared drive.")]),
    T("r_srs", "Sign off the requirements document (SRS)", "Faisal Javed", "Requirements", "Completed",
      who=["Faisal Javed"], prio="urgent", start=-30, due=-20, est=10, late=True, field={"Client Sign-off": True},
      comments=[("Faisal Javed", "Client signed v1.2 after two review rounds. @Haroon Rashid FYI, nine days late.")]),
    T("r_inventory", "Clarify inventory and stock transfer rules", "Asad Mirza", "Requirements", "Update Required",
      who=["Asad Mirza"], prio="high", start=-10, due=-5, est=6, tags=["client-feedback"],
      comments=[("Areeba Hameed", "@Asad Mirza we still need the rule for negative stock at a branch."),
                ("Asad Mirza", "Chasing their operations head; meeting on Monday.")]),
    T("r_wireframes", "Checkout screen wireframes", "Faisal Javed", "UX Design", "Completed",
      who=["Maham Zafar"], prio="high", start=-28, due=-18, est=12, tags=["ui"], field={"Client Sign-off": True}),
    T("r_uikit", "POS UI kit (touch-first)", "Faisal Javed", "UX Design", "In-Progress",
      who=["Omer Farooq", "Maham Zafar"], prio="normal", start=-12, due=3, est=24, tags=["ui"],
      time=[("Omer Farooq", 10, 240, "Buttons and keypad"), ("Maham Zafar", 6, 210, "Receipt preview")]),
    T("r_receipt", "Receipt template design", "Faisal Javed", "UX Design", "To Do",
      who=["Maham Zafar"], prio="low", start=4, due=7, est=6, tags=["ui"]),
    T("r_catalogue", "Product catalogue API", "Faisal Javed", "Backend API", "Completed",
      who=[("Zain Abbas", 5)], prio="high", start=-20, due=-8, est=20, tags=["api"],
      time=[("Zain Abbas", 17, 300, "Products and variants"), ("Zain Abbas", 12, 240, "Price lists")]),
    T("r_sales", "Sales and returns API", "Faisal Javed", "Backend API", "In-Progress",
      who=[("Zain Abbas", 8)], prio="high", start=-7, due=5, est=32, tags=["api"],
      subs=[T("r_sales_returns", "Returns with partial refunds", "Zain Abbas", None, "In-Progress", who=["Zain Abbas"], due=3),
            T("r_sales_z", "Daily Z-report endpoint", "Zain Abbas", None, "To Do", who=["Zain Abbas"], due=5)],
      time=[("Zain Abbas", 5, 270, "Sale posting")]),
    T("r_fbr", "FBR invoice integration", "Faisal Javed", "Backend API", "At Risk",
      who=[("Zain Abbas", 8)], prio="urgent", start=-6, due=2, est=24, tags=["integration", "blocker"],
      desc="Real-time invoice reporting to FBR (POS integration). Sandbox credentials from the client.",
      comments=[("Zain Abbas", "FBR sandbox has been timing out since yesterday. @Faisal Javed this may slip."),
                ("Faisal Javed", "@Asad Mirza can the client's tax consultant raise it with FBR?"),
                ("Asad Mirza", "Raised it this morning; they expect the sandbox back by Friday.")]),
    T("r_offline", "Offline sync for branch tills", "Faisal Javed", "Backend API", "Planning",
      who=[("Zain Abbas", 13)], prio="high", start=8, due=12, est=40, tags=["api"]),
    T("r_cashier", "Cashier sign-in and shift open / close", "Areeba Hameed", "POS Frontend", "In-Progress",
      who=[("Areeba Hameed", 5)], prio="normal", start=-5, due=4, est=16, tags=["ui"],
      time=[("Areeba Hameed", 4, 240, "Shift open"), ("Areeba Hameed", 1, 180, "Cash count")]),
    T("r_barcode", "Barcode scanner support", "Areeba Hameed", "POS Frontend", "To Do",
      who=[("Areeba Hameed", 3)], prio="normal", start=5, due=9, est=8),
    T("r_discounts", "Discounts and promotions engine UI", "Areeba Hameed", "POS Frontend", "Planning",
      who=[("Areeba Hameed", 8)], prio="normal", start=10, due=14, est=24, tags=["ui"]),
    T("r_uat_cases", "UAT test cases", "Faisal Javed", "UAT & Go-live", "In-Progress",
      who=["Danish Iqbal"], prio="normal", start=-3, due=6, est=16,
      time=[("Danish Iqbal", 2, 200, "Checkout and returns cases")]),
    T("r_golive", "Go-live checklist", "Faisal Javed", "UAT & Go-live", "To Do",
      who=["Faisal Javed"], prio="high", due=20, est=8,
      check=[("Tills imaged at three pilot stores", False), ("Cashier training done", False),
             ("FBR production credentials", False), ("Rollback plan signed off", False)]),
    T("r_pilot", "Pilot go-live: three stores", "Faisal Javed", "UAT & Go-live", "To Do", milestone=True,
      who=["Faisal Javed"], prio="urgent", due=21),
    T("r_weekly", "Client weekly status report", "Faisal Javed", "UAT & Go-live", "To Do",
      who=["Faisal Javed"], prio="normal", due=1, est=1, rec={"every": 1, "unit": "week", "weekdays": [5]}),
]

IT_TASKS = [
    T("i_switch", "Replace the core switch on the 2nd floor", "Waqas Butt", "Network & Servers", "Done",
      who=["Junaid Akhtar"], prio="high", start=-12, due=-5, est=8, tags=["network", "hardware"], late=True,
      time=[("Junaid Akhtar", 2, 240, "Cut-over on Saturday")],
      comments=[("Junaid Akhtar", "Vendor delivered the switch four days late; cut-over done, all ports tested.")]),
    T("i_firewall", "Firewall firmware upgrade (FortiGate)", "Waqas Butt", "Network & Servers", "Review",
      who=["Junaid Akhtar"], prio="normal", start=-3, due=1, est=3, tags=["network", "security"]),
    T("i_vpn", "Site-to-site VPN Lahore – Islamabad", "Waqas Butt", "Network & Servers", "In Progress",
      who=["Junaid Akhtar"], prio="high", start=-10, due=-2, est=12, tags=["network"],
      time=[("Junaid Akhtar", 8, 180, "Tunnel config"), ("Junaid Akhtar", 3, 120, "ISP ticket follow-up")],
      comments=[("Junaid Akhtar", "Islamabad ISP still has not opened UDP 500. @Waqas Butt can you escalate?"),
                ("Waqas Butt", "Escalated to their account manager.")]),
    T("i_backup", "Verify nightly SQL Server backups", "Waqas Butt", "Backups & Security", "Done",
      who=["Waqas Butt"], prio="normal", due=-1, est=1, rec={"every": 1, "unit": "week", "weekdays": [1]}),
    T("i_access", "Quarterly access review (AD accounts)", "Waqas Butt", "Backups & Security", "Not Started",
      who=["Waqas Butt"], prio="normal", start=3, due=6, est=6, tags=["security"]),
    T("i_mfa", "Enable MFA for email accounts", "Waqas Butt", "Backups & Security", "In Progress",
      who=["Junaid Akhtar"], prio="high", start=-5, due=8, est=10, tags=["security"],
      subs=[T("i_mfa_pilot", "Pilot with the IT team", "Waqas Butt", None, "Done", who=["Junaid Akhtar"], due=-2),
            T("i_mfa_all", "Roll out to all staff", "Waqas Butt", None, "Not Started", who=["Junaid Akhtar"], due=8)]),
    T("i_procure", "Procure 8 laptops for developers", "Waqas Butt", "Laptop Refresh 2026", "In Progress",
      who=["Waqas Butt", "Bilal Ahmed"], prio="normal", start=-8, due=10, est=6, tags=["hardware"],
      comments=[("Bilal Ahmed", "Three quotations received; the Dell one is cheapest with a 3-year warranty."),
                ("Waqas Butt", "Go with Dell. @Nadia Hussain the PO is on its way to you.")]),
    T("i_reimage", "Re-image laptops with Windows 11", "Waqas Butt", "Laptop Refresh 2026", "Not Started",
      who=["Junaid Akhtar"], prio="normal", start=11, due=14, est=8, tags=["hardware"]),
    T("i_ewaste", "Dispose of old hardware (e-waste vendor)", "Waqas Butt", "Laptop Refresh 2026", "Not Started",
      who=["Bilal Ahmed"], prio="low", due=20, est=3, tags=["hardware"]),
    T("i_ob_saad", "Laptop and accounts for Saad Qureshi", "Waqas Butt", "Onboarding Setups", "Closed",
      who=["Junaid Akhtar"], prio="normal", due="join:Saad Qureshi", tags=["onboarding"]),
    T("i_ob_mehwish", "Laptop and accounts for Mehwish Akram", "Waqas Butt", "Onboarding Setups", "Closed",
      who=["Junaid Akhtar"], prio="normal", due="join:Mehwish Akram", tags=["onboarding"]),
    T("i_printer", "Printer on the 3rd floor keeps jamming", "Junaid Akhtar", "Network & Servers", "Done",
      who=["Bilal Ahmed"], prio="low", due=-3, tags=["hardware"]),
]


# --------------------------------------------------------------------------- the seeding

class Pm:
    def __init__(self, w: World):
        self.w = w
        self.ws: dict[str, dict] = {}        # key -> {id, statuses, groups, folders, lists, tags, fields}
        self.tasks: dict[str, dict] = {}     # key -> last TaskOut
        self.names = sorted(w.employees, key=len, reverse=True)
        self.counts = dict(workspaces=0, folders=0, lists=0, tasks=0, subtasks=0, comments=0, time_entries=0,
                           reminders=0, favourites=0, docs=0, notes=0, personal_items=0, recents=0, attachments=0,
                           extensions=0, checklist=0)

    def eid(self, name: str) -> int:
        return self.w.emp_id(name)

    def mentions(self, text: str) -> list[dict]:
        found = []
        for n in self.names:
            if f"@{n}" in text and n not in found:
                found.append(n)
        return [{"employeeId": self.eid(n)} for n in found]

    # ---- workspaces

    def workspace(self, spec: dict) -> None:
        w = self.w
        owner = w.as_(spec["owner"])
        body = {"name": spec["name"], "description": spec["description"], "privacy": spec["privacy"],
                "ownerId": self.eid(spec["owner"]), "departmentId": int(w.departments[spec["dept"]]["id"]),
                "workflowTemplate": spec["template"],
                "members": [{"employeeId": self.eid(n), "memberRole": r} for n, r in spec["members"]]}
        if spec.get("statuses"):
            body |= {"statusMode": "custom", "statuses": [{"name": n, "statusGroup": g, "color": c}
                                                          for n, g, c in spec["statuses"]]}
        elif spec.get("status_template"):
            body |= {"statusMode": "custom", "statusTemplate": spec["status_template"]}
        ws = owner("POST", "/projects/workspaces", body)["data"]
        info = dict(id=int(ws["id"]), spec=spec, statuses={s["name"]: int(s["id"]) for s in ws["statuses"]},
                    groups={s["name"]: s["statusGroup"] for s in ws["statuses"]}, folders={}, lists={}, tags={},
                    fields={})
        info["active"] = next(n for n, g in info["groups"].items() if g == "active")
        self.ws[spec["key"]] = info
        self.counts["workspaces"] += 1
        wid = info["id"]
        for name, colour in spec["tags"]:
            info["tags"][name] = int(owner("POST", f"/projects/workspaces/{wid}/tags", {"name": name, "color": colour})["data"]["id"])
        for name, ftype, config in spec["fields"]:
            info["fields"][name] = int(owner("POST", f"/projects/workspaces/{wid}/custom-fields",
                                             {"name": name, "fieldType": ftype, "config": config})["data"]["id"])
        if spec.get("overdue"):
            penalty, max_ext = spec["overdue"]
            owner("PUT", f"/projects/workspaces/{wid}/settings/overdue", {"penaltyPercent": penalty, "maxExtensions": max_ext})
        members = [self.eid(spec["owner"])] + [self.eid(n) for n, _ in spec["members"]]
        for order, (folder, by, lists) in enumerate(STRUCTURE[spec["key"]], start=1):
            f = w.as_(by)("POST", f"/projects/workspaces/{wid}/folders", {"name": folder, "sortOrder": order * 10})["data"]
            info["folders"][folder] = int(f["id"])
            self.counts["folders"] += 1
            for lorder, (name, lby, start, end, colour, prio, desc) in enumerate(lists, start=1):
                body = {"name": name, "folderId": int(f["id"]), "color": colour, "description": desc, "priority": prio,
                        "sortOrder": lorder * 10, "memberIds": members,
                        "startAt": at(day(w, start, False), 9) if start is not None else None,
                        "endAt": at(day(w, end, False), 18) if end is not None else None}
                info["lists"][name] = int(w.as_(lby)("POST", f"/projects/workspaces/{wid}/lists", body)["data"]["id"])
                self.counts["lists"] += 1

    # ---- tasks

    def due(self, value: Any):
        if value is None:
            return None
        if isinstance(value, str) and value.startswith("join:"):
            person = next(p for p in self.w.people if f"{p['first']} {p['last']}" == value[5:])
            return day(self.w, (date.fromisoformat(person["joined"]) - timedelta(days=1) - self.w.today).days)
        return day(self.w, value)

    def task(self, info: dict, spec: dict, parent: dict | None = None) -> dict:
        w = self.w
        api = w.as_(spec["by"])
        status = spec["status"]
        group = info["groups"][status]
        late = spec.get("late", False)
        create_status = info["active"] if late else status
        who = [x if isinstance(x, tuple) else (x, None) for x in spec.get("who", [])]
        est = spec.get("est")
        body = {"name": spec["name"], "description": spec.get("desc"), "priority": spec.get("prio"),
                "taskType": "milestone" if spec.get("milestone") else "task",
                "startDate": iso(self.due(spec.get("start"))), "dueDate": iso(self.due(spec.get("due"))),
                "timeEstimateMinutes": est * 60 if est else None, "statusId": info["statuses"][create_status],
                "tagIds": [info["tags"][t] for t in spec.get("tags", [])], "recurrence": spec.get("rec"),
                "url": spec.get("url")}
        if body["startDate"] and body["dueDate"] and body["startDate"] > body["dueDate"]:
            body["startDate"] = body["dueDate"]
        if parent:
            body["parentTaskId"] = int(parent["id"])
            if [n for n, _ in who] == [spec["by"]]:
                body["assigneeIds"] = [self.eid(spec["by"])]   # a contributor adds a subtask for themselves
                who = []
        else:
            body |= {"workspaceId": info["id"], "taskListId": info["lists"][spec["list"]] if spec.get("list") else None}
        t = api("POST", "/projects/tasks", body)["data"]
        tid = int(t["id"])
        self.counts["subtasks" if parent else "tasks"] += 1
        if who:
            t = api("PUT", f"/projects/tasks/{tid}/assignees", {"assignees": [
                {"employeeId": self.eid(n), "storyPoints": sp} for n, sp in who]})["data"]
        for fname, value in spec.get("field", {}).items():
            t = api("PUT", f"/projects/tasks/{tid}/fields/{info['fields'][fname]}", {"value": value})["data"]
        for n, (text, done) in enumerate(spec.get("check", []), start=1):
            item = api("POST", f"/projects/tasks/{tid}/checklist", {"itemText": text, "sortOrder": n * 10})["data"]
            self.counts["checklist"] += 1
            if done:
                doer = w.as_(who[0][0]) if who else api
                doer("PUT", f"/projects/checklist-items/{item['id']}", {"itemText": text, "isDone": True,
                                                                       "sortOrder": n * 10, "rowVersion": item["rowVersion"]})
        for who_name, ago, minutes, note in spec.get("time", []):
            w.as_(who_name)("POST", f"/projects/tasks/{tid}/time-entries", {
                "startAt": at(day(w, -ago), 10 + (ago % 4)), "minutes": minutes, "notes": note})
            self.counts["time_entries"] += 1
        for c in spec.get("comments", []):
            author, text = c[0], c[1]
            out = w.as_(author)("POST", f"/projects/tasks/{tid}/comments", {"body": text, "mentions": self.mentions(text)})["data"]
            self.counts["comments"] += 1
            for reactor in (c[2] if len(c) > 2 else []):
                w.as_(reactor)("PUT", f"/projects/comments/{out['id']}/reaction", {"reaction": "👍"})
        for sub in spec.get("subs", []):
            self.task(info, sub, t)
        if late and group in ("done", "closed"):
            closer = w.as_(who[0][0]) if who else api
            current = closer("GET", f"/projects/tasks/{tid}")["data"]
            t = closer("PATCH", f"/projects/tasks/{tid}/status", {"statusId": info["statuses"][status],
                                                                    "rowVersion": current["rowVersion"]})["data"]
        if spec.get("ext"):
            state, requester, new_due, reason = spec["ext"]
            t = w.as_(requester)("POST", f"/projects/tasks/{tid}/extension-requests",
                                 {"newDueDate": iso(day(w, new_due)), "reason": reason})["data"]
            self.counts["extensions"] += 1
            if state == "approved":
                ext = next(e for e in t["extensions"] if e["status"] == "pending")
                approver = w.as_(info["spec"]["owner"] if spec["by"] == requester else spec["by"])
                t = approver("PATCH", f"/projects/extension-requests/{ext['id']}/approve",
                             {"remarks": "Approved; keep the team posted in stand-up.", "rowVersion": ext["rowVersion"]})["data"]
        self.tasks[spec["key"]] = t
        return t

    def tid(self, key: str) -> int:
        return int(self.tasks[key]["id"])


def seed(w: World) -> dict:
    pm = Pm(w)
    for spec, tasks in ((HRANGO, PRODUCT_TASKS), (POS, POS_TASKS), (ITOPS, IT_TASKS)):
        pm.workspace(spec)
        info = pm.ws[spec["key"]]
        for t in tasks:
            pm.task(info, t)
    _extras(w, pm)
    return pm.counts


def _extras(w: World, pm: Pm) -> None:
    """Dependencies, a few replies and resolved comments, attachments, docs, reminders, favourites, notes,
    personal lists, saved views and recents."""
    product, pos, it = pm.ws["product"], pm.ws["pos"], pm.ws["it"]
    c = pm.counts

    # Dependencies: the barcode screen waits on the catalogue API (done); go-live waits on UAT cases.
    w.as_("Areeba Hameed")("POST", f"/projects/tasks/{pm.tid('r_barcode')}/dependencies",
                           {"otherTaskId": pm.tid("r_catalogue"), "kind": "waiting_on"})
    w.as_("Faisal Javed")("POST", f"/projects/tasks/{pm.tid('r_golive')}/dependencies",
                          {"otherTaskId": pm.tid("r_uat_cases"), "kind": "waiting_on"})
    w.as_("Faisal Javed")("POST", f"/projects/tasks/{pm.tid('p_ss_tests')}/dependencies",
                          {"otherTaskId": pm.tid("p_ss_flow"), "kind": "waiting_on"})
    w.as_("Rabia Anwar")("POST", f"/projects/tasks/{pm.tid('p_test_plan')}/dependencies",
                         {"otherTaskId": pm.tid("p_self_service"), "kind": "linked"})

    # A comment assigned to someone, a reply, and one resolved.
    faisal, zain = w.as_("Faisal Javed"), w.as_("Zain Abbas")
    asked = faisal("POST", f"/projects/tasks/{pm.tid('r_fbr')}/comments", {
        "body": "@Zain Abbas please write down the fallback if FBR is down at go-live (queue and resend).",
        "mentions": pm.mentions("@Zain Abbas"), "assignedToId": pm.eid("Zain Abbas")})["data"]
    zain("POST", f"/projects/tasks/{pm.tid('r_fbr')}/comments", {
        "body": "Drafted it in the Client Requirements doc, section 6.", "parentId": int(asked["id"])})
    resolved = w.as_("Danish Iqbal")("POST", f"/projects/tasks/{pm.tid('p_swap_bug')}/comments", {
        "body": "Also happens for split shifts, please cover both in the fix @Zain Abbas.",
        "mentions": pm.mentions("@Zain Abbas")})["data"]
    w.as_("Danish Iqbal")("PATCH", f"/projects/comments/{resolved['id']}/resolve", {"resolved": True})
    w.as_("Haroon Rashid")("POST", f"/projects/tasks/{pm.tid('p_encash')}/comments", {
        "body": "Linking the payroll bank file work for context.", "mentions": [{"taskId": pm.tid("p_bank_file")}]})
    c["comments"] += 4

    # Attachments: a wireframe and two PDFs uploaded first, plus a Google Drive link.
    maham, omer, mehwish = w.as_("Maham Zafar"), w.as_("Omer Farooq"), w.as_("Mehwish Akram")
    wire = upload(maham, "checkout-wireframe.png", png(480, 300, (245, 247, 250), (225, 230, 238), [
        (20, 20, 280, 40, (47, 99, 154)), (20, 80, 280, 190, (255, 255, 255)), (320, 20, 140, 260, (255, 255, 255)),
        (330, 220, 120, 50, (49, 136, 69)), (30, 95, 260, 18, (220, 224, 230)), (30, 125, 260, 18, (220, 224, 230)),
        (30, 155, 200, 18, (220, 224, 230))]), "image/png", "projects")
    maham("POST", f"/projects/tasks/{pm.tid('r_wireframes')}/attachments", {"fileId": int(wire["id"])})
    kit = upload(omer, "POS UI kit v0.3.pdf", pdf("Retail POS - UI kit v0.3", [
        "Touch targets: 56 px minimum, keypad 72 px.", "Colours: primary #2F639A, success #318845, danger #DC3545.",
        "Screens: sign-in, shift open, sale, payment, receipt, returns.", "Owner: Omer Farooq, UI/UX Design."]),
        "application/pdf", "projects")
    omer("POST", f"/projects/tasks/{pm.tid('r_uikit')}/attachments", {"fileId": int(kit["id"])})
    plan = upload(mehwish, "Test plan - update information requests.pdf", pdf("Test plan: update information requests", [
        "Scope: employee request, HR approval, rejection, audit trail.", "42 cases: 30 positive, 12 negative.",
        "Includes six cases for employees on probation.", "Prepared by Mehwish Akram, reviewed by Rabia Anwar."]),
        "application/pdf", "projects")
    mehwish("POST", f"/projects/tasks/{pm.tid('p_test_plan')}/attachments", {"fileId": int(plan["id"])})
    faisal("POST", f"/projects/tasks/{pm.tid('r_srs')}/attachments/link", {
        "provider": "google_drive", "externalId": "1RetailPOS-SRS-v1-2", "name": "Retail POS SRS v1.2 (signed).pdf",
        "webUrl": "https://drive.google.com/file/d/1RetailPOS-SRS-v1-2/view", "mimeType": "application/pdf"})
    c["attachments"] += 4

    # Docs, with linked tasks and a few comments.
    docs = [
        (product, "Haroon Rashid", "Release notes v2.4", "Web App", [
            "<h1>hRango v2.4</h1><p>Released to all customers this month.</p>",
            "<h2>New</h2><ul><li>Biometric punches are retried when a device loses its link.</li>"
            "<li>HBL bank file from an approved payroll run.</li><li>Redesigned leave balance cards.</li></ul>",
            "<h2>Fixed</h2><ul><li>Time sheet dates drifting across time zones.</li></ul>"],
         ["p_bio_sync", "p_bank_file", "p_leave_card", "p_tz_fix"]),
        (product, "Faisal Javed", "Sprint 22 planning notes", "Web App", [
            "<h1>Sprint 22</h1><p>Goal: self-service updates ready for QA, PM list view in review.</p>",
            "<h2>Capacity</h2><p>Zain 8 days, Areeba 9 days, Saad 10 days, Hira on mobile.</p>",
            "<h2>Risks</h2><ul><li>Leave encashment rule pending Finance.</li></ul>"],
         ["p_self_service", "p_pm_list", "p_encash"]),
        (product, "Zain Abbas", "API style guide", None, [
            "<h1>API style guide</h1><p>camelCase JSON, ids as strings, one envelope for items and pages.</p>",
            "<h2>Errors</h2><p>422 with fieldErrors, 409 for conflicts, never 500 for user mistakes.</p>"], []),
        (pos, "Faisal Javed", "Client requirements summary", "Phase 1 – Discovery", [
            "<h1>Retail POS: requirements summary</h1><p>40 stores, 120 tills, central inventory.</p>",
            "<h2>Must have</h2><ul><li>FBR real-time invoices.</li><li>Offline sales for up to 24 hours.</li>"
            "<li>Returns with partial refunds.</li></ul><h2>6. FBR fallback</h2><p>Queue invoices and resend.</p>"],
         ["r_srs", "r_fbr", "r_offline"]),
        (pos, "Asad Mirza", "Meeting minutes – week 6", "Phase 2 – Build", [
            "<h1>Weekly client call</h1><p>Attendees: client IT and operations, Faisal, Asad, Zain.</p>",
            "<ul><li>UI kit approved with minor changes.</li><li>Pilot stores: Gulberg, DHA, Johar Town.</li></ul>"],
         ["r_uikit", "r_pilot"]),
        (it, "Junaid Akhtar", "Network diagram and IP plan", "Infrastructure", [
            "<h1>Network</h1><p>Lahore 10.10.0.0/16, Islamabad 10.20.0.0/16, VPN between the two.</p>",
            "<h2>VLANs</h2><ul><li>10 staff</li><li>20 servers</li><li>30 biometric devices</li><li>40 guests</li></ul>"],
         ["i_vpn", "i_switch"]),
        (it, "Waqas Butt", "New joiner IT checklist", "Helpdesk", [
            "<h1>New joiner IT checklist</h1><ol><li>Laptop imaged and asset-tagged.</li><li>Email with MFA.</li>"
            "<li>Biometric enrolment at reception.</li><li>VPN for remote days.</li></ol>"],
         ["i_ob_saad", "i_ob_mehwish"]),
    ]
    made_docs = {}
    for info, owner, title, folder, html, links in docs:
        api = w.as_(owner)
        body_html = "".join(html)
        doc = api("POST", f"/projects/workspaces/{info['id']}/docs", {
            "title": title, "contentHtml": body_html, "visibility": "workspace",
            "folderId": info["folders"].get(folder) if folder else None,
            "content": {"type": "doc", "content": [  # ProseMirror JSON: one paragraph per block, as plain text
                {"type": "paragraph", "content": [{"type": "text", "text": " ".join(re.sub(r"<[^>]+>", " ", part).split())}]}
                for part in html]},
            "settings": {"fontFamily": "Inter", "fontSize": 14, "header": {"title": True, "owner": True, "toc": True}}})["data"]
        if links:
            api("PUT", f"/projects/docs/{doc['id']}/tasks", {"taskIds": [pm.tid(k) for k in links]})
        made_docs[title] = int(doc["id"])
        c["docs"] += 1
    for title, author, text in [("Release notes v2.4", "Rabia Anwar", "Added the regression scope to the QA section."),
                                ("Sprint 22 planning notes", "Areeba Hameed", "I am out on Friday, please plan around it."),
                                ("Client requirements summary", "Zain Abbas", "Section 6 drafted, please review."),
                                ("Network diagram and IP plan", "Waqas Butt", "Add the printer VLAN as well.")]:
        w.as_(author)("POST", f"/projects/docs/{made_docs[title]}/comments", {"body": text})

    # Reminders: some due within hours, some later this week.
    now = datetime.now().replace(second=0, microsecond=0)
    soon = lambda hours: (now + timedelta(hours=hours)).isoformat()  # noqa: E731
    reminders = [
        ("Zain Abbas", "task", pm.tid("p_self_service"), "Open the PR for the approval flow", soon(2), None, 15, "soft"),
        ("Faisal Javed", "task", pm.tid("r_fbr"), "Check FBR sandbox status with Zain", soon(20), "Zain Abbas", 30, "hard"),
        ("Hira Shahid", "task", pm.tid("m_push"), "Test push approvals on the Samsung device", soon(3), None, 10, "soft"),
        ("Danish Iqbal", "task", pm.tid("q_load"), "Run the 500-employee payroll load test", at(day(w, 2), 11), None, 30, "soft"),
        ("Waqas Butt", "task", pm.tid("i_access"), "Export AD accounts for the access review", at(day(w, 4), 10), None, 60, "soft"),
        ("Haroon Rashid", "task_list", product["lists"]["Sprint 22"], "Sprint 22 demo and retro", at(day(w, 3), 16),
         None, 60, "hard"),
        ("Rabia Anwar", "task", pm.tid("q_load"), "Review the load test results with Danish", soon(5), "Danish Iqbal", 15, "soft"),
        ("Asad Mirza", "workspace", pos["id"], "Weekly client call", at(day(w, 1), 15), None, 30, "soft"),
    ]
    for owner, etype, eid, name, when, assignee, before, kind in reminders:
        w.as_(owner)("POST", "/projects/reminders", {
            "entityType": etype, "entityId": eid, "name": name, "remindAt": when,
            "assigneeId": pm.eid(assignee) if assignee else None, "notifyBeforeMinutes": before, "reminderKind": kind})
        c["reminders"] += 1

    # Favourites and a hidden workspace.
    favourites = [
        ("Haroon Rashid", "workspace", product["id"]), ("Haroon Rashid", "task_list", product["lists"]["Sprint 22"]),
        ("Haroon Rashid", "workspace", pos["id"]), ("Faisal Javed", "workspace", pos["id"]),
        ("Faisal Javed", "task", pm.tid("r_fbr")), ("Faisal Javed", "folder", product["folders"]["Web App"]),
        ("Zain Abbas", "task", pm.tid("p_self_service")), ("Zain Abbas", "task", pm.tid("r_fbr")),
        ("Zain Abbas", "task_list", product["lists"]["Sprint 22"]), ("Areeba Hameed", "task", pm.tid("p_pm_list")),
        ("Areeba Hameed", "workspace", product["id"]), ("Hira Shahid", "task_list", product["lists"]["Mobile v1.3"]),
        ("Danish Iqbal", "task", pm.tid("p_playwright")), ("Rabia Anwar", "folder", product["folders"]["Quality"]),
        ("Waqas Butt", "workspace", it["id"]), ("Junaid Akhtar", "task", pm.tid("i_vpn")),
        ("Omer Farooq", "task_list", product["lists"]["Design System"]),
    ]
    for person, etype, eid in favourites:
        w.as_(person)("PUT", "/projects/favorites", {"entityType": etype, "entityId": eid, "kind": "favorite", "on": True},
                      ok=(204,))
        c["favourites"] += 1
    w.as_("Shelley Kannes")("PUT", "/projects/favorites", {"entityType": "workspace", "entityId": it["id"],
                                                           "kind": "hidden", "on": True}, ok=(204,))

    # Saved views: a shared board for the sprint, a private "my bugs" list.
    w.as_("Haroon Rashid")("POST", f"/projects/workspaces/{product['id']}/views", {
        "viewType": "board", "name": "Sprint 22 board", "taskListId": product["lists"]["Sprint 22"], "isPinned": True,
        "config": {"groupBy": "status", "subtasks": "collapsed"}})
    w.as_("Danish Iqbal")("POST", f"/projects/workspaces/{product['id']}/views", {
        "viewType": "list", "name": "My open bugs", "isPrivate": True,
        "config": {"filters": {"tagIds": [str(product["tags"]["bug"])], "statusGroups": ["not_started", "active"]},
                   "groupBy": "priority", "sortBy": "due_date"}})

    # Notes (Notepad), one edited twice so it has history.
    notes = [
        ("Haroon Rashid", "1:1 talking points – Faisal", "<ul><li>Hiring a second backend engineer</li>"
         "<li>Retail POS risk: FBR</li><li>Saad's probation review next week</li></ul>"),
        ("Faisal Javed", "Sprint 22 retro ideas", "<ul><li>Start: pairing on payroll tasks</li>"
         "<li>Stop: merging on Fridays</li><li>Keep: daily 10-minute stand-up</li></ul>"),
        ("Zain Abbas", "SQL Server tips", "<p>Use OPTION (RECOMPILE) on list procedures with optional filters.</p>"),
        ("Rabia Anwar", "QA hiring – interview questions", "<ol><li>Explain a bug you found that others missed.</li>"
         "<li>How do you test a payroll calculation?</li></ol>"),
        ("Waqas Butt", "Vendors and contacts", "<p>ISP Islamabad: account manager, ticket 44812. Dell partner: quotes by Friday.</p>"),
    ]
    for person, title, html in notes:
        api = w.as_(person)
        note = api("POST", "/projects/notes", {"title": title, "contentHtml": html})["data"]
        c["notes"] += 1
        if person == "Faisal Javed":
            api("PUT", f"/projects/notes/{note['id']}", {"title": title, "contentHtml": html + "<p>Action: rotate the demo host.</p>",
                                                         "rowVersion": note["rowVersion"]})

    # Personal lists.
    personal = {
        "Haroon Rashid": [("Approve Q4 hiring plan", 1, False), ("Review Retail POS budget", 2, False),
                          ("Sign the AWS reserved instance renewal", -1, True), ("Prepare board update slides", 5, False)],
        "Faisal Javed": [("Code review: list view PR", 0, True), ("Call client about FBR sandbox", 1, False),
                         ("Update sprint burndown", 3, False)],
        "Zain Abbas": [("Read FBR POS integration spec", 0, False), ("Renew SSL certificate on staging", 2, False),
                       ("Book dentist appointment", 6, True)],
        "Areeba Hameed": [("Pair with Saad on drag and drop", 1, False), ("Write the list view docs", 4, False)],
        "Waqas Butt": [("Collect Dell quotation", -2, True), ("Renew antivirus licences", 9, False),
                       ("Escalate ISP ticket", 0, False)],
        "Shelley Kannes": [("Review update request rules with Zain", 1, False), ("Offsite venue shortlist", 7, False)],
    }
    for person, items in personal.items():
        api = w.as_(person)
        for title, due, done in items:
            item = api("POST", "/projects/personal-list", {"title": title, "dueDate": iso(day(w, due))})["data"]
            c["personal_items"] += 1
            if done:
                api("PATCH", f"/projects/personal-list/{item['id']}", {"done": True, "rowVersion": item["rowVersion"]})

    # Recents: what people opened lately (oldest first, so the newest is last).
    recents = {
        "Haroon Rashid": [("workspace", pos["id"]), ("doc", made_docs["Release notes v2.4"]), ("task", pm.tid("p_v25")),
                          ("task_list", product["lists"]["Sprint 22"]), ("workspace", product["id"])],
        "Faisal Javed": [("task", pm.tid("p_pm_list")), ("doc", made_docs["Client requirements summary"]),
                         ("task", pm.tid("r_fbr")), ("task_list", product["lists"]["Sprint 22"]), ("workspace", pos["id"])],
        "Zain Abbas": [("task", pm.tid("p_encash")), ("task", pm.tid("r_sales")), ("task", pm.tid("r_fbr")),
                       ("task", pm.tid("p_self_service"))],
        "Areeba Hameed": [("task", pm.tid("r_cashier")), ("task", pm.tid("p_dash_widgets")), ("task", pm.tid("p_pm_list"))],
        "Hira Shahid": [("task", pm.tid("m_push")), ("task", pm.tid("m_face")), ("task_list", product["lists"]["Mobile v1.3"])],
        "Danish Iqbal": [("task", pm.tid("r_uat_cases")), ("task", pm.tid("p_urdu_pdf")), ("task", pm.tid("p_playwright"))],
        "Waqas Butt": [("folder", it["folders"]["Helpdesk"]), ("task", pm.tid("i_vpn")), ("workspace", it["id"])],
        "Junaid Akhtar": [("doc", made_docs["Network diagram and IP plan"]), ("task", pm.tid("i_mfa")), ("task", pm.tid("i_vpn"))],
    }
    for person, items in recents.items():
        api = w.as_(person)
        for etype, eid in items:
            api("POST", "/projects/recents", {"entityType": etype, "entityId": eid}, ok=(204,))
            c["recents"] += 1
