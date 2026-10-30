"""Set-up of the leave_requests demo part: leave types, policies, allotment and opening balances; Request
Settings (authorities, flows, restrictions, delegation, expense categories, reimbursement pay items);
loan & advance types and categories; the approval rights the CEO and the Admin Officer need."""
from datetime import date, timedelta

from scripts.demo_data._leave_requests_common import Ctx

# Leave types. While the history is filed every type accepts back-dated applications (the demo files
# months of history today); `final` holds the rules the company really runs with, saved afterwards.
LEAVE_TYPES = [
    dict(title="Annual Leave", shortCode="AL", allowance=14, autoAllotment=True, autoBalanceOnJoining=True,
         proRated=True, isDeductible=True, showInPayslip=True, allowEncashment=True, encashmentMin=2,
         encashmentMax=10, carryForward=True, accumulativeCount=2, hasFutureLimit=True, futureLimitDays=120,
         final=dict(allowBackDate=False, backDateLimitDays=None)),
    dict(title="Casual Leave", shortCode="CL", allowance=10, autoAllotment=True, autoBalanceOnJoining=True,
         proRated=True, isDeductible=True, showInPayslip=True, isShortLeave=True, allowedInProbation=True,
         shortSlabs=[{"name": "Half day", "balance": 0.5, "valueType": "percentage", "value": 50},
                     {"name": "Short leave (2 hours)", "balance": 0.25, "valueType": "percentage", "value": 25}],
         final=dict(allowBackDate=True, backDateLimitDays=3)),
    dict(title="Sick Leave", shortCode="SL", allowance=8, autoAllotment=True, isDeductible=True, showInPayslip=True,
         allowedInProbation=True, attachmentRequired=True, attachmentRule="note",
         final=dict(allowBackDate=True, backDateLimitDays=7)),
    dict(title="Maternity Leave", shortCode="ML", allowance=90, autoAllotment=True, isDeductible=True,
         gender="female", maritalStatus="married", minExperienceMonths=6, maxApplications=3,
         attachmentRequired=True, attachmentRule="note", final=dict(allowBackDate=False, backDateLimitDays=None)),
    dict(title="Paternity Leave", shortCode="PL", allowance=5, autoAllotment=True, isDeductible=True,
         gender="male", maritalStatus="married", minExperienceMonths=6,
         final=dict(allowBackDate=True, backDateLimitDays=15)),
    dict(title="Unpaid Leave", shortCode="UL", allowance=0, isDeductible=False, showInPayslip=True,
         allowedInProbation=True, final=dict(allowBackDate=True, backDateLimitDays=30)),
]

LOAN_CATEGORIES = [("Medical", "Treatment and hospital bills of the employee or family."),
                   ("Education", "Fees for the employee's or children's education."),
                   ("Marriage", "Own or a dependant's wedding."),
                   ("House Renovation", "Repairs and renovation of the employee's home."),
                   ("Vehicle", "Buying or repairing a car or motorbike."),
                   ("Family Emergency", "Unplanned family expenses.")]

LOAN_TYPES = [
    dict(name="Personal Loan", guarantorRequired=False, minExperienceMonths=12, gapBetweenRequestsMonths=12,
         installments=12, description="Up to three gross salaries, repaid over 12 months through payroll."),
    dict(name="Vehicle Loan", guarantorRequired=True, minExperienceMonths=24, gapBetweenRequestsMonths=36,
         installments=36, description="Car or motorbike purchase, repaid over 36 months; one guarantor."),
    dict(name="Advance Salary", guarantorRequired=False, minExperienceMonths=3, gapBetweenRequestsMonths=3,
         installments=1, description="Up to one month's net salary, recovered from the next payslip."),
]

EXPENSE_CATEGORIES = [
    ("Travel Fee", 50000, False, "Local taxis, ride-hailing and intercity fares on company work."),
    ("Fuel & Mileage", 15000, False, "Fuel for an own vehicle used on company work."),
    ("Client Entertainment", 25000, True, "Meals and hospitality for clients; receipt required."),
    ("Internet & Mobile", 5000, False, "Monthly mobile data and home internet for remote work."),
    ("Tech & Software", 60000, True, "Software licences and subscriptions; receipt required."),
    ("Equipment & Supplies", 30000, False, "Small tools and supplies bought for the office."),
    ("Training & Certification", 80000, True, "Course and exam fees approved by the line manager."),
]


def _type_body(spec: dict, back_date: bool) -> dict:
    body = {k: v for k, v in spec.items() if k != "final"}
    if back_date:
        body.update(allowBackDate=True, backDateLimitDays=150)
    else:
        body.update(spec["final"])
    return body


