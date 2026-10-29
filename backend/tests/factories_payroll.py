"""Payroll test helpers. They write other modules' rows (salary, time sheet, leave, loans, end of employment)
with plain SQL on purpose: those screens belong to their own modules."""
from datetime import date, datetime, time, timedelta

from app.core.db import Db
from tests import factories


def scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute("SET NOCOUNT ON; " + sql, *params).fetchval()
    finally:
        cur.close()


def execute(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def rows(db: Db, sql: str, *params) -> list[dict]:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]
    finally:
        cur.close()


def employee(db: Db, company_id: int, salary: float | None = None, joined: date = date(2025, 1, 1),
             salary_from: date | None = None, frequency: str = "monthly", **kw) -> int:
    e = factories.employee(db, company_id, **kw)
    execute(db, "UPDATE hr.employee SET salary_frequency = ? WHERE id = ?", frequency, e)
    execute(db, "INSERT hr.employment_period (employee_id, joining_date) VALUES (?, ?)", e, joined)
    if salary is not None:
        execute(db, "INSERT hr.employee_salary (employee_id, effective_date, amount, source) VALUES (?, ?, ?, N'joining')",
                e, salary_from or joined, salary)
    return e


def day(db: Db, company_id: int, employee_id: int, work_date: date, status: str = "present", worked: int = 480,
        late: int = 0, early: int = 0, overtime: int = 0, first_in: time = time(9, 0)) -> int:
    start = datetime.combine(work_date, first_in)
    return scalar(db, "INSERT att.timesheet_day (company_id, employee_id, work_date, day_status, expected_in, expected_out, "
                      "expected_minutes, first_in, last_out, worked_minutes, late_minutes, early_left_minutes, "
                      "overtime_after_minutes) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, ?, 480, ?, ?, ?, ?, ?, ?)",
                  company_id, employee_id, work_date, status, datetime.combine(work_date, time(9, 0)),
                  datetime.combine(work_date, time(17, 0)), start if worked else None,
                  start + timedelta(minutes=worked) if worked else None, worked, late, early, overtime)


def month_days(db: Db, company_id: int, employee_id: int, year: int, month: int, absent: set[int] = frozenset(),
               late: dict[int, int] | None = None) -> None:
    d = date(year, month, 1)
    while d.month == month:
        if d.weekday() == 6:
            day(db, company_id, employee_id, d, "weekend", worked=0)
        elif d.day in absent:
            day(db, company_id, employee_id, d, "absent", worked=0)
        else:
            day(db, company_id, employee_id, d, "present", late=(late or {}).get(d.day, 0))
        d += timedelta(days=1)


def pay_item_id(db: Db, company_id: int, system_code: str) -> int:
    db.call("pay.usp_pay_item_system_ensure", company_id=company_id)
    return scalar(db, "SELECT id FROM pay.pay_item WHERE company_id = ? AND system_code = ?", company_id, system_code)


def employee_pay_item(db: Db, employee_id: int, pay_item: int, amount: float, effective: date = date(2025, 1, 1)) -> None:
    execute(db, "INSERT hr.employee_pay_item (employee_id, pay_item_id, amount, effective_date) VALUES (?, ?, ?, ?)",
            employee_id, pay_item, amount, effective)


def loan(db: Db, company_id: int, employee_id: int, installments: list[tuple[date, float]]) -> int:
    item = pay_item_id(db, company_id, "loan_deduction")
    loan_type = scalar(db, "INSERT loan.loan_type (company_id, name, min_experience_months, installments, deduction_pay_item_id) "
                           "OUTPUT INSERTED.id VALUES (?, ?, 0, ?, ?)", company_id, f"Loan {factories.tag()}",
                       len(installments), item)
    loan_id = scalar(db, "INSERT loan.loan (company_id, employee_id, loan_type_id, principal, installments, status) "
                         "OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, N'active')", company_id, employee_id, loan_type,
                     sum(a for _, a in installments), len(installments))
    for n, (due, amount) in enumerate(installments, 1):
        execute(db, "INSERT loan.loan_installment (loan_id, installment_no, due_month, amount, status) "
                    "VALUES (?, ?, ?, ?, N'pending')", loan_id, n, due, amount)
    return loan_id


