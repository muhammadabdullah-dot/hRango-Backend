## 9. Payroll [pay]

```
tax_structure                         Settings -> Tax -> Tax Structure
  id PK, company_id FK company
  code                                TXS-0004, from core.number_sequence prefix TXS-
  name, start_date {NN}, end_date {NN}
  UNIQUE (company_id, name)
  surcharge_type                      flat, percentage (optional)
  surcharge_value
  description

tax_slab                              tax = fixed_amount + (annual taxable - min_amount) x percentage / 100
  id PK, tax_structure_id FK tax_structure, min_amount {NN}, max_amount, fixed_amount {NN}, percentage {NN}

tax_rebate                            Settings -> Tax -> Tax Rebate; lowers the year's tax
  id PK, employee_id FK employee, rebate_date {NN}, amount {NN}, file_id FK stored_file, description

formula                               Pay Components -> Formulas; {variables}, pay items and other formulas
  id PK, company_id FK company, name
  UNIQUE (company_id, name)
  expression {NN}
  is_salary_division, for_integration
  is_custom                           0 for the formulas the system adds for its own pay items
  description

pay_item                              Pay Components -> Pay Items
  id                PK
  company_id        FK company
  name, label
  UNIQUE (company_id, name)
  item_type {NN}                      earning, deduction, reimbursement, employee_data, other
  calculation_type {NN}               fixed (per-person amount), manual (typed on the payslip), formula
  tax_distribution {NN}               current_month, remaining_months
  employee_formula_id {NULL} FK formula   required for calculation_type formula
  employer_formula_id {NULL} FK formula   employer contribution
  is_taxable                          default for the Taxable tick when the item is added to a payroll
  is_display_only, is_benefit, is_advance_payment
  eligibility_expression              true/false expression; blank = everyone
  system_code {NVARCHAR(30)}          salary, overtime, absent_deduction, leave_deduction, short_deduction, penalty_deduction, loan_deduction, leave_encashment, tax
  UNIQUE (company_id, system_code)
  description

pay_rule                              Pay Components -> Rules: evaluated per person on every run, posts to an employee account
  id PK, company_id FK company, name, expression {NN}, account_type_id FK account_type, description
  UNIQUE (company_id, name)

account_type                          Settings -> Account Type
  id PK, company_id FK company
  code                                ACT-0001, from core.number_sequence prefix ACT-
  category {NN}                       benefit, leave_quota, custom_pay_item
  ref_id {BIGINT}                     reward_benefit, lv.leave_type or pay_item, by category
  name
  UNIQUE (company_id, name)

reward_benefit                        Settings -> Rewards -> Benefits ("Benefit Create")
  id PK, company_id FK company, name, benefit_type {NN}, pay_item_id FK pay_item, formula_id {NULL} FK formula, is_group, is_accumulative, description
  UNIQUE (company_id, name)

reward_benefit_member                 who gets it: employees, or employee groups when is_group
  id PK, reward_benefit_id FK reward_benefit, employee_id {NULL} FK employee, employee_group_id {NULL} FK employee_group

reward_benefit_field                  "Additional Information" fields of a benefit
  id PK, reward_benefit_id FK reward_benefit, name, field_type {NN}, is_required, min_value {DECIMAL(18,4)}, max_value {DECIMAL(18,4)}, min_length, max_length, field_value

sales_incentive                       Settings -> Rewards -> Incentives (stored; no sales source yet)
  id PK, company_id FK company, branch_id FK branch, applicable_month {NN}, incentive_type {NN}, target_amount {NN}, value_type {NN}, reward_value {NN}, description

disbursement_bank                     Settings -> Disbursement Banks (the company's paying accounts)
  id PK, company_id FK company, account_holder {NN}, account_number {NN}, bank_name {NN}, branch_name, branch_code {NN}, branch_location {NN}, tax_payer_id {NN}, effective_date, description
  UNIQUE (company_id, account_number)

payroll                               Payrolls -> Monthly and Daily Wages
  id                PK
  company_id        FK company
  code                                PR-00008, from core.number_sequence prefix PR-
  name
  kind                                monthly, daily_wage
  payroll_month                       monthly runs: first day of the month
  work_date                           daily-wage runs
  time_slot_id {NULL} FK time_slot    daily-wage runs
  currency {CHAR(3)}
  tax_structure_id {NULL} FK tax_structure
  tax_applicable
  processing_mode                     from_date, month_end
  processing_date
  applicable_days                     actual, fixed
  fixed_days
  disbursement_bank_id {NULL} FK disbursement_bank
  description
  status                              open, running, on_hold, closed
  last_run_at, closed_at
  closed_by_user_id FK user_account

payroll_pay_item                      which pay items this run uses
  id PK, payroll_id FK payroll, pay_item_id {NN} FK pay_item, is_taxable, arrear_applicable, final_settlement, calculate_only
  UNIQUE (payroll_id, pay_item_id)

payroll_employee                      who is in the run
  payroll_id FK payroll, employee_id FK employee                       *──*

payroll_run_log                       Payrolls History
  id PK, payroll_id FK payroll, kind, started_at, finished_at, status, run_by_user_id FK user_account, processed_count {INT}, error_count {INT}

payroll_run_error                     Payrolls History Error
  id PK, payroll_run_log_id FK payroll_run_log, employee_id {NULL} FK employee, message

payslip                               one per person per run; final settlement slips have no run
  id                PK
  company_id        FK company
  payroll_id {NULL} FK payroll        blank for a final settlement slip
  employee_id       FK employee
  payslip_month {NN}
  applicable_days {DECIMAL(6,2)}
  worked_days, worked_minutes, expected_minutes, leave_days, absent_days, overtime_minutes
  gross, total_earnings, total_deductions, total_reimbursements, net_payable
  taxable_income {DECIMAL(18,2)}
  tax_amount
  status                              ready, on_hold, released
  payment_method                      bank, cash
  released_at, paid_at
  is_final_settlement
  is_manually_updated                 daily wages: totals typed by hand

payslip_line
  id PK, payslip_id FK payslip, pay_item_id {NN} FK pay_item, amount, employer_contribution, is_taxable, is_manually_updated
  UNIQUE (payslip_id, pay_item_id)

opening_balance                       Balances -> Opening Balance; added to the pay item in that month's run
  id PK, employee_id FK employee, balance_month {NN}, pay_item_id {NN} FK pay_item, amount {NN}, is_taxable, kind, description

employee_account_entry                Provident Fund, EOBI, medical … ledger (Employee Accounts, Statement)
  id PK, employee_id FK employee, account_type_id {NN} FK account_type, entry_month {NN}, credit, debit, is_processed, payslip_id FK payslip, pay_rule_id {NULL} FK pay_rule, description

voucher                               Vouchers / Employee Voucher; daily-wage vouchers
  id                PK
  company_id        FK company
  voucher_no {NN}
  UNIQUE (company_id, voucher_no)
  employee_id       FK employee
  voucher_type {NN}                   expense_reimbursement, salary_advance, bonus, travel_allowance, daily_wage
  voucher_date {NN}
  currency {CHAR(3)}
  amount {NN}
  payment_method, purpose, notes
  file_id           FK stored_file    attachment
  payroll_id        FK payroll        daily-wage voucher
  UNIQUE (payroll_id, employee_id)
  requested_by_id   FK employee
  approved_by_id    FK employee
  decided_by_user_id FK user_account  who approved or rejected (kept when the account has no employee record)
  approved_at
  verified_by_id    FK employee
  verified_by_user_id FK user_account  who verified
  verified_at
  remarks                             approver's or verifier's remarks
  status                              pending, approved, rejected, processed
```

```
tax_structure 1──* tax_slab
formula 1──* pay_item (employee / employer formula)
pay_rule *──1 account_type
reward_benefit 1──* reward_benefit_member / reward_benefit_field
payroll 1──* payroll_pay_item *──1 pay_item
payroll *──* employee   (payroll_employee)
payroll 1──* payslip 1──* payslip_line *──1 pay_item
payroll 1──* payroll_run_log 1──* payroll_run_error
employee 1──* opening_balance / employee_account_entry / tax_rebate / voucher
```
