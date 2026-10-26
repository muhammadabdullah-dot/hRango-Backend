# 09 Manpower planning and Benefits

Compared on 2026-10-23: frontend (`frontend/src/features/manpower-planning`, `features/benefits`, routes
`src/routes/_app/manpower-planning/**`, `benefits/**`, frontend README "Manpower Planning", "Benefits" and their
"departures" sections), documents, and the ERD. Documents used: `erd/source/12-mp.md` (corrected 2026-10-19 from
Figma "HRango Dashboard App Version", page App UI, Manpower Planning frames), the same file's "Benefits" section
(3054:4092) and its Health Benefits and Perks frames as summarised in the 2026-10-19 layer read. `requirements/`,
"HRango - Overview.pdf", "HRango - Mini SRS.pdf" and the Functional Requirements PDF say nothing about manpower
planning, e-budgets or benefit plan years: the Mini SRS / FRD "Benefits" are payroll benefit pay items (Payroll
module), and the profile's Benefits tab is a payroll view. The frontend's mock data and payloads were not used.

## Screens

| Screen | Frontend route | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Planning list (plan year filter, title / mode / status filters, Details, Approvals, delete) | `/manpower-planning/planning` | 12-mp `manpower_plan` ("Approvals" column, "Current Planning") | mp.manpower_plan, e_budget | Build. Approvals column = the plan's budgets and their decisions; mode derived from the lines |
| Add / edit Planning (header, Plan for New Positions, Plan for Existing Positions, Submit) | `/planning/new`, `/planning/$planId/edit` | 12-mp `manpower_plan`, `manpower_plan_line` | manpower_plan, manpower_plan_line | Build with changes: one call saves header and lines (JSON), prices the lines and submits (makes budgets) |
| Plan Details (read-only) | `/planning/$planId` | not drawn | same | Build (GET plan: header, lines, budgets) |
| Import Positions / Import Existing Employees / Export / Refresh on Add Planning | buttons | Figma buttons only | - | Frontend: it fills lines from GET positions / the employees module; export stays in the frontend |
| E-Budgeting (budgets, add, edit, delete) | `/manpower-planning/e-budgeting` | 12-mp `e_budget` | e_budget | Build |
| Budget Approvals | `/manpower-planning/budget-approvals` | 12-mp `e_budget.request_id` "Budget Approvals screen" | e_budget | Build with changes: status-based approve / reject in mp (see decisions) |
| Open Positions (JD download, Edit, Close / Reopen) | `/manpower-planning/open-positions` | 12-mp `open_position` ("JD's" download) | open_position | Build; JD is a core.stored_file reference |
| E-Budget Settings: Budget Duration (IsCurrent) | `/e-budget-settings?tab=budget-duration` | 12-mp `budget_duration` | budget_duration | Build; one current per company |
| E-Budget Settings: Position Title | `?tab=position-title` | Figma Position Title list; org.job_title | org.job_title (read) | Build read-only list with usage counts; add / edit / delete stay on Organisation's Job titles |
| E-Budget Settings: Employee Position (form, Upload Excel, salary range) | `?tab=employee-position` | 12-mp `position`, `position_salary_range` | position, position_salary_range | Build; import takes rows already read from the sheet (JSON) |
| Benefits page frame and stats row | every `/benefits/*` tab | Figma Benefits (3054:4092) | counts | Build `GET /benefits/summary` |
| Plan Years list / New / Edit (Details, Plans, New Hires) / Delete | `/benefits/plan-years`, `/plan-years/new` | Figma Benefits | ben.plan_year, plan_year_plan | Build |
| New Open Enrollment Window (step 1 and 2), Qualifying Life Event, New Hire | row menu | Figma Benefits | enrollment_window, _plan, _employee | Build; kind open_enrollment / life_event / new_hire |
| Plans list, Add {Category} Plan, copy, delete | `/benefits/plans`, `/plans/new?category=` | Figma Benefits (Plan Details only) | benefit_plan | Build Plan Details; Coverage Options, Eligibility & Cost, Enrollment Details, Payroll deduction not built (not drawn) |
| Enrollment Windows, Employees, Files tabs, Update Information | `/benefits/enrollment-windows`, `/employees`, `/files` | not drawn | enrollment_window, election, core.attachment | Build windows, employees (elections + missing details), files; Update Information belongs to Employees (hr) |
| Employee elections (elect / waive / approve) | implied by "Employee Elections" counts | Figma: pending / approved counts | election, election_plan | Build (needed for the counts the design shows) |
| Health Benefits (insurer, coverage, life cover, annual payment, availed / not availed) | none | Figma App UI Health Benefits frames | ben.health_benefit | Build (backend ahead of frontend); fields from the 2026-10-19 layer-read summary |
| Perks (Eid ul Adha, Eid ul Fitr, Birthday, Ramadan, New Year gifts) | none | Figma App UI Perks frames | ben.perk | Build (backend ahead of frontend); occasions are a fixed list, no seed |

