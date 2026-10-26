# 05 Leaves, Warning and Penalty: frontend vs documents vs ERD

Sources: `requirements/HRango - UI design/Design/05-Leaves/README.md` (D-LV), `Design/06-Warning-and-Penalty/README.md`
(D-WRN), `All Dashboards/06-Attendance-and-Leave/README.md` (AD), "Functional Requirements for HRango.pdf" (FRD, page
numbers of the PDF), `HRango - Functional Requirements Document/01-Requests/README.md` (FRD-R),
"HRango - Mini SRS.pdf" (SRS), "HRango - Open Questions.pdf" (OQ). Frontend: `frontend/src/features/leaves`,
`features/warning`, routes `_app/leaves/*`, `_app/warning/*`, frontend README "Leaves", "Leaves: departures from the
design", "How the reference feature is wired", "The rest of the Warning module", "Leave Encashment" (under Payroll).

## Screens

| Screen / feature | Frontend (route) | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Leave Types (Settings) | `/leaves/settings/leave-types` (+ `?dialog=add`) | D-LV "Leave Types"; FRD pp. 56-59 "Leave Settings", "Pre-Condition Settings"; FRD-R "Leave Types"; SRS LEV-1..3 (p. 6-7) | lv.leave_type, leave_type_experience_slab, leave_type_short_slab | **Build.** CRUD `/api/leaves/types`; every switch, dependent field, pre-condition, balance setting and both slab tables |
| Leave Policies (Settings) | `/leaves/settings/policies` | D-LV "Leave Policies" (not in FRD); SRS LEV-4 | lv.leave_policy, leave_policy_type, leave_policy_employee | **Build with changes.** CRUD `/api/leaves/policies`; a distribution policy lists its leave types with an allowance each (ERD), so "No. of Leaves" is computed. The frontend's separate "Leave Policy (in force)" switch is dropped: Status (`isActive`) is enough |
| Enroll Employee | button on the policy list (no frame) | D-LV "action Enroll Employee"; SRS LEV-4 | lv.leave_policy_employee | **Build.** `GET/POST /api/leaves/policies/{id}/employees`, `DELETE .../employees/{employeeId}`; employee-level policies only |
| General Settings | `/leaves/settings/general` | D-LV "General Settings" (three labels, no meaning given) | core.company_setting (module `leave`) | **Build with changes.** `GET/PUT /api/leaves/settings`, values as the frontend defined them (documents silent). Stored only; see "Decisions" |
| My Leaves | `/leaves/my-leaves` | D-LV "My Leaves and Leave Applications" ("older version of the Leave request screens"); FRD pp. 48-51 "Leave Request" | req.request + req.req_leave (requests module) | **Build (read).** `GET /api/leaves/applications?tab=my` |
| Leave Applications | `/leaves/applications` | D-LV; AD "Attendance - Leave Application" (approver cards); FRD pp. 52-55 "Leave Approvals", "Leave Delegates" | same | **Build (read).** `?tab=subordinates` / `?tab=all`, filters of FRD p. 49-50, status counts `GET /api/leaves/applications/counts`, detail with the balance `GET /api/leaves/applications/{id}` |
| + Apply Leave, Approve / Reject / Forward, Cancel | dialogs on My Leaves / Leave Applications | FRD pp. 48-55; FRD-R "Leave" | req.* | **Not here: the requests API** (`POST /api/requests/...`, comparison/04-requests.md). The Leaves buttons call that API; this module gives it `lv.fn_leave_balance`, `lv.usp_leave_request_check`, `lv.usp_request_apply_leave`, `lv.usp_request_revert_leave` |
| Leave balance card (Total, Availed, Available, Pending) | Apply dialog, application rows | FRD p. 51 "Leave Balance Display"; SRS LEV-5; AD ring "5/8 Leaves Allowed" | lv.leave_ledger | **Build.** `lv.fn_leave_balance`; `GET /api/leaves/balances` (per employee and type, scoped) |
| Leave ledger, opening balance, adjustment | none | SRS LEV-5 ("balances"); FRD-R "Not defined: when leave balance is deducted and restored" | lv.leave_ledger | **Build (no frontend screen yet).** `GET/POST /api/leaves/ledger` |
| Allotment, earned accrual | none (mock computes balances on the fly) | FRD p. 56 "Auto Allotment", "Auto Balance on Joining Month", "Earned Balance", "Prorated" | lv.leave_ledger | **Build.** `POST /api/leaves/allotment/process` (idempotent; run yearly / monthly) |
| Carry forward | none (switch stored only in the mock) | FRD p. 57 "Carry Forward ... for the next year"; "Accumulative Count" p. 58 | lv.leave_ledger | **Build.** `POST /api/leaves/carry-forward/process` |
| Leave Encashment | Leaves sub-menu link → Payroll → Leave Encashment | D-LV "Leave Encashment"; FRD pp. 155-156 "Leave Encashment", "Create"; SRS PAY-11 | lv.leave_encashment, leave_encashment_employee | **Build.** `/api/leaves/encashments` (list, detail, create = "process", edit, delete). Payroll reads the lines (see cross-module) |
| Payroll → Leave Configuration (CPL type, max earned CPL, deductions, calendar/fiscal year) | Payroll settings | FRD p. 101 | payroll settings | **Not here** (payroll). The leave year here follows `org.company.fiscal_year_start_month` |
| Leave dashboard cards, mobile Team Leave | dashboards | AD | — | **Not in this build** (dashboards module reads `/api/leaves/applications` and balances) |
| Warning Policy (overview list) | `/warning` | D-WRN "Warning Policy"; SRS WRN-1 (p. 8) | att.warning_policy, warning_policy_rule | **Build.** `GET /api/warning/policies` |
| Policy form (rule builder Day/Week/Month/Year, Over Time, Half Day Leave) | `/warning/policy`, `/warning/policy/$policyId` | D-WRN "Warning Section"; SRS WRN-1 | same | **Build with changes.** `POST/PUT/DELETE /api/warning/policies[/{id}]`: one period per policy, one rule per clock event (minutes, every n-th occurrence), total grace minutes, week start/end day. The frontend's repeated period blocks with dates and a clock-in time are not kept (see "Decisions") |
| Penalty form and list | `/warning/penalty`, overview | D-WRN "Penalty" (Late Arrival, Full Day, Percentage, Both, Year); SRS WRN-2; OQ C12 (p. 3) | att.penalty_rule | **Build with changes.** `PUT /api/warning/policies/{id}/penalties`, `GET /api/warning/penalties`. A penalty belongs to a warning policy (ERD); badge colour, points scale, weekday chips and time windows of the frontend are dropped |
| History panel | dialog on the overview | D-WRN "History panel ... Delete All" | core.audit_log | **Build (read).** `GET /api/warning/history`. "Delete" / "Delete All" not built: the audit log is not deletable |
| Column Preferences | side panel | D-WRN "Column Preferences" | — | Frontend only |
| Warnings raised (time-sheet Warnings / Penalty columns) | none (time sheet columns in Attendance) | D-WRN "results of these rules are meant to appear there"; SRS ATT-9, WRN-2 | att.warning | **Build.** `POST /api/warning/warnings/process` (from att.timesheet_day), `GET /api/warning/warnings` |

