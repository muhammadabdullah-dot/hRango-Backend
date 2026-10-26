## 7. Requests and approvals [req]

```
request_type                          the fixed list of request types (reference data, every company); see comparison/04-requests.md
  id                PK
  code                                leave, punch, relaxation, official_visit, work_from_home, overtime, rest_day, shift_swap, promotion, transfer, resignation, loan, travel, expense, air_ticket, requisition, task_extension
  name
  kind                                detail table req_<kind> and effect <schema>.usp_request_apply_<kind>
  prefix                              request code prefix: RQ-<prefix>-0001
  is_admin_only                       filed by HR for an employee, never for oneself (promotion, transfer)
  is_active
  sort_order
  UNIQUE (code)

request                               shared header for every request
  id                PK
  company_id        FK company
  code                                RQ-LV-0001
  request_type_id   FK request_type
  employee_id       FK employee       who it is for
  created_by_user_id FK user_account  may be HR on their behalf
  from_date, to_date
  days              {DECIMAL(6,2)}    the Count column: days (leave, WFH, rest days) or 1
  reason
  description
  application       {NVARCHAR(MAX)}   the application text (written by hand or generated)
  status                              pending, approved, rejected, cancelling, cancelled
  approval_flow_id  FK approval_flow  the flow (version) the request is walking now; cancellation flow while cancelling
  current_node_id   FK approval_node
  submitted_at, decided_at
  cancel_reason
  cancel_requested_at
  is_deleted                          deleted by the requester before anyone acted (kept for audit)

request_day                           each day a multi-day request covers (leave, work from home, rest days)
  id PK, request_id FK request, request_date {NN}, schedule_id FK schedule
  UNIQUE (request_id, request_date)

req_leave          request_id PK/FK request, leave_type_id FK leave_type, is_short, short_leave_type, start_time, end_time, days
req_punch          request_id PK/FK request, punch_date {NN}, punch_type {NN}, punch_time {NN}
req_time_window    request_id PK/FK request, kind, window_date {NN}, start_time {NN}, end_time {NN}, time_slot_id FK time_slot {NULL}, duration_minutes
req_rest_day       request_id PK/FK request, department_id FK department, roster_group_id FK roster_group {NN}, is_payable
req_overtime       request_id PK/FK request, department_id FK department, location_id FK location {NULL}, branch_id FK branch {NULL}, overtime_date {NN}, start_time {NN}, end_time {NN}, applied_minutes {NN}, approved_minutes
req_loan           request_id PK/FK request, loan_type_id FK loan_type, loan_category_id FK loan_category {NULL}, amount_requested {NN}, required_date {NN}, extension_no, approved_amount, currency {CHAR(3)}, payment_method, repayment_date
req_travel         request_id PK/FK request, purpose {NN}, extension_no, alt_phone, advance_required
req_promotion      request_id PK/FK request, is_demotion, grade_id FK grade, job_level_id FK job_level {NULL}, designation_id FK designation {NN}, job_title_id FK job_title {NN}, previous_salary, new_salary {NN}, effective_date {NN}
req_transfer       request_id PK/FK request, location_id FK location, branch_id FK branch {NN}, department_id FK department {NN}, line_manager_id FK employee {NN}, final_authority_id FK employee {NN}, effective_date {NN}
req_resignation    request_id PK/FK request, resignation_type {NN}, resignation_date {NN}, last_working_date, notice_period_days, serve_notice
req_shift_swap     request_id PK/FK request, shift_date {NN}, from_schedule_id FK schedule {NULL}, time_slot_id FK time_slot {NULL}, with_employee_id FK employee {NULL}, to_schedule_id FK schedule {NULL}

loan_guarantor     id PK, request_id FK request, name {NN}, cnic {NN}, known_since {NN}, relationship {NN}, extension_no, description, file_id FK stored_file
travel_advance     id PK, request_id FK request, amount {NN}, currency {CHAR(3)} {NN}
travel_leg         id PK, request_id FK request, travel_type {NN}, from_place {NN}, to_place {NN}, travel_mode {NN}, distance_km, depart_at {NN}, arrive_at {NN}, stay_required
travel_stay        id PK, request_id FK request, stay_type {NN}, address {NN}, city {NN}, from_date {NN}, to_date {NN}, nights {NN}, phone {NN}, email {NN}
travel_ticket      id PK, request_id FK request, ticket_no {NN}, travel_class, from_place, to_place, travel_at {NN}, file_id FK stored_file, description
req_promotion_benefit  request_id FK request, pay_item_id FK pay_item     benefits ticked on a promotion (many to many)

req_expense        request_id PK/FK request, currency {CHAR(3)}, total_amount {NN}, approved_amount     one expense request = the claims prepared together ("Generate Claim", "Submit All")
expense_line                          one claim of an expense request, each with its own receipt
  id                PK
  request_id        FK request
  line_no           {INT} {NN}
  title             {NVARCHAR(200)}   Expense Claim Title*
  claim_date        {NN}              Expense Claim Date (today when empty)
  expense_category_id FK expense_category {NN}
  amount            {NN}
  approved_amount                     the approver may lower it (0 = not reimbursed); the amount when left empty
  description       {NN}
  file_id           FK stored_file {NULL}   the receipt
  opening_balance_id FK opening_balance {NULL}   what payroll pays it through, set on final approval
  UNIQUE (request_id, line_no)
req_air_ticket                        an air ticket the employee paid and claims back
  request_id        PK/FK request
  title
  claim_date        {NN}
  travel_date       {NN}
  from_place, to_place
  amount            {NN}
  approved_amount
  currency          {CHAR(3)}
  description
  file_id           FK stored_file {NULL}   the ticket
  opening_balance_id FK opening_balance {NULL}
req_requisition                       items, assets or stationery wanted; approval only, then fulfilled by the admin side
  request_id        PK/FK request
  title
  requisition_type  {NN}              stationery, it_equipment, furniture, asset, consumable, service, other
  needed_by_date    {NN}
  delivery_location
  estimated_amount                    the lines' quantity x estimated unit cost
  currency          {CHAR(3)}
requisition_line
  id PK, request_id FK request, line_no {INT} {NN}, item_name {NN}, quantity {DECIMAL(18,2)} {NN}, unit, estimated_unit_cost, description
  UNIQUE (request_id, line_no)

expense_category                      Request Settings -> Expense Categories (Travel Fee, Tech & Soft, Venue Rental ...)
  id                PK
  company_id        FK company
  name
  pay_item_id       FK pay_item {NULL}   the reimbursement pay item claims of this category are paid under; empty: the default below
  max_amount                          per claim; empty: no limit
  receipt_required  {BIT}
  is_active
  description
  UNIQUE (company_id, name)

reimbursement_setting                 Request Settings -> Reimbursement: how approved claims reach payroll (one row per company)
  id PK, company_id FK company, expense_pay_item_id FK pay_item {NULL}, air_ticket_pay_item_id FK pay_item {NULL}
  UNIQUE (company_id)

approval_flow                         one version of a flow; editing saves a new version so requests on the way keep theirs
  id                PK
  company_id        FK company
  request_type_id   FK request_type
  purpose                             request, cancellation
  name
  scope_type                          company, branch, department, employee (the most specific active flow wins)
  scope_id                            the branch, department or employee; empty for company
  description
  is_active
  is_current                          0 once a newer version replaced it or it was deleted

approval_node
  id                PK
  approval_flow_id  FK approval_flow
  step_no           {NN}              the node number shown in the editor; Next / If True / If False point at these
  approver_kind                       employee, line_manager, hod, branch_manager, final_authority, role, or an authority (team_lead, hr_manager, finance_manager ...)
  approver_employee_id FK employee    when approver_kind = employee
  role_id           FK role           when approver_kind = role: anyone holding the role decides
  is_condition
  expression                          as typed: days > 3, amount >= 100000, department_id = 12
  condition_field                     parsed from expression: days, amount, minutes, department_id, branch_id, location_id, grade_id, designation_id, employment_type_id
  condition_operator {NVARCHAR(2)}    =, <>, >, >=, <, <=
  condition_value   {DECIMAL(18,4)}
  next_node_id      FK approval_node  empty: the next node by number
  true_node_id      FK approval_node
  false_node_id     FK approval_node
  can_edit                            the approver may change the request's details
  can_disagree                        a consent step: agree or disagree, the flow goes on either way
  is_observer                         "On Looker": informed only, does not decide
  UNIQUE (approval_flow_id, step_no)

approval_authority                    who holds an authority (HR Manager, Finance Manager ...): the Request Flow screen of the requirements
  id                PK
  company_id        FK company
  authority         {NVARCHAR(30)}    team_lead, hr_manager, operations_manager, finance_manager, director, compliance_officer, project_manager, admin_supervisor, it_administrator, area_manager, admin_manager
  employee_id       FK employee
  request_type_id   FK request_type   empty: every request type
  branch_id         FK branch         empty: every branch
  department_id     FK department     empty: every department
  description
  is_active

delegation
  id PK, company_id FK company, delegator_id FK employee, delegatee_id FK employee {NN}, request_type_id FK request_type {NN}, description, is_active

request_restriction                   block a request type for a company between two dates
  id PK, company_id FK company, request_type_id FK request_type, start_date {NN}, end_date {NN}, description

request_step                          one row per event and approver action; the Flow and History popups
  id                PK
  request_id        FK request
  approval_node_id  FK approval_node  empty for the submit, cancel and colleague-consent rows
  purpose                             request, cancellation
  approver_kind                       copied from the node (or colleague, requester)
  approver_id       FK employee       who should act
  approver_role_id  FK role           when any holder of a role may act
  acted_by_id       FK employee       who did act (delegate if different)
  is_delegate
  is_consent                          a consent step (Can Disagree node, or the colleague of a shift swap)
  action_taken      {NN}              submitted, pending, approved, rejected, consented, disagreed, forwarded, skipped, informed, cancel_requested, withdrawn, cancelled
  remarks
  acted_at
```

```
request_type 1──* request 1──1 req_<kind>
request 1──* request_day / request_step / loan_guarantor / travel_* / expense_line / requisition_line
expense_category 1──* expense_line
expense_line / req_air_ticket ──> opening_balance   (payroll pays the approved claim)
request_type 1──* approval_flow 1──* approval_node
approval_node ──> approval_node   (next / true / false)
employee 1──* delegation (as delegator and as delegatee)
employee 1──* approval_authority
```
