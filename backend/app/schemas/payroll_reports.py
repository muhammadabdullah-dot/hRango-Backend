"""Payroll reports and the payroll dashboard."""
from datetime import date

from app.schemas.common import ApiModel


class AccountBalanceLineOut(ApiModel):
    account_type_id: str
    account_name: str
    credit: float
    debit: float
    balance: float


class EmployeeAccountReportOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    tax_paid: float
    tax_rebate: float
    accounts: list[AccountBalanceLineOut]


class PayItemTotalOut(ApiModel):
    pay_item_id: str
    pay_item_name: str
    item_type: str
    amount: float
    employer_contribution: float
    employee_count: int


class PayrollSummaryOut(ApiModel):
    payroll_id: str
    code: str
    name: str
    kind: str
    payroll_month: date | None
    work_date: date | None
    status: str
    employee_count: int
    gross: float
    total_earnings: float
    total_deductions: float
    total_reimbursements: float
    tax: float
    net_payable: float
    on_hold_count: int
    on_hold_amount: float
    paid_amount: float
    pay_items: list[PayItemTotalOut]


class EmployeeWiseRowOut(ApiModel):
    payslip_id: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    payslip_month: date
    payroll_name: str | None
    is_final_settlement: bool
    gross: float | None
    total_earnings: float | None
    total_reimbursements: float | None
    total_deductions: float | None
    tax_amount: float | None
    net_payable: float | None
    status: str


class DailyWagesRowOut(ApiModel):
    payroll_id: str
    code: str
    name: str
    work_date: date
    time_slot_name: str | None
    status: str
    employee_count: int
    worked_minutes: int
    net_payable: float
    voucher_count: int
    vouchers_processed: int


class DashboardTilesOut(ApiModel):
    total_payrolls: int
    closed_payrolls: int
    total_payslips: int
    released_payslips: int
    paid_payslips: int
    on_hold_payslips: int
    unpaid_payslips: int
    net_payable: float
    paid_amount: float


class DashboardMonthOut(ApiModel):
    month: date
    gross: float
    tax: float
    deductions: float
    net_payable: float
    payslip_count: int


class DashboardBreakupOut(ApiModel):
    pay_item_id: str
    pay_item_name: str
    item_type: str
    amount: float


class DashboardOut(ApiModel):
    year: int
    breakup_month: date | None
    tiles: DashboardTilesOut
    salary_statistics: list[DashboardMonthOut]
    salary_breakup: list[DashboardBreakupOut]
