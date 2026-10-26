"""Run lifecycle around the engine: adding people by filters, group benefits, opening balances, hold and
unhold, history, deleting an unclosed run."""
from tests import factories
from tests import factories_payroll as fp


def test_benefits_balances_hold_and_delete(client, db):
    company = factories.company(db)
    h = factories.login_as(db, client, company, role_codes="company_admin")["headers"]
    dept = factories.department(db, company)
    group = fp.scalar(db, "INSERT org.employee_group (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)", company,
                      f"Shift workers {factories.tag()}")
    member = fp.employee(db, company, salary=30000, department_id=dept, first_name="Member")
    outsider = fp.employee(db, company, salary=30000, department_id=dept, first_name="Outsider")
    fp.execute(db, "UPDATE hr.employee SET employee_group_id = ? WHERE id = ?", group, member)

    formula = client.post("/api/payroll/formulas", json={"name": f"Ten percent {factories.tag()}",
                                                         "expression": "{gross_salary} * 0.1"}, headers=h).json()["data"]
    bonus = client.post("/api/payroll/pay-items", json={"name": f"Shift Bonus {factories.tag()}", "itemType": "earning",
                                                        "calculationType": "fixed", "taxDistribution": "current_month"},
                        headers=h).json()["data"]
    r = client.post("/api/payroll/benefits", json={"name": f"Shift {factories.tag()}", "benefitType": "bonus",
                                                   "payItemId": bonus["id"], "formulaId": formula["id"], "isGroup": True,
                                                   "members": [{"employeeGroupId": str(group)}]}, headers=h)
    assert r.status_code == 201, r.text
    arrears = client.post("/api/payroll/pay-items", json={"name": f"Arrears {factories.tag()}", "itemType": "earning",
                                                          "calculationType": "manual", "taxDistribution": "current_month"},
                          headers=h).json()["data"]
    ob = client.post("/api/payroll/opening-balances", json={"employeeId": str(outsider), "balanceMonth": "2026-07-01",
                                                            "payItemId": arrears["id"], "amount": 2000}, headers=h)
    assert ob.status_code == 201, ob.text

    tax = fp.tax_structure(client, h)
    bank = fp.bank(client, h)
    run = fp.payroll(client, h, "2026-07-01", tax["id"], bank["id"], taxApplicable=False)
    assert {i["systemCode"] for i in run["payItems"]} >= {"salary", "tax"} and len(run["payItems"]) == 11

    added = client.post(f"/api/payroll/payrolls/{run['id']}/employees/add", json={"departmentId": str(dept)}, headers=h)
    assert added.status_code == 200 and added.json()["data"]["added"] == 2, added.text
    people = client.get(f"/api/payroll/payrolls/{run['id']}/employees", headers=h).json()["data"]
    assert {p["employeeId"] for p in people} == {str(member), str(outsider)}

    assert client.post(f"/api/payroll/payrolls/{run['id']}/hold", headers=h).status_code == 409  # not run yet
    log = client.post(f"/api/payroll/payrolls/{run['id']}/run", headers=h).json()["data"]
    assert log["processedCount"] == 2 and log["errorCount"] == 0

    slips = client.get("/api/payroll/payslips", params={"payrollId": run["id"]}, headers=h).json()["data"]
    by_emp = {s["employeeId"]: client.get(f"/api/payroll/payslips/{s['id']}", headers=h).json()["data"] for s in slips}
    m = {l["payItemName"]: l["amount"] for l in by_emp[str(member)]["lines"]}
    o = {l["payItemName"]: l["amount"] for l in by_emp[str(outsider)]["lines"]}
    assert m == {"Salary": 30000, bonus["name"]: 3000}
    assert o == {"Salary": 30000, arrears["name"]: 2000}
    assert by_emp[str(member)]["netPayable"] == 33000 and by_emp[str(outsider)]["netPayable"] == 32000

    held = client.post(f"/api/payroll/payrolls/{run['id']}/hold", headers=h)
    assert held.status_code == 200 and held.json()["data"]["status"] == "on_hold"
    assert {s["status"] for s in client.get("/api/payroll/payslips", params={"payrollId": run["id"]},
                                            headers=h).json()["data"]} == {"on_hold"}
    cannot_pay = client.post("/api/payroll/payslips/pay", json={"ids": [s["id"] for s in slips]}, headers=h)
    assert cannot_pay.status_code == 409
    assert client.post(f"/api/payroll/payrolls/{run['id']}/unhold", headers=h).json()["data"]["status"] == "running"
    one = client.post("/api/payroll/payslips/hold", json={"ids": [slips[0]["id"]]}, headers=h).json()["data"]
    assert one["changed"] == 1
    history = client.get(f"/api/payroll/payrolls/{run['id']}/history", headers=h).json()["data"]
    assert [x["kind"] for x in history] == ["run"]

    current = client.get(f"/api/payroll/payrolls/{run['id']}", headers=h).json()["data"]
    assert client.delete(f"/api/payroll/payrolls/{run['id']}", params={"rowVersion": run["rowVersion"]},
                         headers=h).status_code == 409
    assert client.delete(f"/api/payroll/payrolls/{run['id']}", params={"rowVersion": current["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"/api/payroll/payrolls/{run['id']}", headers=h).status_code == 404