def setup_leaves(c: Ctx) -> None:
    w, admin = c.w, c.w.admin
    admin("PUT", "/leaves/settings", {"finalApprovalBy": "hr_manager", "approveOnStatus": "approved",
                                     "postDeadline": True})
    existing = {t["title"]: t for t in admin.all("/leaves/types")}
    types = {}
    for spec in LEAVE_TYPES:
        if spec["title"] in existing:
            types[spec["title"]] = existing[spec["title"]]
            continue
        types[spec["title"]] = admin("POST", "/leaves/types", _type_body(spec, back_date=True))["data"]
    c.ids["leave"] = {t: int(x["id"]) for t, x in types.items()}
    lt = c.ids["leave"]

    policies = {p["title"]: p for p in admin.all("/leaves/policies")}
    everyone = [t for t in lt]

    def policy(title, level, kind="distribution", allowances=None, half=False, short=False):
        if title in policies:
            return policies[title]
        body = {"title": title, "policyKind": kind, "policyLevel": level, "allowHalfDay": half,
                "allowShortLeave": short, "isActive": True,
                "types": [{"leaveTypeId": lt[t], "allowance": (allowances or {}).get(t)} for t in everyone]
                if kind == "distribution" else []}
        return admin("POST", "/leaves/policies", body)["data"]

    policy("Standard Leave Policy", "company")
    senior = policy("Leadership Leave Policy", "employee",
                    allowances={"Annual Leave": 18, "Sick Leave": 10})
    probation = policy("Probation Leave Policy", "employee",
                       allowances={"Casual Leave": 5, "Sick Leave": 4})
    policy("Half Day & Short Leave Policy", "company", kind="half_short", half=True, short=True)

    leaders = [n for n, e in w.employees.items() if e.get("gradeName") in ("G5", "G6")] or \
        ["Imran Siddiqui", "Shelley Kannes", "Nadia Hussain", "Haroon Rashid", "Asad Mirza"]
    probationers = [n for n, e in w.employees.items() if e.get("status") == "probation"]
    for pol, names in ((senior, leaders), (probation, probationers)):
        if names and not int(pol.get("enrolledCount") or 0):
            admin("POST", f"/leaves/policies/{pol['id']}/employees", {"employeeIds": [c.eid(n) for n in names]})

    # The leave year follows the company's fiscal year (lv.fn_leave_year). Allot every leave year the
    # history and the upcoming applications fall in.
    me = admin("GET", "/auth/me")["data"]
    company = admin("GET", f"/organisation/companies/{me['companyId']}")["data"]
    c.fy_start = int(company.get("fiscalYearStartMonth") or 1)
    years = sorted({c.leave_year(w.days_ago(130)), c.leave_year(w.today), c.leave_year(w.today + timedelta(days=60))})
    for year in years:
        admin("POST", "/leaves/allotment/process", {"fiscalYear": year})

    # Annual leave carried over from last year for a few people, and one adjustment.
    year = c.leave_year(w.today)
    label = str(year - 1) if c.fy_start == 1 else f"{year - 1}-{year % 100:02d}"
    if not admin.all(f"/leaves/ledger?reason=opening&fiscalYear={year}"):
        for name, days in (("Areeba Hameed", 4), ("Faisal Javed", 6), ("Danish Iqbal", 3), ("Junaid Akhtar", 5),
                           ("Rabia Anwar", 7), ("Omer Farooq", 2), ("Usman Ghani", 4), ("Komal Shah", 2)):
            admin("POST", "/leaves/ledger", {"employeeId": c.eid(name), "leaveTypeId": lt["Annual Leave"],
                                            "entryDate": date(year, c.fy_start, 1).isoformat(), "days": days,
                                            "reason": "opening", "remarks": f"Carried forward from {label}"})
        admin("POST", "/leaves/ledger", {"employeeId": c.eid("Junaid Akhtar"), "leaveTypeId": lt["Casual Leave"],
                                        "entryDate": c.day(9, 5).isoformat(), "days": 1, "reason": "adjustment",
                                        "remarks": "Compensatory day for the weekend network migration"})


def finalise_leave_types(c: Ctx) -> None:
    """The real back-date rules, once the history is in."""
    admin = c.w.admin
    for spec in LEAVE_TYPES:
        tid = c.ids["leave"][spec["title"]]
        cur = admin("GET", f"/leaves/types/{tid}")["data"]
        body = _type_body(spec, back_date=False)
        body["rowVersion"] = cur["rowVersion"]
        c.call(admin, "PUT", f"/leaves/types/{tid}", body)


# ---------------------------------------------------------------------- approvers and Request Settings

