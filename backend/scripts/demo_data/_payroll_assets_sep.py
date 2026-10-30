"""Assets, off-boarding and benefits for the payroll_assets demo part.

Ayesha Khan (HR Officer) keeps the asset register and allocations; the Admin Officer, Bilal Ahmed, has only
the Employee role, so he appears as the person who checked the leaver's assets. Shelley Kannes (HR Manager)
owns the off-boarding settings and approves clearances."""
from datetime import date, timedelta

from scripts.demo_data import World

AYESHA, SHELLEY, BILAL = "Ayesha Khan", "Shelley Kannes", "Bilal Ahmed"

ASSET_TYPES = [
    ("Laptop", "Notebook computers issued for work."),
    ("Monitor", "External displays for engineering and design desks."),
    ("Mobile Phone", "Company phones for sales, support and management."),
    ("SIM Card", "Company-paid mobile connections."),
    ("Access Card", "Building and floor access cards (HID proximity)."),
]

# Laptop model by grade: (name, manufacturer, model, value PKR)
LAPTOPS = {
    "G6": ("MacBook Pro 14", "Apple", "MacBook Pro 14 M3 Pro", 685_000),
    "G5": ("MacBook Air 15", "Apple", "MacBook Air 15 M3", 465_000),
    "G4": ("ThinkPad X1 Carbon", "Lenovo", "X1 Carbon Gen 11", 520_000),
    "G3": ("ThinkPad T14", "Lenovo", "T14 Gen 4", 345_000),
    "G2": ("Latitude 5440", "Dell", "Latitude 5440", 265_000),
    "G1": ("ProBook 450", "HP", "ProBook 450 G10", 215_000),
}
MONITOR_PEOPLE = ["Haroon Rashid", "Faisal Javed", "Areeba Hameed", "Zain Abbas", "Hira Shahid", "Saad Qureshi",
                  "Rabia Anwar", "Danish Iqbal", "Omer Farooq", "Maham Zafar", "Waqas Butt", "Junaid Akhtar"]
PHONE_PEOPLE = ["Imran Siddiqui", "Asad Mirza", "Komal Shah", "Taha Saleem", "Waqas Butt", "Junaid Akhtar", "Shelley Kannes",
                "Kashif Mehmood"]


def serial(prefix: str, n: int) -> str:
    return f"{prefix}{(n * 7_919 + 104_729) % 10_000_000:07d}"


