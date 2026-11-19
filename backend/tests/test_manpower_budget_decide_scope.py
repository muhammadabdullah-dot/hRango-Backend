"""Test Run (18-19 Nov 2026) row 12.38: Finance reads every department's budgets but decides only its own
department's. Each budget row says whether the caller may approve or reject it (canApprove / canReject), and
deciding another department's budget is refused with the reason, not "Budget not found"."""
from tests import factories
from tests import factories_manpower as mpf

API = "/api/manpower"


def _budget(client, h, duration_id: str, department_id: int, title: str) -> dict:
    r = client.post(f"{API}/budgets", headers=h, json={
        "budgetDurationId": duration_id, "title": title, "departmentId": department_id, "amount": 1000,
        "startDate": "2033-01-01", "endDate": "2033-01-31"})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_finance_decides_only_its_own_departments_budgets(client, db, company, admin):
    h = admin["headers"]
    duration = mpf.duration(client, h, "2033-01-01", "2033-12-31")
    finance_dept = factories.department(db, company, name=f"Finance {factories.tag()}")
    qa = factories.department(db, company, name=f"Quality Assurance {factories.tag()}")
    own = _budget(client, h, duration["id"], finance_dept, "Accountant")
    other = _budget(client, h, duration["id"], qa, "SQA Engineer")

    # The Finance Manager: reads budgets company-wide (Finance) and heads the Finance department.
    nadia = factories.employee(db, company, department_id=finance_dept, first_name="Nadia")
    fm = factories.login_as(db, client, company, role_codes="finance,department_head", employee_id=nadia)["headers"]
    rows = {b["id"]: b for b in client.get(f"{API}/budget-approvals", params={"pageSize": 100, "q": "SQA Engineer"},
                                           headers=fm).json()["data"]}
    rows.update({b["id"]: b for b in client.get(f"{API}/budget-approvals", params={"pageSize": 100, "q": "Accountant"},
                                                headers=fm).json()["data"]})
    assert own["id"] in rows and other["id"] in rows  # she reads both
    assert (rows[own["id"]]["canApprove"], rows[own["id"]]["canReject"]) == (True, True)
    assert (rows[other["id"]]["canApprove"], rows[other["id"]]["canReject"]) == (False, False)
    seen = client.get(f"{API}/budgets/{other['id']}", headers=fm).json()["data"]
    assert seen["canApprove"] is False

    refused = client.post(f"{API}/budgets/{other['id']}/approve", headers=fm, json={"rowVersion": other["rowVersion"]})
    assert refused.status_code == 403, refused.text
    assert "Quality Assurance" in refused.json()["message"] and "not found" not in refused.json()["message"].lower()
    rejected = client.post(f"{API}/budgets/{other['id']}/reject", headers=fm,
                           json={"rowVersion": other["rowVersion"], "remarks": "No"})
    assert rejected.status_code == 403 and "reject" in rejected.json()["message"]

    ok = client.post(f"{API}/budgets/{own['id']}/approve", headers=fm, json={"rowVersion": own["rowVersion"]})
    assert ok.status_code == 200, ok.text
    # Decided: nobody is offered the actions any more.
    assert (ok.json()["data"]["canApprove"], ok.json()["data"]["canReject"]) == (False, False)

    # The administrator (company scope) may decide the other department's budget.
    mine = client.get(f"{API}/budgets/{other['id']}", headers=h).json()["data"]
    assert mine["canApprove"] is True and mine["canReject"] is True

    # Someone who cannot even read it still gets "not found".
    outsider_emp = factories.employee(db, company, department_id=finance_dept)
    head = factories.login_as(db, client, company, role_codes="department_head", employee_id=outsider_emp)["headers"]
    assert client.post(f"{API}/budgets/{other['id']}/approve", headers=head,
                       json={"rowVersion": other["rowVersion"]}).status_code == 404