def approver_rights(c: Ctx) -> None:
    """The CEO (Executive role: read-only) and the Admin Officer (Employee role) are line managers in the
    demo; a personal grant lets them decide their reports' requests from the Approvals screen."""
    admin = c.w.admin
    users = {u["email"]: u for u in admin.all("/access/users")}
    for name, reason in (("Imran Siddiqui", "CEO decides the requests of his direct reports"),
                         ("Bilal Ahmed", "Admin Officer decides the requests of the office assistants")):
        u = users.get(c.w.email(name))
        if not u:
            continue
        have = {o["code"] for o in admin("GET", f"/access/users/{u['id']}/overrides")["data"]}
        for code in ("requests.approvals.approve", "requests.approvals.reject"):
            if code not in have:
                admin("PUT", f"/access/users/{u['id']}/overrides",
                      {"code": code, "effect": "grant", "scope": "team", "reason": reason})


def setup_request_settings(c: Ctx) -> None:
    w, admin = c.w, c.w.admin
    # Authorities: who holds the HR Manager, Finance Manager ... nodes.
    if not admin.all("/requests/settings/authorities"):
        for authority, name, extra, text in (
                ("hr_manager", "Shelley Kannes", {}, "HR approval on every request type"),
                ("finance_manager", "Nadia Hussain", {}, "Finance sign-off on loans, travel and claims"),
                ("it_administrator", "Waqas Butt", {"requestType": "requisition"}, "Fulfils IT equipment requisitions"),
                ("admin_manager", "Bilal Ahmed", {"requestType": "requisition"}, "Fulfils office requisitions"),
                ("team_lead", "Faisal Javed", {"departmentId": int(w.departments["Software Development"]["id"])},
                 "Team lead of the web team")):
            admin("POST", "/requests/settings/authorities",
                  {"authority": authority, "employeeId": c.eid(name), "description": text, **extra})

    # Flows: line manager then HR in general; loans and travel go further.
    lm_hr = [{"stepNo": 1, "approverKind": "line_manager"}, {"stepNo": 2, "approverKind": "hr_manager"}]
    lm_fin = [{"stepNo": 1, "approverKind": "line_manager"}, {"stepNo": 2, "approverKind": "finance_manager"}]
    hod_hr = [{"stepNo": 1, "approverKind": "hod"}, {"stepNo": 2, "approverKind": "hr_manager"}]
    loan = [{"stepNo": 1, "approverKind": "line_manager"}, {"stepNo": 2, "approverKind": "hr_manager"},
            {"stepNo": 3, "isCondition": True, "expression": "amount > 300000", "ifTrue": 4, "ifFalse": 5},
            {"stepNo": 4, "approverKind": "final_authority"}, {"stepNo": 5, "approverKind": "finance_manager"}]
    travel = [{"stepNo": 1, "approverKind": "line_manager"}, {"stepNo": 2, "approverKind": "hod"},
              {"stepNo": 3, "isCondition": True, "expression": "days > 3", "ifTrue": 4, "ifFalse": 5},
              {"stepNo": 4, "approverKind": "final_authority"}, {"stepNo": 5, "approverKind": "finance_manager"}]
    flows = [(t, "request", "General Flow", lm_hr, "Line manager, then HR.")
             for t in ("leave", "punch", "relaxation", "official_visit", "work_from_home", "overtime", "rest_day",
                       "shift_swap", "requisition")]
    flows += [("expense", "request", "Claims Flow", lm_fin, "Line manager, then Finance releases the payment."),
              ("air_ticket", "request", "Claims Flow", lm_fin, "Line manager, then Finance releases the payment."),
              ("loan", "request", "Loan & Advance Flow", loan,
               "Line manager, HR, the CEO above PKR 300,000, then Finance."),
              ("travel", "request", "Business Travel Flow", travel,
               "Line manager, head of department, the CEO for trips over 3 days, then Finance."),
              ("promotion", "request", "Promotion Flow", hod_hr, "Head of department, then HR."),
              ("transfer", "request", "Transfer Flow", hod_hr, "Head of department, then HR."),
              ("leave", "cancellation", "Leave Cancellation", [{"stepNo": 1, "approverKind": "line_manager"}],
               "Cancelling approved leave needs the line manager only.")]
    current = admin.all("/requests/settings/flows?scopeType=company")
    for code, purpose, name, nodes, text in flows:
        body = {"requestType": code, "purpose": purpose, "name": name, "scopeType": "company", "description": text,
                "isActive": True, "nodes": nodes}
        old = next((f for f in current if f["requestType"] == code and f["purpose"] == purpose), None)
        if old is None:
            admin("POST", "/requests/settings/flows", body)
        else:  # e.g. the General Flow the engine saved for an earlier request: a new version of it
            admin("PUT", f"/requests/settings/flows/{old['id']}", {**body, "rowVersion": old["rowVersion"]})

    # Restrictions (start in the future) and a delegation.
    if not admin.all("/requests/settings/restrictions"):
        admin("POST", "/requests/settings/restrictions",
              {"requestType": "leave", "startDate": c.day(-7, 0).isoformat(), "endDate": c.day(-7, 4).isoformat(),
               "description": "Year-end release freeze: client go-lives that week, no leave."})
        admin("POST", "/requests/settings/restrictions",
              {"requestType": "travel", "startDate": c.day(-9, 0).isoformat(), "endDate": c.day(-9, 6).isoformat(),
               "description": "Year-end closing: no business travel."})
    if not admin.all("/requests/settings/delegations"):
        admin("POST", "/requests/settings/delegations",
              {"delegatorId": c.eid("Haroon Rashid"), "delegateeId": c.eid("Faisal Javed"), "requestType": "leave",
               "description": "Faisal decides leave for the technology heads while Haroon is on client visits.",
               "isActive": True})
        d = admin("POST", "/requests/settings/delegations",
                  {"delegatorId": c.eid("Asad Mirza"), "delegateeId": c.eid("Haroon Rashid"),
                   "requestType": "travel", "description": "Cover during Asad's leave in August.", "isActive": True})
        admin("PATCH", f"/requests/settings/delegations/{d['data']['id']}",
              {"isActive": False, "description": "Cover during Asad's leave in August (ended).",
               "rowVersion": d["data"]["rowVersion"]})