class Sep:
    def __init__(self, w: World):
        self.w = w
        self.ayesha, self.shelley = w.as_(AYESHA), w.admin
        self.people = {f"{p['first']} {p['last']}": p for p in w.people}
        self.counts: dict[str, int] = {}
        self.types: dict[str, dict] = {}

    def count(self, what: str, n: int = 1) -> None:
        self.counts[what] = self.counts.get(what, 0) + n

    def joined(self, name: str) -> date:
        return date.fromisoformat(self.people[name]["joined"])

    # ------------------------------------------------------------------ assets

    def asset(self, kind: str, name: str, ident: str, manufacturer: str, model: str, value: int, acquired: date,
              condition: str = "new", taxable: bool = False, desc: str | None = None) -> dict:
        self.count("assets")
        return self.ayesha("POST", "/assets/company-assets", {
            "name": name, "assetTypeId": int(self.types[kind]["id"]), "identificationNo": ident, "isTaxable": taxable,
            "assetCondition": condition, "manufacturer": manufacturer, "model": model, "currentValue": value,
            "acquiredDate": str(acquired), "description": desc})["data"]

    def allocate(self, asset: dict, name: str, on: date, desc: str | None = None) -> dict:
        self.count("allocations")
        return self.ayesha("POST", "/assets/allocations", {"assetId": int(asset["id"]), "employeeId": self.w.emp_id(name),
                                                           "allocatedOn": str(on), "description": desc})["data"]

    def assets(self) -> None:
        w, api = self.w, self.ayesha
        for name, desc in ASSET_TYPES:
            self.types[name] = api("POST", "/assets/types", {"name": name, "description": desc})["data"]
        refresh = date(w.today.year - 3, 1, 10)
        n = 0
        for name, p in self.people.items():
            n += 1
            joined = self.joined(name)
            label, make, model, value = LAPTOPS[p["grade"]]
            bought = max(joined - timedelta(days=5), refresh)
            # Zain Abbas's first laptop went for repair (water damage); he works on a replacement since.
            if name == "Zain Abbas":
                old = self.asset("Laptop", label, serial("5CD", n), make, model, value, bought, desc="Keyboard and board water damage.")
                a = self.allocate(old, name, max(bought, joined))
                back = w.days_ago(47)
                api("PATCH", f"/assets/allocations/{a['id']}/deallocate", {
                    "deallocatedOn": str(back), "returnCondition": "damaged", "rowVersion": a["rowVersion"],
                    "remarks": "Sent to Dell service centre for board replacement."})
                bought, n = back, n + 100
            laptop = self.asset("Laptop", label, serial("5CD" if make in ("HP", "Dell") else "PF" if make == "Lenovo" else "C02", n),
                                make, model, value, bought, condition="new" if bought.year >= w.today.year - 1 else "fair")
            self.allocate(laptop, name, max(bought, joined) + timedelta(days=1 if bought >= joined else 0))
            card = self.asset("Access Card", f"Access Card {p.get('branch', 'Lahore Head Office').split()[0]}",
                              f"HID-{40_100 + n}", "HID Global", "ProxCard II", 1_800, joined)
            self.allocate(card, name, joined)
        # Monitors for engineering and design desks; Hira Shahid gave hers back when she moved to a laptop stand.
        for k, name in enumerate(MONITOR_PEOPLE):
            m = self.asset("Monitor", 'Dell 27" Monitor', serial("CN0", 500 + k), "Dell", "P2723QE 27 4K", 128_000,
                           date(w.today.year - 1, 3, 4))
            a = self.allocate(m, name, max(date(w.today.year - 1, 3, 6), self.joined(name)))
            if name == "Hira Shahid":
                api("PATCH", f"/assets/allocations/{a['id']}/deallocate", {
                    "deallocatedOn": str(w.days_ago(20)), "returnCondition": "good", "rowVersion": a["rowVersion"],
                    "remarks": "Returned to IT store; no longer needed."})
        for k, name in enumerate(PHONE_PEOPLE):
            phone = self.asset("Mobile Phone", "Samsung Galaxy A55", f"35{(8_812_340_000_000 + k * 9_173):013d}", "Samsung",
                               "Galaxy A55 5G", 129_999, date(w.today.year - 1, 8, 12), taxable=True)
            self.allocate(phone, name, max(date(w.today.year - 1, 8, 14), self.joined(name)))
            sim = self.asset("SIM Card", "Jazz Business SIM", f"8992{(3_011_000_000 + k * 7_771):010d}", "Jazz",
                             "Business 4G Postpaid", 0, date(w.today.year - 1, 8, 12))
            self.allocate(sim, name, max(date(w.today.year - 1, 8, 14), self.joined(name)))
        # Spares in the IT store, and an old laptop written off.
        for k in range(2):
            self.asset("Laptop", "Latitude 5440", serial("5CD", 900 + k), "Dell", "Latitude 5440", 265_000, w.days_ago(60),
                       desc="Spare in the IT store.")
            self.asset("Access Card", "Access Card Visitor", f"HID-{49_001 + k}", "HID Global", "ProxCard II", 1_800,
                       w.days_ago(200), desc="Visitor card at reception.")
        old = self.asset("Laptop", "ThinkPad T480", serial("PF1", 77), "Lenovo", "T480", 35_000, date(w.today.year - 6, 2, 1),
                         condition="old", desc="Battery swollen; written off.")
        api("PATCH", f"/assets/company-assets/{old['id']}/deactivate", {"rowVersion": old["rowVersion"]})

    # ------------------------------------------------------------------ off-boarding

    def checklist(self) -> None:
        self.shelley("POST", "/offboarding/settings/checklists", {
            "name": "Exit Checklist", "description": "Hand-over, exit interview and account closure for every leaver.",
            "fields": [
                {"name": "Exit interview held", "fieldType": "boolean", "isRequired": True},
                {"name": "Exit interview date", "fieldType": "date"},
                {"name": "Knowledge handover completed", "fieldType": "boolean", "isRequired": True},
                {"name": "Email and system accounts disabled on", "fieldType": "date", "isRequired": True},
                {"name": "Experience rating (1-5)", "fieldType": "number", "minValue": 1, "maxValue": 5},
                {"name": "Exit interview notes", "fieldType": "string", "maxLength": 500}]})

    def resign(self, name: str, resign_on: date, notice: int, approve: bool) -> dict:
        """The resignation request as the person, then (when approve) every approval step as its approver."""
        w = self.w
        flows = w.admin("GET", "/requests/settings/flows?requestType=resignation&page=1&pageSize=100")["data"]
        if not any(f["purpose"] == "request" and f["isActive"] for f in flows):
            # The General Flow ends with the final authority (the CEO), whose Executive role cannot approve:
            # resignations go to the line manager, then HR.
            w.admin("POST", "/requests/settings/flows", {
                "requestType": "resignation", "name": "Resignation Flow", "scopeType": "company",
                "description": "Line manager, then the HR Manager.",
                "nodes": [{"stepNo": 1, "approverKind": "line_manager", "next": 2},
                          {"stepNo": 2, "approverKind": "employee", "employeeId": w.emp_id(SHELLEY)}]})
        me = w.as_(name)
        lwd = resign_on + timedelta(days=notice)
        r = me("POST", "/requests/resignation", {
            "reason": "Better opportunity" if approve else "Moving abroad for higher studies",
            "description": "I am grateful for the time at Top Edge and will complete my hand-over during the notice period.",
            "details": {"resignationType": "resignation", "resignationDate": str(resign_on), "lastWorkingDate": str(lwd),
                        "noticePeriodDays": notice, "serveNotice": True}})["data"]
        self.count("resignations")
        if not approve:
            return r
        by_id = {str(e["id"]): n for n, e in w.employees.items()}
        for _ in range(6):
            r = w.admin("GET", f"/requests/resignation/{r['id']}")["data"]
            if r["status"] != "pending":
                break
            approver = by_id.get(str(r.get("nextApproverId")), SHELLEY)
            body = {"remarks": "Accepted with thanks. Please complete the hand-over.", "rowVersion": r["rowVersion"],
                    "details": {"lastWorkingDate": str(lwd), "serveNotice": True, "noticePeriodDays": notice}}
            done = w.as_(approver)("POST", f"/requests/approvals/{r['id']}/approve", body, ok=(200, 403))
            if "data" not in done:
                # The approver's role cannot approve (an Employee-only line manager, the CEO's Executive role):
                # they delegate resignations to the HR Officer, who approves for them.
                d = w.admin("POST", "/requests/settings/delegations", {
                    "delegatorId": w.emp_id(approver), "delegateeId": w.emp_id(AYESHA), "requestType": "resignation",
                    "description": f"{approver} delegates resignation approvals to HR."}, ok=(201, 409, 422))
                w.as_(AYESHA)("POST", f"/requests/approvals/{r['id']}/approve", body)
                if "data" in d:
                    w.admin("PATCH", f"/requests/settings/delegations/{d['data']['id']}", {
                        "isActive": False, "description": d["data"].get("description"), "rowVersion": d["data"]["rowVersion"]})
        if r["status"] != "approved":
            raise SystemExit(f"resignation of {name} ended {r['status']}")
        return r

    def clear(self, name: str, delegatee: str, description: str) -> dict:
        """Asset clearance, checklist answers: everything but the final settlement."""
        w, api = self.w, self.ayesha
        eid = w.emp_id(name)
        eoe = next(e for e in api.all("/offboarding/end-of-employment?status=pending") if e["employeeId"] == str(eid))
        eoe = api("GET", f"/offboarding/end-of-employment/{eoe['id']}")["data"]
        lwd = date.fromisoformat(str(eoe["lastWorkingDate"]))
        api("PUT", f"/offboarding/end-of-employment/{eoe['id']}", {
            "employeeId": eid, "reason": eoe["reason"], "serveNotice": eoe["serveNotice"],
            "noticePeriodDays": eoe.get("noticePeriodDays"), "lastWorkingDate": str(lwd),
            "needsFinalSettlement": True, "needsAssetClearance": True, "assetClearByDate": str(lwd),
            "replacementId": None, "delegateeId": w.emp_id(delegatee), "description": description,
            "rowVersion": eoe["rowVersion"]})
        pre = api("GET", f"/assets/clearance-forms/prefill?employeeId={eid}")["data"]
        items = []
        for it in pre["items"]:
            nm = it["assetName"]
            if "SIM" in nm:
                items.append({"assetAllocationId": int(it["assetAllocationId"]), "conditionAtClearance": "good",
                              "returnStatus": "not_returned", "reason": "Number kept by the employee",
                              "comments": "Ownership transferred to the employee; Rs 1,500 recovered in final settlement."})
            elif "Galaxy" in nm:
                items.append({"assetAllocationId": int(it["assetAllocationId"]), "conditionAtClearance": "fair",
                              "returnStatus": "complete", "reason": "Resignation", "comments": "Screen scratched; usable."})
            else:
                items.append({"assetAllocationId": int(it["assetAllocationId"]), "conditionAtClearance": "good",
                              "returnStatus": "complete", "reason": "Resignation", "comments": "Returned with charger." if "Laptop" in nm or "Latitude" in nm else None})
        form = api("POST", "/assets/clearance-forms", {
            "employeeId": eid, "endOfEmploymentId": int(eoe["id"]), "clearanceDate": str(lwd),
            "checkedById": w.emp_id(BILAL), "approvedById": w.emp_id(SHELLEY), "approvalDate": str(lwd), "items": items})["data"]
        self.shelley("PATCH", "/assets/clearance-forms/approve", {"forms": [{"id": int(form["id"]), "rowVersion": form["rowVersion"]}]})
        fields = {f["name"]: f for f in api("GET", "/offboarding/end-of-employment/checklist-fields")["data"]}
        answers = {"Exit interview held": True, "Exit interview date": str(lwd - timedelta(days=1)),
                   "Knowledge handover completed": True, "Email and system accounts disabled on": str(lwd + timedelta(days=1)),
                   "Experience rating (1-5)": 4,
                   "Exit interview notes": "Leaving for a better-paid role closer to home. Would consider returning."}
        eoe = api("GET", f"/offboarding/end-of-employment/{eoe['id']}")["data"]
        api("PUT", f"/offboarding/end-of-employment/{eoe['id']}/checklist", {
            "answers": [{"checklistFieldId": int(fields[k]["id"]), "answer": v} for k, v in answers.items() if k in fields],
            "rowVersion": eoe["rowVersion"]})
        self.count("clearance forms")
        return eoe

    # ------------------------------------------------------------------ benefits

    def benefits(self) -> None:
        w, api = self.w, self.ayesha
        start = date(w.today.year if w.today.month >= 7 else w.today.year - 1, 7, 1)
        end = date(start.year + 1, 6, 30)
        plans = {}
        for cat, name, ptype, carrier, desc in [
            ("medical", "Group Health Insurance", "Hospitalisation and maternity", "State Life Insurance Corporation",
             "In-patient cover up to Rs 1,000,000 a year for the employee, spouse and children; maternity Rs 150,000."),
            ("medical", "OPD Cover", "Out-patient", "Jubilee General Insurance",
             "Doctor visits, medicines and tests up to Rs 60,000 a year per family."),
            ("life", "Group Life Insurance", "Term life", "EFU Life Assurance",
             "36 months' gross salary on death or permanent disability; company paid."),
            ("retirement", "Employees Provident Fund", "Recognised provident fund", "Top Edge Employees Provident Fund Trust",
             "8.33% of basic from the employee, matched by the company; withdrawals after 3 years."),
        ]:
            plans[name] = api("POST", "/benefits/plans", {"category": cat, "name": name, "planType": ptype, "carrier": carrier,
                                                          "startDate": str(start), "endDate": str(end), "description": desc})["data"]
        year = api("POST", "/benefits/plan-years", {
            "name": f"Benefits {start.year}-{str(end.year)[2:]}", "startDate": str(start), "endDate": str(end),
            "planIds": [int(p["id"]) for p in plans.values()], "newHireStart": "waiting_period", "waitingPeriodDays": 30,
            "electionPeriod": 30, "electionUnit": "day"})["data"]
        window = api("POST", "/benefits/enrollment-windows", {
            "planYearId": int(year["id"]), "kind": "open_enrollment", "name": f"Open Enrolment {start.year}-{str(end.year)[2:]}",
            "effectiveDate": str(w.days_ago(14)), "closesOn": str(w.today + timedelta(days=16)),
            "description": "Choose your health, life and provident fund cover for the plan year.",
            "planIds": [int(p["id"]) for p in plans.values()]})["data"]
        self.count("benefit plans", len(plans))
        all_plans = [int(p["id"]) for p in plans.values()]
        core = [int(plans[n]["id"]) for n in ("Group Health Insurance", "Group Life Insurance", "Employees Provident Fund")]
        names = sorted(self.people)
        elections = []
        for k, name in enumerate(names):
            if name in ("Taha Saleem", "Saad Qureshi", "Mehwish Akram", "Kashif Mehmood"):
                continue  # leaving, on probation, or not yet decided
            me = w.as_(name)
            body = {"employeeId": w.emp_id(name), "planYearId": int(year["id"]), "enrollmentWindowId": int(window["id"]),
                    "planIds": all_plans if k % 3 else core, "submit": True}
            if name in ("Haroon Rashid", "Farah Naz"):
                body = {**body, "planIds": [], "waive": True, "remarks": "Covered through my spouse's employer."}
            elif name in ("Hira Shahid", "Danish Iqbal"):
                body = {**body, "submit": False}
            elections.append((name, me("POST", "/benefits/elections", body)["data"]))
        self.count("benefit elections", len(elections))
        approver = w.as_(AYESHA)
        for name, e in elections:
            if e["status"] != "pending" or name in ("Junaid Akhtar", "Maham Zafar", "Omer Farooq"):
                continue
            who = self.shelley if name == AYESHA else approver
            who("POST", f"/benefits/elections/{e['id']}/approve", {"remarks": "Enrolled.", "rowVersion": e["rowVersion"]})
            self.count("elections approved")