## Gaps

Frontend has, documents do not define: Plan Details page, Approvals dialog, budget edit / delete rules, Activate /
Deactivate on titles and positions, the Enrollment Windows / Employees / Files tabs, Update Information, plan copy.
Built where they contradict nothing (positions status, copy, the three tabs); the rules chosen are below.

Documents have, frontend does not: Health Benefits and Perks screens (built in the backend); position reports-to /
employee holding a seat (built); salary band history (built as `position_salary_range` with an effective date).

## ERD changes

`12-mp.md`
- `position_salary_range`: re-keyed from `job_title_id` to `position_id` with `effective_date`. The Employee
  Position form carries the Min / Max Salary (the design draws them on that popup), so a band belongs to a
  position; the history allows a band to change per budget year.
- `position.job_title_id` made required (the list and filters need it; the frontend added it to the popup).
- `manpower_plan`: dropped `planning_mode` (a plan holds both kinds of lines; the list's mode filter is derived),
  `is_current` (it is the duration's `is_current`), `request_id`; added `submitted_at`; status `pending, approved,
  rejected` (the design's Submit sends it at once; there is no "new" draft state).
- `manpower_plan_line`: added `sort_order`, `e_budget_id` (the budget the line is counted in), `months`; amounts
  made required.
- `e_budget`: added `manpower_plan_id` (optional, blank for a budget added by hand), `job_title_id`,
  `total_positions`, `decided_by_user_id`, `decided_at`, `remarks`; dropped `request_id`.
- `open_position`: added `company_id` (was missing), `e_budget_id`, `position_id`, `branch_id`, `title`.
- `budget_duration`: `UNIQUE (company_id, name)`, dates required.

`17-ben.md` (new): plan_year, benefit_plan, plan_year_plan, enrollment_window, enrollment_window_plan,
enrollment_window_employee, election, election_plan, health_benefit, perk. Plan attachments use
`core.attachment` (entity_type `ben.benefit_plan`), so no table for files.

## Decisions on unclear points

- **Approval: status-based inside mp, not the requests engine.** The ERD linked `manpower_plan.request_id` and
  `e_budget.request_id` to `req.request`, but `req.request.employee_id` is required ("who it is for") and a budget is
  for a department, not a person; the design gives budgets their own Budget Approvals screen with approve / reject.
  So `manpower.budget_approvals.approve / reject` decide a pending budget (`mp.usp_e_budget_decide`), with the
  decider and time on the row. No `usp_request_apply_*` effect is written; `req.request_type` `manpower_budget` is
  unused by this module for now. Elections are approved the same way (`benefits.elections.approve / reject`).
- **Submitting a plan makes its budgets**: one pending budget per position title and department of its lines
  (new-position lines by the position's title and department; existing-employee lines by the employee's job title
  and department, "Existing positions" when the employee has no job title). The plan's status follows its budgets:
  any rejected -> rejected, all approved -> approved, else pending.
- **Line pricing** (frontend's rule; documents silent): new position a month = (max salary + allowance) x headcount;
  existing employee a month = monthly salary + allowance; annual gross = a month x calendar months from start to end,
  both counted; plan monthly / annual amount = the sums. Blank min / max take the position's band in force today;
  blank monthly salary takes the latest `hr.employee_salary`. Lines must fall inside the plan year.
- **Locks**: a plan with an approved budget cannot be edited or deleted (409 `PLAN_LOCKED`); editing a plan replaces
  its lines and (all still unapproved) budgets and resubmits it. An approved budget cannot be edited or deleted;
  editing a pending or rejected one sends it back to pending. A duration used by plans or budgets, or a position used
  by plan lines / open positions, cannot be deleted.
- **Approving a budget releases open positions**: one per new-position line of the budget (its headcount, the
  position's title, department and station, the line's end date), or one for the budget's total positions when it
  has no such lines (a budget added by hand).
- **Position titles are org.job_title**: listed by mp with usage counts; added / edited on Organisation -> Job titles.
  No is_active exists on org.job_title, so the design's Active / Inactive title status is not built (need below).
- **Position import**: the frontend (or a later Python service) reads the sheet; the API takes rows by names. Valid
  rows are added, the others reported per row and field.
- **Scope**: plans, budgets and open positions are reached through their department or station
  (`mp.fn_unit_reach`): company scope sees all; department scope its department and sub-departments; branch scope
  its station; selected_units the ticked branches / departments; own and team reach none. Elections, health benefits
  and perks use `auth.fn_visible_employees` with the endpoint's code.
- **Benefits company-wide records** (plan years, plans, windows, plan files) change only with the permission held
  with company scope, because the Employee role's `*.create` pattern grants `benefits.plan_years.create` with own scope.
- **Elections**: one per employee and plan year; plans must be offered in the window (or the plan year); the window
  must be open and list the employee (none listed = everyone). Without a window the employee's open window is taken;
  with none, only a company-scope user (HR) may record it. `waive` records Waived with no plans; `submit = false`
  keeps it Incomplete. Status: incomplete, pending, approved, rejected, waived.
- **Employees tab "missing information"**: date of birth and marital status from `hr.employee`. The design's Home
  Address has no column in `hr.employee`; Update Information belongs to the Employees module.
- **Plan year delete** removes its windows and elections, refused while an approved election stands. A plan
  nobody elected can be deleted (its links and file links go with it).
- **No reference data seeded**: categories, kinds, occasions and statuses are fixed lists checked in the procedures.
- **Error codes**: deleting a budget duration that plans or budgets use is 409 `DURATION_IN_USE`; deciding a budget
  that is no longer pending is 409 `BUDGET_ALREADY_DECIDED` (checked before the rowVersion, so a second click with
  the old rowVersion gets it too, not "someone else changed it").

## Cross-module needs

- Organisation: `is_active` on `org.job_title` (Position Title Active / Inactive in the design).
- Core / files: an upload and download endpoint for `core.stored_file`; `stored_file` has no `company_id`, so
  JD and plan files are checked only for existence.
- Employees (hr): a home address field and the Update Information edit for date of birth / marital status / address.
- Requests (req): request type `manpower_budget` is not used by mp (status-based approval); drop or keep for later.
- Default roles (`core/default_roles.py`, shared): the Recruiter role gets `manpower.budget_approvals.approve` with
  company scope through `manpower.*`; exclude `manpower.budget_approvals.*` there if recruiters should not approve
  budgets. The Employee role receives `benefits.health.create` and `benefits.perks.create` with own scope (self
  entry); exclude them there if only HR should record health benefits and perks.
- Shared ERD build: `05-att.md` `polygon_points` note `{"lat", "lng"}` is read as a type directive; my private
  baseline patches it until Attendance fixes the note.
