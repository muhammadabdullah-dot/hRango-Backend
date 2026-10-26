## 8. Loans [loan]

```
loan_type                             Loan & Advance Types settings
  id                PK
  company_id        FK company
  name, is_active
  guarantor_required, non_payable
  min_experience_months {NN}
  gap_between_requests_months
  installments      {NN}
  gap_between_installments_months
  formula_id        FK formula        optional until payroll formulas exist (Formula* in the requirements)
  deduction_pay_item_id FK pay_item {NULL}  required unless non_payable
  description
  UNIQUE (company_id, name)

loan_type_employment_type             Employment Contract Type*: the contract types that may apply
  loan_type_id FK loan_type, employment_type_id FK employment_type              *──*

loan_category
  id PK, company_id FK company, name, is_active, description
  UNIQUE (company_id, name)

loan                                  created when a loan request is finally approved
  id                PK
  company_id        FK company
  employee_id       FK employee
  request_id        FK request
  loan_type_id      FK loan_type {NN}
  loan_category_id  FK loan_category
  principal         {NN}
  installment_amount
  installments
  gap_between_installments_months
  currency          {CHAR(3)}
  payment_method                      bank, cash, pay_order, cheque
  start_month                         first installment month (from the repayment date)
  status                              active, settled, non_payable, written_off
  settled_at
  UNIQUE (request_id)

loan_installment                      the Repayment tab; payroll marks rows paid
  id PK, loan_id FK loan, installment_no {INT} {NN}, due_month {NN}, amount {NN}, paid_amount, payslip_id FK payslip, paid_at, status
  UNIQUE (loan_id, installment_no)
```

```
request(loan) 1──1 loan 1──* loan_installment *──1 payslip
loan_type *──* employment_type
```
