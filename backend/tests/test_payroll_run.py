"""A full monthly run with known inputs: salary, fixed allowance, absences, a late arrival, a loan installment,
tax from slabs and a rule posting; hand edits kept on recalculation; close locks everything; payslip scope."""
from datetime import date
from decimal import Decimal

import pytest

from tests import factories
from tests import factories_events as fe
from tests import factories_payroll as fp

JULY = "2026-07-01"


@pytest.fixture(scope="module")
def setup(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    h = admin["headers"]
    dept = factories.department(db, company)
    e1 = fp.employee(db, company, salary=100000, department_id=dept, first_name="Ayesha", last_name="Khan")
    e2 = fp.employee(db, company, salary=None, department_id=dept, first_name="No", last_name="Salary")
    fp.month_days(db, company, e1, 2026, 7, absent={6, 7}, late={8: 60})

    medical = client.post("/api/payroll/pay-items", json={
        "name": "Medical Allowance", "itemType": "earning", "calculationType": "fixed",
        "taxDistribution": "current_month", "isTaxable": False}, headers=h)
    assert medical.status_code == 201, medical.text
    fp.employee_pay_item(db, e1, int(medical.json()["data"]["id"]), 5000)
    loan_id = fp.loan(db, company, e1, [(date(2026, 7, 1), 5000), (date(2026, 8, 1), 5000)])

    salary_item = fp.pay_item_id(db, company, "salary")
    account = client.post("/api/payroll/account-types", json={"name": "Provident Fund", "category": "custom_pay_item",
                                                              "refId": str(salary_item)}, headers=h)
    assert account.status_code == 201, account.text
    rule = client.post("/api/payroll/rules", json={"name": "PF 5%", "expression": "{salary} * 0.05",
                                                   "accountTypeId": account.json()["data"]["id"]}, headers=h)
    assert rule.status_code == 201, rule.text

    tax = fp.tax_structure(client, h)
    bank = fp.bank(client, h)
    run = fp.payroll(client, h, JULY, tax["id"], bank["id"])
    r = client.put(f"/api/payroll/payrolls/{run['id']}/employees", json={"employeeIds": [str(e1), str(e2)]}, headers=h)
    assert r.status_code == 200 and r.json()["data"]["employeeCount"] == 2, r.text
    return {"company": company, "admin": admin, "h": h, "e1": e1, "e2": e2, "run": run, "loan": loan_id, "dept": dept}


def _lines(slip: dict) -> dict[str, float]:
    return {l["systemCode"] or l["payItemName"]: l["amount"] for l in slip["lines"]}


def test_run_works_out_the_expected_net_pay(client, db, setup):
    h, run = setup["h"], setup["run"]
    r = client.post(f"/api/payroll/payrolls/{run['id']}/run", headers=h)
    assert r.status_code == 200, r.text
    log = r.json()["data"]
    assert log["processedCount"] == 1 and log["errorCount"] == 1
    # Who ran it comes back at once (the account has no employee record: its display name).
    assert log["runByUserId"] == str(setup["admin"]["user_id"]) and log["runByName"] == "Test User"

    errors = client.get(f"/api/payroll/payrolls/{run['id']}/errors", headers=h).json()["data"]
    assert [e["employeeId"] for e in errors] == [str(setup["e2"])] and "salary" in errors[0]["message"].lower()

    slips = client.get("/api/payroll/payslips", params={"payrollId": run["id"]}, headers=h).json()
    assert slips["meta"]["total"] == 1
    slip = client.get(f"/api/payroll/payslips/{slips['data'][0]['id']}", headers=h).json()["data"]
    lines = _lines(slip)
    # 100,000 salary for a full month; absences and short minutes on 30 fixed days of 480 minutes.
    assert lines["salary"] == 100000
    assert lines["Medical Allowance"] == 5000
    assert lines["absent_deduction"] == 6666.67          # 100,000 / 30 x 2
    assert lines["short_deduction"] == 416.67            # 100,000 / 30 / 480 x 60
    assert lines["loan_deduction"] == 5000
    # Taxable 92,916.66 a month -> 1,114,999.92 a year -> (1,114,999.92 - 600,000) x 5% = 25,750.00 -> / 12
    assert lines["tax"] == 2145.83
    assert slip["totalEarnings"] == 105000 and slip["totalDeductions"] == 14229.17
    assert slip["netPayable"] == 90770.83 and slip["status"] == "ready"
    assert slip["absentDays"] == 2 and slip["taxableIncome"] == 92916.66

    pf = fp.rows(db, "SELECT credit, debit, is_processed FROM pay.employee_account_entry WHERE employee_id = ?", setup["e1"])
    assert pf == [{"credit": Decimal("5000.00"), "debit": Decimal("0.00"), "is_processed": False}]

    payroll = client.get(f"/api/payroll/payrolls/{run['id']}", headers=h).json()["data"]
    assert payroll["status"] == "running" and payroll["netPayable"] == 90770.83

    sheet = client.get("/api/payroll/salary-sheet", params={"payrollId": run["id"]}, headers=h).json()["data"]
    assert len(sheet["rows"]) == 1 and sheet["rows"][0]["absentDeduction"] == 6666.67 and sheet["totals"]["netPayable"] == 90770.83


def test_tax_engine_slabs_and_surcharge():
    from app.services.payroll_engine import annual_tax, monthly_tax
    slabs = [{"min_amount": s["minAmount"], "max_amount": s["maxAmount"], "fixed_amount": s["fixedAmount"],
              "percentage": s["percentage"]} for s in fp.SLABS]
    assert annual_tax(Decimal(500000), slabs, None, None) == 0
    assert annual_tax(Decimal(1500000), slabs, None, None) == Decimal(30000) + Decimal(300000) * Decimal("0.15")
    assert annual_tax(Decimal(1500000), slabs, "percentage", 10) == Decimal(75000) * Decimal("1.1")
    assert annual_tax(Decimal(1500000), slabs, "flat", 1000) == Decimal(76000)
    # A one-off bonus with "Current Month" distribution is taxed now; the rest is spread over the months left.
    base = monthly_tax(recurring=Decimal(100000), oneoff_current=Decimal(0), oneoff_spread=Decimal(0), ytd_taxable=Decimal(0),
                       ytd_tax=Decimal(0), rebates=Decimal(0), months_left=12, slabs=slabs, surcharge_type=None,
                       surcharge_value=None)
    assert base == Decimal(2500)
    bonus = monthly_tax(recurring=Decimal(100000), oneoff_current=Decimal(100000), oneoff_spread=Decimal(0),
                        ytd_taxable=Decimal(0), ytd_tax=Decimal(0), rebates=Decimal(0), months_left=12, slabs=slabs,
                        surcharge_type=None, surcharge_value=None)
    assert bonus == Decimal(2500) + Decimal(15000)  # 1.3M is in the 15% slab: 45,000 - 30,000 more, all now
    rebate = monthly_tax(recurring=Decimal(100000), oneoff_current=Decimal(0), oneoff_spread=Decimal(0),
                         ytd_taxable=Decimal(0), ytd_tax=Decimal(0), rebates=Decimal(12000), months_left=12, slabs=slabs,
                         surcharge_type=None, surcharge_value=None)
    assert rebate == Decimal(1500)


def test_hand_edit_is_kept_on_recalculate_and_row_version_guards_it(client, setup):
    h, run = setup["h"], setup["run"]
    slip = client.get("/api/payroll/payslips", params={"payrollId": run["id"]}, headers=h).json()["data"][0]
    overtime = client.get("/api/payroll/pay-items", params={"q": "Overtime"}, headers=h).json()["data"][0]

    r = client.put(f"/api/payroll/payslips/{slip['id']}", json={"lines": [{"payItemId": overtime["id"], "amount": 1000}],
                                                               "rowVersion": slip["rowVersion"]}, headers=h)
    assert r.status_code == 200, r.text
    stale = client.put(f"/api/payroll/payslips/{slip['id']}", json={"lines": [{"payItemId": overtime["id"], "amount": 5}],
                                                                   "rowVersion": slip["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    r = client.post(f"/api/payroll/payslips/{slip['id']}/recalculate", headers=h)
    assert r.status_code == 200, r.text
    again = r.json()["data"]
    lines = {l["systemCode"]: l for l in again["lines"] if l["systemCode"]}
    assert lines["overtime"]["amount"] == 1000 and lines["overtime"]["isManuallyUpdated"]
    # Taxable now 93,916.66 a month -> (1,126,999.92 - 600,000) x 5% / 12
    assert lines["tax"]["amount"] == 2195.83
    assert again["netPayable"] == 91720.83

    history = client.get(f"/api/payroll/payslips/{slip['id']}/history", headers=h).json()["data"]
    assert any(x["fieldName"] == "Overtime" and x["newValue"] == "1000.00" for x in history)


def test_payslip_scope_an_employee_sees_only_their_own(client, db, setup):
    h, run = setup["h"], setup["run"]
    me = factories.login_as(db, client, setup["company"], role_codes="employee", employee_id=setup["e1"])
    other = fp.employee(db, setup["company"], salary=50000, department_id=setup["dept"])
    fp.month_days(db, setup["company"], other, 2026, 7)
    assert client.put(f"/api/payroll/payrolls/{run['id']}/employees",
                      json={"employeeIds": [str(setup["e1"]), str(setup["e2"]), str(other)]}, headers=h).status_code == 200
    assert client.post(f"/api/payroll/payrolls/{run['id']}/run", headers=h).status_code == 200
    everyone = client.get("/api/payroll/payslips", params={"payrollId": run["id"]}, headers=h).json()
    assert everyone["meta"]["total"] == 2

    mine = client.get("/api/payroll/payslips", params={"scope": "my"}, headers=me["headers"]).json()
    assert mine["meta"]["total"] == 1 and mine["data"][0]["employeeId"] == str(setup["e1"])
    all_tab = client.get("/api/payroll/payslips", params={"scope": "all"}, headers=me["headers"]).json()
    assert [s["employeeId"] for s in all_tab["data"]] == [str(setup["e1"])]
    theirs = next(s for s in everyone["data"] if s["employeeId"] == str(other))
    assert client.get(f"/api/payroll/payslips/{theirs['id']}", headers=me["headers"]).status_code == 404
    assert client.get(f"/api/payroll/payslips/{mine['data'][0]['id']}", headers=me["headers"]).status_code == 200

    # Employees cannot run, edit or see payrolls, nor change their own payslip.
    assert client.post(f"/api/payroll/payrolls/{run['id']}/run", headers=me["headers"]).status_code == 403
    assert client.get("/api/payroll/payrolls", headers=me["headers"]).status_code == 403
    assert client.get("/api/payroll/settings/general", headers=me["headers"]).status_code == 403
    assert client.put(f"/api/payroll/payslips/{theirs['id']}", json={"lines": [{"payItemId": "1", "amount": 1}],
                                                                    "rowVersion": theirs["rowVersion"]},
                      headers=me["headers"]).status_code == 403


def test_close_locks_the_run(client, db, setup):
    h, run = setup["h"], setup["run"]
    factories.user(db, setup["company"], employee_id=setup["e1"], role_codes="employee")
    current = client.get(f"/api/payroll/payrolls/{run['id']}", headers=h).json()["data"]
    stale = client.post(f"/api/payroll/payrolls/{run['id']}/close", json={"rowVersion": run["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    r = client.post(f"/api/payroll/payrolls/{run['id']}/close", json={"rowVersion": current["rowVersion"]}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["data"]["status"] == "closed" and r.json()["data"]["closedAt"]

    slips = client.get("/api/payroll/payslips", params={"payrollId": run["id"]}, headers=h).json()["data"]
    assert {s["status"] for s in slips} == {"released"}
    closed = fe.events(db, setup["company"], "payroll.closed", int(run["id"]))
    assert len(closed) == 1 and closed[0]["data"]["kind"] == "monthly"
    assert closed[0]["data"]["payslipsReleased"] == len(slips) and closed[0]["data"]["payrollMonth"] == "2026-07-01"
    told = fe.notifications(db, setup["company"], setup["e1"], "pay.payslip")
    assert told and {n["title"] for n in told} == {"Your payslip for July 2026 is ready"}
    frozen = fp.rows(db, "SELECT COUNT(*) AS n, SUM(CAST(is_frozen AS INT)) AS f FROM att.timesheet_day "
                         "WHERE employee_id = ? AND work_date BETWEEN '2026-07-01' AND '2026-07-31'", setup["e1"])[0]
    assert frozen["n"] == 31 and frozen["f"] == 31
    inst = fp.rows(db, "SELECT due_month, status, payslip_id FROM loan.loan_installment WHERE loan_id = ? ORDER BY installment_no",
                   setup["loan"])
    assert inst[0]["status"] == "paid" and inst[0]["payslip_id"] and inst[1]["status"] == "pending"
    assert fp.scalar(db, "SELECT COUNT(*) FROM pay.employee_account_entry WHERE employee_id = ? AND is_processed = 1",
                     setup["e1"]) == 1

    assert client.post(f"/api/payroll/payrolls/{run['id']}/run", headers=h).status_code == 409
    slip = slips[0]
    locked = client.put(f"/api/payroll/payslips/{slip['id']}", json={"lines": [{"payItemId": "1", "amount": 1}],
                                                                    "rowVersion": slip["rowVersion"]}, headers=h)
    assert locked.status_code == 409
    assert client.put(f"/api/payroll/payrolls/{run['id']}/employees", json={"employeeIds": []}, headers=h).status_code == 409
    assert client.delete(f"/api/payroll/payrolls/{run['id']}", params={"rowVersion": r.json()["data"]["rowVersion"]},
                         headers=h).status_code == 409
    audit = fp.rows(db, "SELECT action_name FROM core.audit_log WHERE entity_type = N'pay.payroll' AND entity_id = ? "
                        "AND action_name = N'close'", int(run["id"]))
    assert len(audit) == 1

    # Pay marks a released slip paid; the dashboard and the summary report count it.
    paid = client.post("/api/payroll/payslips/pay", json={"ids": [s["id"] for s in slips]}, headers=h)
    assert paid.status_code == 200 and paid.json()["data"]["changed"] == 2
    assert len(fe.notifications(db, setup["company"], setup["e1"], "pay.payslip")) == len(told)  # already told
    dash = client.get("/api/payroll/dashboard", params={"year": 2026}, headers=h).json()["data"]
    assert dash["tiles"]["paidPayslips"] == 2 and dash["salaryStatistics"][0]["month"] == JULY
    summary = client.get(f"/api/payroll/reports/payroll-summary/{run['id']}", headers=h).json()["data"]
    assert summary["employeeCount"] == 2 and summary["paidAmount"] == summary["netPayable"]


def test_same_person_cannot_be_in_two_runs_of_a_month(client, db, setup):
    h = setup["h"]
    other_run = fp.payroll(client, h, JULY, setup["run"]["taxStructureId"], setup["run"]["disbursementBankId"])
    r = client.put(f"/api/payroll/payrolls/{other_run['id']}/employees", json={"employeeIds": [str(setup["e1"])]}, headers=h)
    assert r.status_code == 409 and r.json()["code"] == "PAYROLL_EMPLOYEE_CONFLICT"