def setup_claims_and_loans(c: Ctx) -> None:
    admin = c.w.admin
    # Reimbursement pay items: approved claims are paid through payroll under these.
    items = {p["name"]: p for p in admin.all("/payroll/pay-items")}
    reimb = [p for p in items.values() if p["itemType"] == "reimbursement"]

    def pay_item(name: str, text: str) -> int:
        if name in items:
            return int(items[name]["id"])
        return int(admin("POST", "/payroll/pay-items", {
            "name": name, "label": name, "itemType": "reimbursement", "calculationType": "manual",
            "taxDistribution": "current_month", "isTaxable": False, "description": text})["data"]["id"])

    current = admin("GET", "/requests/settings/reimbursement")["data"]
    expense_item = current.get("expensePayItemId") or (
        reimb[0]["id"] if reimb else pay_item("Expense Reimbursement", "Approved expense claims"))
    air_item = current.get("airTicketPayItemId") or pay_item("Air Ticket Reimbursement", "Approved air ticket claims")
    admin("PUT", "/requests/settings/reimbursement",
          {"expensePayItemId": int(expense_item), "airTicketPayItemId": int(air_item)})

    cats = {x["name"]: x for x in admin.all("/requests/settings/expense-categories")}
    for name, cap, receipt, text in EXPENSE_CATEGORIES:
        if name not in cats:
            cats[name] = admin("POST", "/requests/settings/expense-categories",
                               {"name": name, "maxAmount": cap, "receiptRequired": receipt, "isActive": True,
                                "description": text})["data"]
    c.ids["expense"] = {n: int(x["id"]) for n, x in cats.items()}

    lcats = {x["name"]: x for x in admin.all("/loans/categories")}
    for name, text in LOAN_CATEGORIES:
        if name not in lcats:
            lcats[name] = admin("POST", "/loans/categories", {"name": name, "description": text})["data"]
    c.ids["loan_category"] = {n: int(x["id"]) for n, x in lcats.items()}

    ltypes = {x["name"]: x for x in admin.all("/loans/types")}
    deduction = next((p for p in items.values() if p.get("systemCode") == "loan_deduction"), None)
    employment = [int(x["id"]) for x in admin.all("/organisation/employment-types")
                  if x["name"] in ("Permanent", "Contractual")]
    for spec in LOAN_TYPES:
        if spec["name"] not in ltypes:
            ltypes[spec["name"]] = admin("POST", "/loans/types", {
                **spec, "isActive": True, "nonPayable": False, "gapBetweenInstallmentsMonths": 1,
                "deductionPayItemId": int(deduction["id"]) if deduction else None,
                "employmentTypeIds": employment})["data"]
    c.ids["loan_type"] = {n: int(x["id"]) for n, x in ltypes.items()}


def load_schedules(c: Ctx) -> None:
    """Shifts planned by the time part (if it ran): employee -> date -> shift, for the requests that need one."""
    admin = c.w.admin
    start, end = c.w.days_ago(126), c.w.today + timedelta(days=42)
    while start <= end:
        stop = min(start + timedelta(days=90), end)
        page = 1
        while True:
            res = c.call(admin, "GET", f"/scheduling/schedules?tab=all&from={start}&to={stop}&page={page}&pageSize=100",
                         quiet=True)
            if not res:
                return
            for row in res["data"]:
                emp = c.shifts.setdefault(int(row["employee"]["id"]), {})
                for s in row["shifts"]:
                    emp.setdefault(date.fromisoformat(s["workDate"]), s)
            if page >= res["meta"]["totalPages"]:
                break
            page += 1
        start = stop + timedelta(days=1)
