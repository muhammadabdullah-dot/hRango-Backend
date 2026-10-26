## 16. Warnings [att]

```
warning_policy                        Warning -> Policy
  id                PK
  company_id        FK company
  title
  applies_to {NN}                     late_arrival, early_departure, overtime, half_day_leave
  period {NN}                         day, week, month, year
  grace_minutes {INT}                 Total Grace Minutes in a period before days count
  week_start_day, week_end_day        mon ... sun; week periods only
  is_active
  UNIQUE (company_id, title)

warning_policy_rule                   one per clock event
  id PK, warning_policy_id FK warning_policy, clock_event {NN}, minutes {NN}, occurrence_count {NN}
  UNIQUE (warning_policy_id, clock_event)

penalty_rule                          Warning -> Penalty: what the n-th warning in a period costs
  id                PK
  warning_policy_id FK warning_policy
  after_count {NN}
  period {NN}                         week, month, year
  penalty_type {NN}                   half_day, full_day, percentage
  percentage {NN}                     share of a day: 50, 100 or the given percentage
  deduction {NVARCHAR(30)} {NN}       payroll, leave, both
  leave_type_id     FK leave_type     the balance a leave deduction is taken from
  UNIQUE (warning_policy_id, period, after_count)

warning                               a warning actually raised (att.usp_warning_raise)
  id                PK
  company_id        FK company
  employee_id       FK employee
  warning_policy_id {NN}  FK warning_policy
  warning_policy_rule_id {NN}  FK warning_policy_rule
  timesheet_day_id {NN}  FK timesheet_day
  work_date {NN}
  minutes                             minutes measured that day
  occurrence_no {INT}                 n-th occurrence in the policy period
  penalty_rule_id   FK penalty_rule
  penalty_type, penalty_percentage
  deduction {NVARCHAR(30)}            payroll, leave, both
  payslip_id        FK payslip        where the penalty was deducted
  UNIQUE (warning_policy_rule_id, timesheet_day_id)
```

```
warning_policy 1──* warning_policy_rule / penalty_rule / warning
timesheet_day 1──* warning
warning 1──0..1 leave_ledger   (leave deductions)
```
