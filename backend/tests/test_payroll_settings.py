"""Payroll Settings: general options with row versions, pay components and their expressions, tax
structures, rewards, account types, banks, and who may reach them."""
import pytest

from tests import factories
from tests import factories_payroll as fp


@pytest.fixture(scope="module")
def ctx(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    return {"company": company, "h": admin["headers"]}


def test_general_settings_round_trip_and_row_version(client, ctx):
    h = ctx["h"]
    first = client.get("/api/payroll/settings/general", headers=h).json()["data"]
    assert first["rowVersion"] is None and first["taxRounding"] == "actual" and first["showSalaryBreakdown"] is True

    body = {**first, "taxRounding": "ceil", "hidePayslipAfterRun": True, "notesEnglishEnabled": True,
            "notesEnglish": "Next payroll on the 24th.", "leaveYearBasis": "fiscal", "fiscalYearStartMonth": 7,
            "fiscalYearEndMonth": 6}
    saved = client.put("/api/payroll/settings/general", json=body, headers=h)
    assert saved.status_code == 200, saved.text
    data = saved.json()["data"]
    assert data["taxRounding"] == "ceil" and data["hidePayslipAfterRun"] is True and data["rowVersion"]

    stale = client.put("/api/payroll/settings/general", json={**body, "taxRounding": "floor"}, headers=h)
    assert stale.status_code == 409
    again = client.put("/api/payroll/settings/general", json={**data, "taxRounding": "floor"}, headers=h)
    assert again.status_code == 200 and again.json()["data"]["taxRounding"] == "floor"

    bad = client.put("/api/payroll/settings/general", json={**again.json()["data"], "taxRounding": "sideways"}, headers=h)
    assert bad.status_code == 422 and "taxRounding" in bad.json()["fieldErrors"]
    missing = client.put("/api/payroll/settings/general",
                         json={**again.json()["data"], "cutoffProration": True, "cutoffDay": None}, headers=h)
    assert missing.status_code == 422 and "cutoffDay" in missing.json()["fieldErrors"]


def test_system_pay_items_and_formulas(client, ctx):
    h = ctx["h"]
    items = client.get("/api/payroll/pay-items", params={"pageSize": 100}, headers=h).json()["data"]
    codes = {i["systemCode"] for i in items if i["systemCode"]}
    assert codes == {"salary", "overtime", "absent_deduction", "leave_deduction", "short_deduction", "penalty_deduction",
                     "loan_deduction", "leave_encashment", "tax"}
    salary = next(i for i in items if i["systemCode"] == "salary")
    assert salary["expression"] == "{gross_salary} * {employed_days} / {month_days}" and salary["reference"] == "{salary}"

    gone = client.delete(f"/api/payroll/pay-items/{salary['id']}", params={"rowVersion": salary["rowVersion"]}, headers=h)
    assert gone.status_code == 409
    retype = client.put(f"/api/payroll/pay-items/{salary['id']}", json={
        "name": "Salary", "itemType": "deduction", "calculationType": "formula", "taxDistribution": "current_month",
        "employeeFormulaId": salary["employeeFormulaId"], "rowVersion": salary["rowVersion"]}, headers=h)
    assert retype.status_code == 422

    variables = client.get("/api/payroll/settings/variables", headers=h).json()["data"]
    assert {"gross_salary", "absent_days"} <= {v["name"] for v in variables if v["kind"] == "variable"}
    check = client.post("/api/payroll/settings/expressions/check", json={"expression": "{salary} * 0.1"}, headers=h).json()
    assert check["data"]["valid"] is True
    check = client.post("/api/payroll/settings/expressions/check", json={"expression": "{nope} + 1"}, headers=h).json()
    assert check["data"]["valid"] is False


def test_formula_expressions_are_checked(client, ctx):
    h = ctx["h"]
    name = f"House Rent {factories.tag()}"
    ok = client.post("/api/payroll/formulas", json={"name": name, "expression": "{gross_salary} * 0.45"}, headers=h)
    assert ok.status_code == 201, ok.text
    formula = ok.json()["data"]
    assert formula["isCustom"] is True

    for bad in ("{gross_salary} *", "__import__('os')", "{unknown_thing} + 1", "gross_salary + 1"):
        r = client.post("/api/payroll/formulas", json={"name": f"Bad {factories.tag()}", "expression": bad}, headers=h)
        assert r.status_code == 422 and "expression" in r.json()["fieldErrors"], (bad, r.text)

    reserved = client.post("/api/payroll/formulas", json={"name": "Gross Salary", "expression": "1"}, headers=h)
    assert reserved.status_code == 409 and reserved.json()["code"] == "NAME_RESERVED"

    item = client.post("/api/payroll/pay-items", json={
        "name": f"HRA {factories.tag()}", "itemType": "earning", "calculationType": "formula",
        "taxDistribution": "remaining_months", "employeeFormulaId": formula["id"], "isTaxable": True}, headers=h)
    assert item.status_code == 201, item.text
    no_formula = client.post("/api/payroll/pay-items", json={
        "name": f"X {factories.tag()}", "itemType": "earning", "calculationType": "formula",
        "taxDistribution": "current_month"}, headers=h)
    assert no_formula.status_code == 422 and "employeeFormulaId" in no_formula.json()["fieldErrors"]

    # A formula that names the pay item built on it is a loop.
    ref = item.json()["data"]["reference"]
    loop = client.put(f"/api/payroll/formulas/{formula['id']}", json={"name": name, "expression": f"{ref} + 1",
                                                                       "rowVersion": formula["rowVersion"]}, headers=h)
    assert loop.status_code == 422 and loop.json()["code"] == "EXPRESSION_LOOP"

    stale_free = client.put(f"/api/payroll/formulas/{formula['id']}", json={
        "name": name, "expression": "{gross_salary} * 0.5", "rowVersion": formula["rowVersion"]}, headers=h)
    assert stale_free.status_code == 200
    stale = client.put(f"/api/payroll/formulas/{formula['id']}", json={
        "name": name, "expression": "{gross_salary} * 0.4", "rowVersion": formula["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    in_use = client.delete(f"/api/payroll/formulas/{formula['id']}",
                           params={"rowVersion": stale_free.json()["data"]["rowVersion"]}, headers=h)
    assert in_use.status_code == 409


def test_tax_structures_and_rebates(client, db, ctx):
    h = ctx["h"]
    ts = fp.tax_structure(client, h)
    assert ts["code"].startswith("TXS-") and len(ts["slabs"]) == 4 and ts["slabs"][1]["percentage"] == 5
    dup = client.post("/api/payroll/tax-structures", json={"name": ts["name"], "startDate": "2026-07-01",
                                                          "endDate": "2027-06-30", "slabs": fp.SLABS}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "TAX_STRUCTURE_DUPLICATE"
    overlap = client.post("/api/payroll/tax-structures", json={
        "name": f"Overlap {factories.tag()}", "startDate": "2026-07-01", "endDate": "2027-06-30",
        "slabs": [{"minAmount": 0, "maxAmount": 700000}, {"minAmount": 600000, "maxAmount": None, "percentage": 5}]},
                          headers=h)
    assert overlap.status_code == 422 and "slabs.1.minAmount" in overlap.json()["fieldErrors"]
    backwards = client.post("/api/payroll/tax-structures", json={
        "name": f"Back {factories.tag()}", "startDate": "2027-07-01", "endDate": "2026-06-30", "slabs": fp.SLABS}, headers=h)
    assert backwards.status_code == 422

    e = fp.employee(db, ctx["company"], salary=50000)
    proof = factories.upload(client, h, name="Donation receipt.pdf", module="payroll")
    rebate = client.post("/api/payroll/tax-rebates", json={"employeeId": str(e), "rebateDate": "2026-09-01",
                                                          "amount": 12000, "fileId": int(proof["id"])}, headers=h)
    assert rebate.status_code == 201, rebate.text
    assert rebate.json()["data"]["file"]["name"] == "Donation receipt.pdf"
    listed = client.get("/api/payroll/tax-rebates", params={"employeeId": str(e)}, headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["amount"] == 12000
    assert listed["data"][0]["file"]["id"] == proof["id"]
    assert client.get(listed["data"][0]["file"]["url"]).status_code == 200
    missing = client.post("/api/payroll/tax-rebates", json={"employeeId": str(e), "rebateDate": "2026-09-02",
                                                           "amount": 1, "fileId": 999999999}, headers=h)
    assert missing.status_code == 422 and "fileId" in missing.json()["fieldErrors"]


def test_rewards_account_types_banks(client, db, ctx):
    h = ctx["h"]
    items = client.get("/api/payroll/pay-items", params={"pageSize": 100}, headers=h).json()["data"]
    salary = next(i for i in items if i["systemCode"] == "salary")
    e = fp.employee(db, ctx["company"], salary=50000)

    group_without_members = client.post("/api/payroll/benefits", json={
        "name": f"Bonus {factories.tag()}", "benefitType": "bonus", "payItemId": salary["id"], "isGroup": True}, headers=h)
    assert group_without_members.status_code == 422 and "members" in group_without_members.json()["fieldErrors"]
    required = client.post("/api/payroll/benefits", json={
        "name": f"Bonus {factories.tag()}", "benefitType": "bonus", "payItemId": salary["id"],
        "fields": [{"name": "Grade", "fieldType": "number", "isRequired": True}]}, headers=h)
    assert required.status_code == 422
    benefit = client.post("/api/payroll/benefits", json={
        "name": f"Bonus {factories.tag()}", "benefitType": "bonus", "payItemId": salary["id"], "isGroup": True,
        "members": [{"employeeId": str(e)}], "fields": [{"name": "Grade", "fieldType": "number", "fieldValue": "7"}]},
                          headers=h)
    assert benefit.status_code == 201, benefit.text
    b = benefit.json()["data"]
    assert b["memberCount"] == 1 and b["members"][0]["employeeId"] == str(e) and b["fields"][0]["fieldValue"] == "7"
    # A member that is an employee group has no employee name (null, not " ").
    group = fp.scalar(db, "INSERT org.employee_group (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)", ctx["company"],
                      f"Group {factories.tag()}")
    by_group = client.post("/api/payroll/benefits", json={
        "name": f"Bonus {factories.tag()}", "benefitType": "bonus", "payItemId": salary["id"], "isGroup": True,
        "members": [{"employeeGroupId": str(group)}]}, headers=h)
    assert by_group.status_code == 201, by_group.text
    m = by_group.json()["data"]["members"][0]
    assert m["employeeGroupId"] == str(group) and m["employeeId"] is None and m["employeeName"] is None

    branch = factories.branch(db, ctx["company"])
    inc = client.post("/api/payroll/incentives", json={"branchId": str(branch), "applicableMonth": "2026-07-15",
                                                       "incentiveType": "part_of_salary", "targetAmount": 1000000,
                                                       "valueType": "percentage", "rewardValue": 5}, headers=h)
    assert inc.status_code == 201 and inc.json()["data"]["applicableMonth"] == "2026-07-01"

    acct = client.post("/api/payroll/account-types", json={"name": f"Medical {factories.tag()}", "category": "benefit",
                                                           "refId": b["id"]}, headers=h)
    assert acct.status_code == 201 and acct.json()["data"]["refName"] == b["name"] and acct.json()["data"]["code"].startswith("ACT-")
    no_ref = client.post("/api/payroll/account-types", json={"name": f"X {factories.tag()}", "category": "leave_quota"},
                         headers=h)
    assert no_ref.status_code == 422 and "refId" in no_ref.json()["fieldErrors"]

    bank = fp.bank(client, h)
    dup = client.post("/api/payroll/disbursement-banks", json={
        "accountHolder": "X", "accountNumber": bank["accountNumber"], "bankName": "X", "branchCode": "1",
        "branchLocation": "X", "taxPayerId": "1"}, headers=h)
    assert dup.status_code == 409
    renamed = client.put(f"/api/payroll/disbursement-banks/{bank['id']}", json={
        **{k: bank[k] for k in ("accountHolder", "accountNumber", "bankName", "branchCode", "branchLocation", "taxPayerId")},
        "branchName": "Gulberg", "rowVersion": bank["rowVersion"]}, headers=h)
    assert renamed.status_code == 200 and renamed.json()["data"]["branchName"] == "Gulberg"
    assert client.delete(f"/api/payroll/disbursement-banks/{bank['id']}", params={"rowVersion": bank["rowVersion"]},
                         headers=h).status_code == 409
    assert client.delete(f"/api/payroll/disbursement-banks/{bank['id']}",
                         params={"rowVersion": renamed.json()["data"]["rowVersion"]}, headers=h).status_code == 204


def test_settings_need_permissions(client, db, ctx):
    e = fp.employee(db, ctx["company"], salary=50000)
    staff = factories.login_as(db, client, ctx["company"], role_codes="employee", employee_id=e)
    finance = factories.login_as(db, client, ctx["company"], role_codes="finance")
    for url in ("/api/payroll/settings/general", "/api/payroll/pay-items", "/api/payroll/tax-structures",
                "/api/payroll/disbursement-banks"):
        assert client.get(url, headers=staff["headers"]).status_code == 403, url
    # Finance reads payroll settings but cannot change them.
    assert client.get("/api/payroll/pay-items", headers=finance["headers"]).status_code == 200
    assert client.post("/api/payroll/formulas", json={"name": "F", "expression": "1"},
                       headers=finance["headers"]).status_code == 403
    # Another company's records are not found.
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    ts = fp.tax_structure(client, ctx["h"])
    assert client.get(f"/api/payroll/tax-structures/{ts['id']}", headers=other_admin["headers"]).status_code == 404
