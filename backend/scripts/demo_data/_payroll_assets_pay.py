"""Payroll for the payroll_assets demo part: settings in a Pakistani context, salaries, bank accounts,
revisions, vouchers, monthly runs and the final settlement. Nadia Hussain (Finance Manager, payroll and
finance roles) and Usman Ghani (Payroll Accountant) do the work; nobody touches their own pay record."""
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal

from scripts.demo_data import World

NADIA, USMAN = "Nadia Hussain", "Usman Ghani"

# Monthly gross salary in PKR, in line with the grade (G1 ~ 60k up to G6 ~ 900k).
SALARY = {
    "Imran Siddiqui": 950_000, "Haroon Rashid": 850_000,
    "Shelley Kannes": 620_000, "Nadia Hussain": 600_000, "Asad Mirza": 580_000,
    "Faisal Javed": 480_000, "Rabia Anwar": 420_000, "Waqas Butt": 410_000, "Omer Farooq": 400_000,
    "Areeba Hameed": 300_000, "Ayesha Khan": 260_000, "Usman Ghani": 250_000,
    "Zain Abbas": 190_000, "Hira Shahid": 175_000, "Junaid Akhtar": 170_000, "Danish Iqbal": 165_000,
    "Hamza Riaz": 160_000, "Maham Zafar": 155_000, "Sana Malik": 150_000, "Komal Shah": 140_000,
    "Taha Saleem": 135_000, "Bilal Ahmed": 130_000, "Farah Naz": 125_000,
    "Saad Qureshi": 85_000, "Mehwish Akram": 80_000, "Kashif Mehmood": 60_000,
}

# Employee bank accounts: (bank, IBAN bank code, branch, branch code).
EMP_BANKS = [("Meezan Bank", "MEZN", "Gulberg III, Lahore", "0211"), ("HBL", "HABB", "Main Boulevard, Lahore", "1004"),
             ("United Bank Limited", "UNIL", "Liberty Market, Lahore", "0532"),
             ("MCB Bank", "MUCB", "Blue Area, Islamabad", "0786"), ("Bank Alfalah", "ALFH", "F-7 Markaz, Islamabad", "0145")]

# Income tax on salary, Tax Year 2025-26 (Finance Act 2025): annual income -> fixed + % of the part above the minimum.
SLABS = [(0, 600_000, 0, 0), (600_000, 1_200_000, 0, 1), (1_200_000, 2_200_000, 6_000, 11),
         (2_200_000, 3_200_000, 116_000, 23), (3_200_000, 4_100_000, 346_000, 30), (4_100_000, None, 616_000, 35)]

QUARTERLY_BONUS = ["Faisal Javed", "Areeba Hameed", "Rabia Anwar", "Komal Shah", "Junaid Akhtar", "Hira Shahid"]


def month_start(d: date) -> date:
    return d.replace(day=1)


def add_months(d: date, n: int) -> date:
    y, m = divmod(d.month - 1 + n, 12)
    return date(d.year + y, m + 1, 1)


def month_end(d: date) -> date:
    return add_months(month_start(d), 1) - timedelta(days=1)


def tax_year_start(d: date) -> date:
    return date(d.year if d.month >= 7 else d.year - 1, 7, 1)


def r1000(x: float) -> int:
    return int(Decimal(x / 1000).quantize(Decimal(1), ROUND_HALF_UP)) * 1000


def iban(n: int, code: str) -> str:
    return f"PK{36 + n % 60:02d}{code}{(7_310_000_000_000_000 + n * 104_729_331):016d}"[:24]