def leave_type(db: Db, company_id: int, title: str | None = None, deductible: bool = False, encash: bool = False,
               encash_max: float | None = None) -> int:
    return scalar(db, "INSERT lv.leave_type (company_id, title, gender, marital_status, tenure, balance_basis, is_active, "
                      "is_deductible, allow_encashment, encashment_max) OUTPUT INSERTED.id "
                      "VALUES (?, ?, N'all', N'all', N'yearly', N'yearly', 1, ?, ?, ?)",
                  company_id, title or f"Leave {factories.tag()}", deductible, encash, encash_max)


def ledger(db: Db, employee_id: int, leave_type_id: int, fiscal_year: int, entry_date: date, days: float,
           reason: str = "allotment") -> None:
    execute(db, "INSERT lv.leave_ledger (employee_id, leave_type_id, fiscal_year, entry_date, days, reason) "
                "VALUES (?, ?, ?, ?, ?, ?)", employee_id, leave_type_id, fiscal_year, entry_date, days, reason)


def end_of_employment(db: Db, company_id: int, employee_id: int, last_working_date: date) -> int:
    return scalar(db, "INSERT sep.end_of_employment (company_id, employee_id, reason, last_working_date, "
                      "needs_final_settlement, status) OUTPUT INSERTED.id VALUES (?, ?, N'resignation', ?, 1, N'pending')",
                  company_id, employee_id, last_working_date)


def time_slot(db: Db, company_id: int) -> int:
    return scalar(db, "INSERT sch.time_slot (company_id, code, name, start_time, end_time, duration_minutes, workable_minutes) "
                      "OUTPUT INSERTED.id VALUES (?, ?, ?, '09:00', '17:00', 480, 480)",
                  company_id, f"TS-{factories.tag()}", f"Day shift {factories.tag()}")


# --------------------------------------------------------------------------- through the API

SLABS = [  # annual taxable income: fixed amount + percentage of the part above the minimum
    {"minAmount": 0, "maxAmount": 600000, "fixedAmount": 0, "percentage": 0},
    {"minAmount": 600000, "maxAmount": 1200000, "fixedAmount": 0, "percentage": 5},
    {"minAmount": 1200000, "maxAmount": 2200000, "fixedAmount": 30000, "percentage": 15},
    {"minAmount": 2200000, "maxAmount": None, "fixedAmount": 180000, "percentage": 25},
]


def tax_structure(client, headers, start: str = "2026-07-01", end: str = "2027-06-30") -> dict:
    r = client.post("/api/payroll/tax-structures", json={"name": f"Tax Structure {factories.tag()}", "startDate": start,
                                                        "endDate": end, "slabs": SLABS}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def bank(client, headers) -> dict:
    r = client.post("/api/payroll/disbursement-banks",
                    json={"accountHolder": "Company Payroll", "accountNumber": f"PK{factories.tag()}",
                          "bankName": "UBL", "branchCode": "0102", "branchLocation": "Lahore", "taxPayerId": "1234567-8"},
                    headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def payroll(client, headers, month: str, tax_structure_id: str, bank_id: str, **kw) -> dict:
    body = {"name": f"Payroll {factories.tag()}", "payrollMonth": month, "currency": "PKR",
            "taxStructureId": tax_structure_id, "taxApplicable": True, "processingMode": "month_end",
            "processingDate": month, "applicableDays": "fixed", "fixedDays": 30, "disbursementBankId": bank_id, **kw}
    r = client.post("/api/payroll/payrolls", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def bank_account(db: Db, employee_id: int, account_number: str | None = None, bank_name: str = "Meezan Bank",
                 primary: bool = True) -> str:
    number = account_number or f"PK{factories.tag()}"
    execute(db, "INSERT hr.employee_bank_account (employee_id, account_holder, account_number, bank_name, branch_code, "
                "is_primary) VALUES (?, NULL, ?, ?, N'0201', ?)", employee_id, number, bank_name, primary)
    return number


def email(db: Db, employee_id: int, address: str | None = None) -> str:
    address = address or f"emp.{factories.tag()}@test.local"
    execute(db, "UPDATE hr.employee SET email = ? WHERE id = ?", address, employee_id)
    return address
