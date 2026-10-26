## 17. Benefits [ben]

Source: Figma "HRango Dashboard App Version", page App UI: the "Benefits" section (3054:4092: plan years,
plans, enrollment windows) and the Health Benefits and Perks frames. Added 2026-10-23
(comparison/09-manpower-benefits.md). Plan attachments use core.attachment (entity_type ben.benefit_plan).

```
plan_year                             "Benefit Plan Years"
  id                PK
  company_id        FK company
  name
  start_date        {NN}
  end_date          {NN}
  new_hire_start    {NVARCHAR(30)} {NN}   immediately, waiting_period, per_employee
  waiting_period_days                 when new_hire_start = waiting_period
  election_period   {INT} {NN}        "How long do new employees have to complete elections?"
  election_unit     {NVARCHAR(10)} {NN}   day, week, month
  UNIQUE (company_id, name)

benefit_plan                          "Benefit Plans" (Add {Category} Plan)
  id                PK
  company_id        FK company
  category          {NN}              medical, dental, vision, retirement, hsa, life, others
  name
  plan_type         {NVARCHAR(100)}   EPO, HMO, PPO ... per category
  plan_type_ref     {NVARCHAR(50)}    "Plan Type ID"
  carrier
  start_date        {NN}
  end_date          {NN}
  description
  status                              active, inactive
  UNIQUE (company_id, name)

plan_year_plan     plan_year_id FK plan_year, benefit_plan_id FK benefit_plan     the plans offered in a year (many to many)

enrollment_window                     "New Open Enrollment Window" (also Qualifying Life Event, New Hire)
  id                PK
  company_id        FK company
  plan_year_id      FK plan_year
  kind                                open_enrollment, life_event, new_hire
  name
  effective_date    {NN}              inside the plan year
  closes_on         {NN}              the last day to enrol; open until then
  description

enrollment_window_plan      enrollment_window_id FK enrollment_window, benefit_plan_id FK benefit_plan
enrollment_window_employee  enrollment_window_id FK enrollment_window, employee_id FK employee             none listed = everyone

election                              an employee's elections for a plan year ("Employee Elections")
  id                PK
  company_id        FK company
  employee_id       FK employee
  plan_year_id      FK plan_year      {NN}
  enrollment_window_id FK enrollment_window
  status                              incomplete, pending, approved, rejected, waived
  submitted_at
  decided_by_user_id FK user_account
  decided_at
  remarks
  UNIQUE (employee_id, plan_year_id)

election_plan      election_id FK election, benefit_plan_id FK benefit_plan     

health_benefit                        "Health Benefits": the insurance an employee holds
  id                PK
  company_id        FK company
  employee_id       FK employee
  insurer
  policy_no         {NVARCHAR(50)}
  coverage_amount                     the cover
  life_cover_amount                   "Life Cover"
  annual_payment    {DECIMAL(18,2)}   "Annual Payment"
  start_date
  end_date
  status                              availed, not_availed
  remarks
  document_file_id  FK stored_file    the policy document or insurance card (an upload)

perk                                  "Perks": occasion gifts
  id                PK
  company_id        FK company
  employee_id       FK employee
  occasion          {NVARCHAR(30)} {NN}   eid_ul_adha, eid_ul_fitr, birthday, ramadan, new_year
  perk_date         {NN}
  description
  amount
  status                              availed, not_availed
  UNIQUE (employee_id, occasion, perk_date)
```

```
plan_year 1──* plan_year_plan *──1 benefit_plan
plan_year 1──* enrollment_window 1──* enrollment_window_plan / enrollment_window_employee
plan_year 1──* election 1──* election_plan *──1 benefit_plan
employee 1──* election / health_benefit / perk
```