class Pay:
    def __init__(self, w: World):
        self.w = w
        self.nadia, self.usman = w.as_(NADIA), w.as_(USMAN)
        self.people = {f"{p['first']} {p['last']}": p for p in w.people}
        self.items: dict[str, dict] = {}
        self.banks: dict[str, dict] = {}
        self.tax: dict[date, dict] = {}
        self.counts: dict[str, int] = {}

    def by(self, target: str):
        """Usman does the pay records, Nadia his own (nobody changes their own pay)."""
        return self.nadia if target == USMAN else self.usman

    def count(self, what: str, n: int = 1) -> None:
        self.counts[what] = self.counts.get(what, 0) + n

    # ------------------------------------------------------------------ settings

    def settings(self) -> None:
        api, w = self.nadia, self.w
        cur = api("GET", "/payroll/settings/general")["data"]
        api("PUT", "/payroll/settings/general", {
            **cur, "excludeFinalSettlement": True, "hidePayslipAfterRun": True, "salaryReportRounding": "round_off",
            "showSalaryBreakdown": True, "payslipColor": "#1F4E79", "taxRounding": "round", "prorationRounding": "round",
            "notesEnglishEnabled": True,
            "notesEnglish": "This is a computer-generated payslip and needs no signature. Questions about your pay: "
                            "payroll@topedge.tech.",
            "printSignature": True, "sendCloseEmail": True, "payslipTemplate": "template_1", "showOnHoldAmounts": True,
            "showEmployeePayItems": True, "leaveYearBasis": "calendar"})

        # Tax structures: the previous and the current tax year (July to June), same slabs.
        ty = tax_year_start(w.today)
        for start in (date(ty.year - 1, 7, 1), ty):
            end = date(start.year + 1, 6, 30)
            name = f"Salaried Individuals Tax Year {start.year}-{str(start.year + 1)[2:]}"
            self.tax[start] = api("POST", "/payroll/tax-structures", {
                "name": name, "startDate": str(start), "endDate": str(end),
                "description": "Income tax on salary under the First Schedule, Part I, Division I (Finance Act 2025). "
                               "The 10% surcharge on income above Rs 10 million is applied by hand.",
                "slabs": [{"minAmount": a, "maxAmount": b, "fixedAmount": f, "percentage": p} for a, b, f, p in SLABS]})["data"]
        self.count("tax structures", 2)

        system = {i["systemCode"]: i for i in api.all("/payroll/pay-items") if i["systemCode"]}
        grades = {g["name"]: g["id"] for g in w.admin.all("/organisation/grades")}
        fuel = (f"if({{grade_id}} == {grades['G6']}, 60000, if({{grade_id}} == {grades['G5']}, 40000, "
                f"if({{grade_id}} == {grades['G4']}, 25000, 0))) * {{employed_days}} / {{month_days}}")
        # Formulas name variables and other formulas only: a new formula naming a pay item ({salary}) is refused
        # as a loop by the expression check (backend bug, reported), so basic is worked out from the gross here.
        formulas = {}
        for name, expr, desc in [
            ("Basic salary formula", "{gross_salary} * {employed_days} / {month_days} / 1.65",
             "Basic is 100/165 of gross: gross = basic + 45% house rent + 10% medical + 10% utilities."),
            ("House rent formula", "{basic_salary_formula} * 0.45", "45% of basic (exempt up to 45% of basic, Second Schedule)."),
            ("Medical allowance formula", "{basic_salary_formula} * 0.10", "10% of basic (exempt up to 10% of basic)."),
            ("Utilities formula", "{basic_salary_formula} * 0.10", "10% of basic."),
            ("Fuel allowance formula", fuel, "Monthly fuel by grade: G6 Rs 60,000, G5 Rs 40,000, G4 Rs 25,000; prorated."),
            ("EOBI employee formula", "if({employed_days} > 0, 400, 0)", "1% of the minimum wage (Rs 40,000)."),
            ("EOBI employer formula", "if({employed_days} > 0, 2000, 0)", "5% of the minimum wage (Rs 40,000)."),
            ("Provident fund formula", "round({basic_salary_formula} * 0.0833)", "8.33% of basic, matched by the company."),
            ("Quarterly bonus formula", "{gross_salary} * 0.5", "Half a month's gross for the quarter's top performers."),
        ]:
            formulas[name] = api("POST", "/payroll/formulas", {"name": name, "expression": expr, "description": desc})["data"]
        self.count("formulas", len(formulas))

        def item(name, label, kind, calc, formula=None, employer=None, taxable=False, display=False, benefit=False,
                 dist="remaining_months", desc=None):
            self.items[name] = api("POST", "/payroll/pay-items", {
                "name": name, "label": label, "itemType": kind, "calculationType": calc, "taxDistribution": dist,
                "employeeFormulaId": int(formulas[formula]["id"]) if formula else None,
                "employerFormulaId": int(formulas[employer]["id"]) if employer else None,
                "isTaxable": taxable, "isDisplayOnly": display, "isBenefit": benefit, "description": desc})["data"]

        item("Basic Salary", "Basic Pay", "earning", "formula", "Basic salary formula", display=True,
             desc="Breakdown of the gross salary on the payslip.")
        item("House Rent Allowance", "House Rent", "earning", "formula", "House rent formula", display=True,
             desc="Breakdown of the gross salary on the payslip.")
        item("Medical Allowance", "Medical", "earning", "formula", "Medical allowance formula", display=True,
             desc="Breakdown of the gross salary on the payslip.")
        item("Utilities Allowance", "Utilities", "earning", "formula", "Utilities formula", display=True,
             desc="Breakdown of the gross salary on the payslip.")
        item("Fuel Allowance", "Conveyance / Fuel", "earning", "formula", "Fuel allowance formula", taxable=True,
             desc="Company car fuel for G4 and above.")
        item("Performance Bonus", "Performance Bonus", "earning", "fixed", taxable=True, benefit=True,
             dist="current_month", desc="Paid through the Quarterly Performance Bonus reward to its members.")
        item("EOBI Contribution", "EOBI", "deduction", "formula", "EOBI employee formula", "EOBI employer formula",
             desc="Employees' Old-Age Benefits Institution: employee 1%, employer 5% of the minimum wage.")
        item("Provident Fund", "Provident Fund", "deduction", "formula", "Provident fund formula", "Provident fund formula",
             desc="Employee 8.33% of basic, matched by the company; credited to the Provident Fund account.")
        self.items.update({k: v for k, v in system.items()})
        self.count("pay items", 8)

        bonus = api("POST", "/payroll/benefits", {
            "name": "Quarterly Performance Bonus", "benefitType": "bonus", "payItemId": int(self.items["Performance Bonus"]["id"]),
            "formulaId": int(formulas["Quarterly bonus formula"]["id"]), "isGroup": True,
            "description": "Half a month's gross for the people rated Outstanding in the quarter's review.",
            "members": [{"employeeId": w.emp_id(n)} for n in QUARTERLY_BONUS],
            "fields": [{"name": "Review cycle", "fieldType": "string", "isRequired": True, "fieldValue": "Q1 FY 2026-27"},
                       {"name": "Minimum rating", "fieldType": "number", "fieldValue": "4.5", "minValue": 1, "maxValue": 5}]})["data"]
        api("POST", "/payroll/incentives", {
            "branchId": int(w.branches["Islamabad Office"]["id"]), "applicableMonth": str(month_start(w.today)),
            "incentiveType": "part_of_salary", "targetAmount": 15_000_000, "valueType": "percentage", "rewardValue": 1.5,
            "description": "Sales team incentive: 1.5% of new contract value once the branch reaches Rs 15 million."})

        pf_account = api("POST", "/payroll/account-types", {"name": "Provident Fund Balance", "category": "custom_pay_item",
                                                            "refId": int(self.items["Provident Fund"]["id"])})["data"]
        api("POST", "/payroll/account-types", {"name": "Performance Bonus Account", "category": "benefit",
                                               "refId": int(bonus["id"])})
        n_accounts = 2
        for lt in self.leave_types():
            title = lt.get("title") or lt.get("name") or ""
            if lt.get("isActive", True) and "annual" in title.lower():
                api("POST", "/payroll/account-types", {"name": f"{title} Quota", "category": "leave_quota",
                                                       "refId": int(lt["id"])})
                n_accounts += 1
                break
        self.count("account types", n_accounts)
        api("POST", "/payroll/rules", {
            "name": "Provident fund accrual", "expression": "{provident_fund} * 2", "accountTypeId": int(pf_account["id"]),
            "description": "Employee and company shares credited to the person's provident fund balance every run."})

        for holder, number, bank, branch, code, loc in [
            ("Top Edge Technologies (Pvt) Ltd", "PK24MEZN0002110104567812", "Meezan Bank", "Gulberg III Branch", "0211", "Lahore"),
            ("Top Edge Technologies (Pvt) Ltd", "PK61HABB0010047900345503", "HBL", "Blue Area Branch", "1004", "Islamabad")]:
            self.banks[bank] = api("POST", "/payroll/disbursement-banks", {
                "accountHolder": holder, "accountNumber": number, "bankName": bank, "branchName": branch,
                "branchCode": code, "branchLocation": loc, "taxPayerId": "4291837-6",
                "effectiveDate": str(date(w.today.year - 1, 7, 1)), "description": "Salary disbursement account."})["data"]
        self.count("disbursement banks", 2)

    def leave_types(self) -> list[dict]:
        r = self.w.admin("GET", "/leaves/types?page=1&pageSize=100", ok=(200, 403, 404))
        return r.get("data") or []

    # ------------------------------------------------------------------ salaries and bank accounts

    def salaries(self) -> None:
        w = self.w
        ty = tax_year_start(w.today)
        for n, (name, amount) in enumerate(SALARY.items(), start=1):
            p = self.people[name]
            joined = date.fromisoformat(p["joined"])
            api, eid = self.by(name), w.emp_id(name)
            if joined <= ty - timedelta(days=365):
                before = r1000(amount / 1.10)
                api("POST", f"/employees/{eid}/salary", {"effectiveDate": str(joined), "amount": r1000(before * 0.8 if joined.year < 2021 else before),
                                                          "source": "joining", "remarks": "Salary at joining."})
                if joined.year < 2021:
                    api("POST", f"/employees/{eid}/salary", {"effectiveDate": str(date(ty.year - 1, 7, 1)), "amount": before,
                                                              "source": "revision", "changeType": "percent", "changeValue": 25,
                                                              "remarks": "Annual increment and market adjustment."})
                api("POST", f"/employees/{eid}/salary", {"effectiveDate": str(ty), "amount": amount, "source": "revision",
                                                          "changeType": "percent", "changeValue": 10,
                                                          "remarks": "Annual increment, July."})
            else:
                api("POST", f"/employees/{eid}/salary", {"effectiveDate": str(joined), "amount": amount, "source": "joining",
                                                          "remarks": "Salary at joining."})
            self.count("salary records")
            bank, code, branch, bcode = EMP_BANKS[n % len(EMP_BANKS)]
            api("POST", f"/employees/{eid}/bank-accounts", {
                "accountHolder": name, "accountNumber": iban(n, code), "bankName": bank, "branchName": branch,
                "branchCode": bcode, "taxPayerId": f"35202{4000000 + n * 7919:07d}{n % 9 + 1}", "isPrimary": True})
            self.count("bank accounts")

    def revisions(self) -> None:
        """Two revisions in the Salary Revision screen, the first with its letter."""
        w, api = self.w, self.usman
        last = add_months(month_start(w.today), -1)

        def free(names: list[str], on: date) -> str:
            """The first person whose current salary starts before `on` (an approved promotion from leave_requests
            may already have set a salary this month, e.g. Zain Abbas)."""
            for n in names:
                cur = api("GET", f"/payroll/salary-revisions/current/{w.emp_id(n)}")["data"]
                if not cur.get("effectiveDate") or date.fromisoformat(str(cur["effectiveDate"])) < on:
                    return n
            raise SystemExit(f"no one free for a salary revision on {on}")

        r = api("POST", "/payroll/salary-revisions", {"employeeId": w.emp_id(free(["Areeba Hameed", "Faisal Javed"], last)),
                                                       "effectiveDate": str(last), "changeType": "percent", "changeValue": 15})["data"]
        api("POST", f"/payroll/salary-revisions/{r['id']}/email", {"rowVersion": r["rowVersion"]})
        api("POST", "/payroll/salary-revisions", {
            "employeeId": w.emp_id(free(["Junaid Akhtar", "Maham Zafar", "Farah Naz"], month_start(w.today))),
            "effectiveDate": str(month_start(w.today)), "changeType": "flat", "changeValue": 20_000})
        self.count("salary revisions", 2)
        # A rebate (charitable donation, section 61) lowers Haroon Rashid's tax for the year.
        api("POST", "/payroll/tax-rebates", {"employeeId": w.emp_id("Haroon Rashid"), "rebateDate": str(add_months(last, -1) + timedelta(days=9)),
                                             "amount": 85_000, "description": "Donation to an approved institution (section 61)."})

    def vouchers(self) -> None:
        w, api = self.w, self.usman
        asad, nadia = w.as_("Asad Mirza"), self.nadia
        made = []
        for emp, kind, days, amount, method, purpose in [
            ("Komal Shah", "travel_allowance", 40, 38_500, "bank_transfer", "Client visits in Karachi: travel and stay, 3 days."),
            ("Taha Saleem", "expense_reimbursement", 26, 12_400, "cash", "Social media ad spend paid by personal card."),
            ("Asad Mirza", "bonus", 12, 150_000, "bank_transfer", "Closing bonus: Pak-Gulf Logistics contract."),
            ("Junaid Akhtar", "expense_reimbursement", 9, 8_750, "cash", "Network cables and patch panel for the Islamabad office."),
            ("Komal Shah", "expense_reimbursement", 3, 6_200, "cash", "Client lunch, Blue Area."),
        ]:
            v = api("POST", "/payroll/vouchers", {
                "employeeId": w.emp_id(emp), "voucherType": kind, "voucherDate": str(w.days_ago(days)), "currency": "PKR",
                "amount": amount, "paymentMethod": method, "purpose": purpose,
                "requestedById": w.emp_id(emp)})["data"]
            made.append(v)
        self.count("vouchers", len(made))
        # Komal's travel: approved by her head, verified by Finance. Taha's: approved, verified. Asad's bonus: the CEO
        # role cannot approve vouchers, so Nadia (company-wide) approves it. Junaid's: rejected. The last waits.
        v = asad("POST", f"/payroll/vouchers/{made[0]['id']}/approve", {"remarks": "Approved.", "rowVersion": made[0]["rowVersion"]})["data"]
        nadia("POST", f"/payroll/vouchers/{v['id']}/verify", {"remarks": "Paid with October salary.", "rowVersion": v["rowVersion"]})
        v = asad("POST", f"/payroll/vouchers/{made[1]['id']}/approve", {"rowVersion": made[1]["rowVersion"]})["data"]
        nadia("POST", f"/payroll/vouchers/{v['id']}/verify", {"remarks": "Paid in cash.", "rowVersion": v["rowVersion"]})
        nadia("POST", f"/payroll/vouchers/{made[2]['id']}/approve", {"remarks": "Per the sales incentive policy.",
                                                                    "rowVersion": made[2]["rowVersion"]})
        nadia("POST", f"/payroll/vouchers/{made[3]['id']}/reject", {"remarks": "Bought through IT procurement instead; raise a requisition.",
                                                                   "rowVersion": made[3]["rowVersion"]})

    def leave_encashment(self) -> None:
        """Paid through the current month's run, when a leave type allows encashment (made by leave_requests)."""
        w, api = self.w, self.usman
        types = [t for t in self.leave_types() if t.get("allowEncashment")]
        if not types:
            print("  leave encashment skipped: no leave type allows encashment")
            return
        candidates = [w.emp_id(n) for n in ("Junaid Akhtar", "Danish Iqbal", "Sana Malik", "Farah Naz", "Bilal Ahmed")]
        for lt in types:
            for year in (w.today.year, w.today.year - 1):
                body = {"leaveTypeId": int(lt["id"]), "fiscalYear": year, "employeeIds": candidates, "basis": "earned_salary"}
                r = api("POST", "/payroll/leave-encashments/preview", body, ok=(200, 422))
                rows = [x for x in (r.get("data") or []) if x["encashableDays"] > 0]
                if rows:
                    api("POST", "/payroll/leave-encashments", {**body, "employeeIds": [int(x["employeeId"]) for x in rows],
                                                               "mode": "payroll"})
                    self.count("leave encashments (people)", len(rows))
                    return
        print("  leave encashment skipped: nobody has an encashable balance")

    # ------------------------------------------------------------------ monthly payrolls

    def payroll(self, month: date, close: bool, leaving: set[str]) -> dict:
        w, api = self.w, self.usman
        tax = self.tax[max(k for k in self.tax if k <= month)]
        ids = [w.emp_id(n) for n, p in self.people.items()
               if date.fromisoformat(p["joined"]) <= month_end(month) and n not in leaving]
        # Every pay item of the company (also the reimbursement items leave_requests made), the quarterly bonus
        # only in the last month of a quarter.
        items = [{"payItemId": int(i["id"]), "isTaxable": i["isTaxable"], "finalSettlement": i["name"] != "Performance Bonus"}
                 for i in api.all("/payroll/pay-items")
                 if i["name"] != "Performance Bonus" or month.month in (3, 6, 9, 12)]
        pr = api("POST", "/payroll/payrolls", {
            "name": f"Salary {month:%B %Y}", "payrollMonth": str(month), "currency": "PKR",
            "taxStructureId": int(tax["id"]), "taxApplicable": True, "processingMode": "month_end",
            "processingDate": str(month_end(month)), "applicableDays": "actual",
            "disbursementBankId": int(self.banks["Meezan Bank"]["id"]),
            "description": f"Monthly salary for {month:%B %Y}.", "payItems": items})["data"]
        api("PUT", f"/payroll/payrolls/{pr['id']}/employees", {"employeeIds": ids})
        run = api("POST", f"/payroll/payrolls/{pr['id']}/run")["data"]
        if run.get("errorCount"):
            errs = api("GET", f"/payroll/payrolls/{pr['id']}/errors")["data"]
            print(f"  {month:%b %Y}: {run['errorCount']} run errors: " + "; ".join(f"{e['employeeName']}: {e['message']}" for e in errs[:5]))
        pr = api("GET", f"/payroll/payrolls/{pr['id']}")["data"]
        self.count("payslips", pr["payslipCount"])
        if close:
            pr = self.nadia("POST", f"/payroll/payrolls/{pr['id']}/close", {"rowVersion": pr["rowVersion"]})["data"]
            slips = api.all(f"/payroll/payslips?payrollId={pr['id']}")
            usman = str(w.emp_id(USMAN))
            api("POST", "/payroll/payslips/pay", {"ids": [int(s["id"]) for s in slips if s["employeeId"] != usman]})
            mine = [int(s["id"]) for s in slips if s["employeeId"] == usman]
            if mine:
                self.nadia("POST", "/payroll/payslips/pay", {"ids": mine})
            self.count("closed payrolls")
        else:
            self.count("open payrolls")
        return pr

    def final_settlement(self, name: str) -> dict:
        eid = str(self.w.emp_id(name))
        rows = self.nadia.all("/payroll/final-settlements")
        fs = next(r for r in rows if r["employeeId"] == eid)
        fs = self.usman("POST", f"/payroll/final-settlements/{fs['id']}/recalculate")["data"]
        fs = self.nadia("POST", f"/payroll/final-settlements/{fs['id']}/close", {"rowVersion": fs["rowVersion"]})["data"]
        if fs.get("payslipId"):
            self.usman("POST", "/payroll/payslips/pay", {"ids": [int(fs["payslipId"])]})
        self.count("final settlements")
        return fs