Endpoint count: Leaves 28, Warning 10.

## Gaps

Documents have, frontend lacks:
- Leave ledger, opening balances, adjustments, allotment run, carry-forward run (FRD switches imply them; no screen).
- Leave Delegates screen and bulk approve (FRD pp. 53-54): requests module.
- Warnings raised list per employee (only the time-sheet columns are designed).

Frontend has, documents lack:
- General settings value lists (finalApprovalBy, approveOnStatus, postDeadline as a switch): kept as the frontend defined them.
- "Leave Policy" in-force switch on policies: dropped.
- Policy name "grace-minutes" as its own warning kind: dropped (grace minutes are a field of every policy).
- Warning penalty "badge colour", "points" with a number/percentage scale, weekday chips and From-To windows: dropped.
- History "Delete" / "Delete All": not built.
- Leave type "Short Leave Slab Type" as Hours/Minutes: the documents say Percentage/Flat; documents win (`valueType`).

## ERD changes (erd/source/06-lv.md, 16-warning.md)

- `leave_type`: `gender`, `marital_status` NOT NULL with `any`; `tenure` is a code (`yearly`, `monthly`, `employment`), not an INT; `is_accumulative` became `accumulative_count INT` (the design draws a number box); `attachment_rule` codes `refuse`/`note`; `UNIQUE (company_id, title)`.
- Slabs: NOT NULL on the required fields (FRD marks them *); `slab_value DECIMAL(9,2)`.
- `leave_policy`: + `policy_kind` (`distribution`, `half_short`: the design's "Policy *" select with "Leave Distribution Policy" and "Half leave & Short leave"), + `allow_half_day`, `allow_short_leave`, `is_active`; `UNIQUE (company_id, title)`.
- `leave_ledger`: `leave_type_id`, `entry_date` NOT NULL; + `remarks`; + `leave_encashment_id`, `warning_id` (what posted the row, so deleting an encashment or re-raising warnings removes exactly its postings); reasons now opening, allotment, earned, carry_forward, adjustment, overtime, availed, encashed, penalty, restored.
- `leave_encashment`: + `encashment_date`, `applies_to_all` (FRD "All Employees"); `basis` codes overtime, earned_salary, per_hour_rate, overnight; `mode` payroll/manual. `leave_encashment_employee`: `UNIQUE (leave_encashment_id, employee_id)`.
- `warning_policy`: `applies_to` + `early_departure`; + `is_active`; `grace_minutes` is the period's total grace; `UNIQUE (company_id, title)`.
- `warning_policy_rule`: `UNIQUE (warning_policy_id, clock_event)`.
- `penalty_rule`: + `period` (week, month, year: "Year" in the Penalty frame), + `deduction` (payroll, leave, both: "Both" in the frame, OQ C12), + `leave_type_id`; `penalty_type` half_day, full_day, percentage; `UNIQUE (warning_policy_id, period, after_count)`.
- `warning`: + `company_id`, `warning_policy_rule_id`, `work_date`, `minutes`, `occurrence_no`, `penalty_rule_id`, `deduction`; `UNIQUE (warning_policy_rule_id, timesheet_day_id)`.

## Decisions on unclear points

- **Leave year** = the company fiscal year (`org.company.fiscal_year_start_month`, January when empty); `fiscal_year` is the year it starts in (`lv.fn_leave_year`). Tenure `employment` balances span the whole employment.
- **Balance** (`lv.fn_leave_balance(@company_id, @employee_id, @leave_type_id, @as_of)`, inline TVF; NULL type = every type): entitled = credits (opening, allotment, earned, carry_forward, adjustment, overtime), used = availed + encashed + penalty − restored, pending = leave requests with status `pending` starting in the leave year, available = entitled − used − pending.
- **Deductible** (undefined in FRD): deductible types are checked against the balance; non-deductible ones are posted as availed without the check (follows the frontend).
- **Coverage**: an employee's leave types come from their distribution policy (employee-level enrolment outranks the company-level one). One active company-level policy per kind; a person in at most one active employee-level policy per kind. With no active distribution policy at all, every leave type applies to everyone.
- **Allotment**: active types with Auto Allotment (or the one named), matching gender, marital status and probation (Probation Leave Type or Can Apply in Probation lets probationers have it). Amount: allowance (×12 for monthly tenure) or the experience slab for months served at the year start; Pro Rated joiners get the months left (joining month counts with Auto Balance on Joining Month), rounded to half days. Earned Balance types accrue a twelfth per completed month up to `asOf`. Runs are idempotent.
- **Carry forward**: available days at year end move to the next year (a debit and a credit, both `carry_forward`); with Accumulative Count n the carried days are capped at (n − 1) × yearly allowance. Pending requests of the old year are held back.
- **Encashment**: days = available in the year, skipped below Encashment Min, capped at Max; amount = days × amount per leave (entered; the basis is recorded, not computed: the salary-based sums are payroll's). Editing changes date, basis, amount, mode; type/year/people need delete and re-create. Paid lines (payslip_id set) lock the encashment.
- **Request rules** (`lv.usp_leave_request_check`): active type, coverage, gender, marital status, probation, minimum experience, back date and its limit, future limit, attachment when the rule is `refuse`, half/short: the type must allow short leave, then a `half_day` needs the employee's Half leave & Short leave policy's `allow_half_day` (HALF_DAY_NOT_ALLOWED) and a `quarter_day` its `allow_short_leave` (SHORT_LEAVE_NOT_ALLOWED), each on its own (`lv.fn_leave_half_short` picks the policy: employee level first, then company; none = the type decides; the check takes `@short_leave_type`), maximum applications in the employment, gap between applications, and the balance. Sandwich and composite rules (days counting over weekends/holidays) are the requests module's day count (needs the roster).
- **General settings** are stored and returned; they do not change behaviour in this build (final approver belongs to approval flows, `approve_on_status = pending` is not applied to balances).
- **Warning semantics**: measured minutes per day — late_arrival: late_minutes (clock_in); early_departure: early_left_minutes (clock_out); overtime: overtime_before (clock_in) / overtime_after (clock_out); half_day_leave: day_status `half_day`. A day is an occurrence when its minutes exceed the rule's minutes and the period's running total exceeds the policy's grace minutes; every `occurrence_count`-th occurrence raises a warning. Periods day/week/month/year; weeks start on the policy's start day, days outside start..end are ignored, and weeks are cut at the calendar-year boundary. Penalty: the n-th warning of a policy in the rule's period gets the rule whose `after_count` = n (beyond the top rung, the top rung); half day = 50 %, full day = 100 %. Leave and both deductions post `penalty` (percentage / 100 days) to the leave ledger; payroll reads payroll and both.
- **Raising** recomputes the whole calendar years touched; warnings already in a payslip are kept. Policies with warnings cannot be deleted (make inactive); a rule with warnings cannot be removed.
- **Permissions**: `leaves.applications` (view, export), `leaves.balances` (view, edit = adjust), `leaves.allotment` (process), `leaves.encashments` (view, process = create, edit, delete, export), `leaves.settings.general|types|policies` (+ enroll); `warning.warnings` (view, process, export), `warning.settings.policies|penalties|history`. Adjusting and encashing avoid `create` so the Employee role's own-scope create never reaches them.

## Cross-module needs

- **Requests** (comparison/04-requests.md): the Leaves "+ Apply Leave", approve, reject, forward and cancel buttons use the requests API. The engine should call `lv.usp_leave_request_check @company_id, @employee_id, @leave_type_id, @from_date, @to_date, @days, @is_short, @has_attachment, @request_id` before saving a leave request (or at least read `lv.fn_leave_balance`), `lv.usp_request_apply_leave` on final approval and `lv.usp_request_revert_leave` when an approved leave is cancelled. `req_leave.days` (or `request.days`) must hold the counted days (half day 0.5). Statuses read: pending, approved, rejected, cancelling, cancelled; `request_type.code = 'leave'`.
- **Attendance**: `att.timesheet_day` columns read: employee_id, work_date, late_minutes, early_left_minutes, overtime_before_minutes, overtime_after_minutes, day_status (`half_day`), processed_at. The time sheet's Warnings / Penalty columns should read `att.warning` by `timesheet_day_id`. Attendance processing may call `att.usp_warning_raise` after a run. Overtime policy slabs that convert minutes to leave should post `lv.leave_ledger` reason `overtime`.
- **Payroll**: reads `lv.leave_encashment_employee` (mode `payroll`, `payslip_id` NULL) and sets `payslip_id`; reads `att.warning` (deduction payroll/both, `payslip_id` NULL) and sets `payslip_id`; unpaid leave from `lv.leave_ledger` (`availed` of non-deductible types) if payroll treats them as unpaid. Payroll's "Leave Configuration" fiscal year should agree with `org.company.fiscal_year_start_month`.
- **Frontend**: Leave Encashment screen under Payroll calls `/api/leaves/encashments`; warning screens move from `/warning-policies`, `/warning-penalties`, `/warning-history` to `/api/warning/...`.
