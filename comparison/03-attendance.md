# 03 Attendance: frontend vs documents vs ERD

Sources: D-03 = `requirements/HRango - UI design/Design/03-Attendance/README.md`; AD = `All Dashboards/06-Attendance-and-Leave/README.md`;
APP = `UI design/App/README.md`; SRS = `HRango - Mini SRS.pdf` (M5 ATT-1..13, WF1, NFR-5/10); OQ = `HRango - Open Questions.pdf`
(C1..C12); FRD = `Functional Requirements for HRango.pdf` (Punch Requests p. ~8, Relaxation p. ~27, Overtime p. ~31, Overtime
Settings); FE = `frontend/` (README "Attendance", "Attendance Settings and Attendance Logs"). ERD = `erd/source/05-att.md`.
All endpoints are under `/api/attendance`.

## Screens and features

| Screen / feature | Frontend (route) | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Attendance Overview (month grid per employee, counts, legend) | `/attendance/overview` | D-03 "Attendance Overview"; AD "Attendance Overview (table / calendar)" | timesheet_day, timesheet_flag | **Build** `GET /overview?month=yyyy-mm&tab=all|subordinates|my`, `/overview/export` (CSV), `/overview/summary` (count tiles). Days map date -> status. |
| My / Subordinates / All Time Sheet | `/attendance/time-sheet` (My, All tabs) | D-03 "Time sheet" (3 tabs, filters, 16 columns); SRS ATT-9 | timesheet_day, timesheet_flag, timesheet_break | **Build** `GET /time-sheet?tab=&fromDate&toDate` with employee, department, status, flag, time slot, employee status, search; `/time-sheet/export` (CSV); `/time-sheet/summary` ("Days Overview This Month" tiles). Subordinates tab added (design has it, FE does not). |
| Day view (person, times, breaks, punches) | eye button | D-03 "Edit a day", "History"; FE View / Logs popups | timesheet_day, timesheet_break, punch | **Build** `GET /days/{employeeId}/{date}` (processes an unprocessed day on first read). |
| Edit a day (times, expected, Mark Absent / Half / Short Day, breaks, comments) "Manually Updated" | green pencil | D-03 "Edit a day"; SRS ATT-10 | timesheet_day (+ marked_status), timesheet_break, core.audit_log | **Build** `PUT /days/{employeeId}/{date}` with rowVersion; field history `GET /days/{..}/history`. Own day refused. Frozen day refused (409 DAY_FROZEN). |
| Row actions Missing Punch, Relaxation, Absent-as-leave/visit/WFH, Overtime approve | orange/red/purple buttons | FRD: these are **requests** (Punch, Relaxation, Official Visit, WFH, Overtime) with approval flows | req.* (requests module) | **Not built here as direct edits.** Documents route them through requests; attendance provides the approval effects (below). HR's direct correction is the day edit. FE to call the requests module. |
| Warnings / Penalty columns | time sheet columns | D-03 columns; SRS WRN-1/2 | att.warning (warning module) | **Build (read)**: `warningCount`, `penaltyType`, `penaltyPercentage` on each day; processing calls `att.usp_warning_raise`. |
| Clock In / Clock Out (web dashboard, mobile swipe) | My Time Sheet clock card | D-03 Basic "Employee can mark punch from their dashboard", "Take Picture"; APP "Swipe to Check In/Out"; SRS ATT-4/5/6; OQ C6/C7 | punch | **Build** `GET/POST /clock`: refused unless the switch is on; photo required when "Take Picture" is on; geo-fence and IP checks. |
| Attendance Logs list, filters, download | `/attendance/logs` | D-03 "Attendance Logs" | punch, device | **Build** `GET /logs` (≤31 days, FE limit), `/logs/export` (CSV). |
| Create / edit / delete a manual log | + Create, Edit | D-03 "Create Attendance Log (manual)" | punch (source manual) | **Build** `POST/PUT/DELETE /logs`. Only manual and imported punches change; device / dashboard / request punches can only be ignored (`PATCH /logs/{id}/ignore`). Own punches refused (raise a punch request, REQ-1). |
| Import Attendance Log: Computer (file) | Import dialog | D-03 "Import ... Computer"; SRS ATT-2 | punch (source import_file) | **Build** `POST /logs/import` (JSON lines) and `/logs/import/csv` (text/csv: Employee Code, Date, Time, Punch Type). Duplicates skipped, bad lines reported. |
| Import Attendance Log: Machine | Import dialog, machine list | D-03 "Machine"; SRS ATT-1/2; OQ C1/C2 open | punch (source biometric), device_enrolment | **Build with changes** `POST /settings/devices/{id}/punches`: a device connector pushes lines `{deviceUserNo, punchedAt, punchType}`; HRango cannot pull from a device until C1 (models/SDK) is answered. |
| Biometric devices (register, branch, address, status) and enrolment | none (machines are mock data) | SRS ATT-3 (D: old "Biometric Devices" item); OQ C3/C5 | device, device_enrolment | **Build** `/settings/devices` CRUD + `/enrolments` (employee ↔ device user number). Fingerprints stay on the devices (NFR-10). |
| Settings: Basic | Basic tab | D-03 "Basic Configurations" | core.company_setting (module attendance) | **Build** `GET/PUT /settings/basic`. |
| Settings: IP Restrictions | IP Restrictions tab | D-03 "IP Restrictions"; SRS ATT-6 | ip_restriction, ip_restriction_target | **Build** CRUD `/settings/ip-restrictions`; "Count" is computed (`addressCount`). |
| Settings: Geo Fencing | Geo Fencing tab | D-03 "Geo Fencing" (2 steps: targets, map circle/polygon); SRS ATT-6 | geo_fence, geo_fence_target | **Build** CRUD `/settings/geo-fences`. |
| Overtime settings (6 switches + shift hours) | none | D-03 "Overtime Settings"; FRD "Overtime Settings" | core.company_setting (module overtime) | **Build** `GET/PUT /settings/overtime`. |
| Overtime Policy with slabs | none | D-03 "Overtime Policy" (design only) | overtime_policy, overtime_policy_slab | **Build** CRUD `/settings/overtime-policies` with slabs. Converting minutes to leave is **not** built (who a policy applies to is not designed). |
| My Overtime, Applications, Bulk Applications, Bulk Overtime | `/attendance/overtime` placeholder | D-03 "Overtime"; FRD Overtime Request | req.request + req_overtime | **Requests module** (overtime is a request kind). Attendance applies approved minutes. |
| Missing Punch menu | `/attendance/missing-punch` placeholder | D-03 "menu item only" | — | **Not built**: punch requests cover it; the time sheet `flag=missing_punch` filter lists the days. |
| Settings: Scheduling, Rest Day, Break Types, Holidays, Time Slots tabs | settings tabs | D-03 | sch.* | **Scheduling module** (02-scheduling.md). |
| Attendance Insights | menu | D-03 menu only | — | **Not in first build** (no design). |
| Facial recognition | — | SRS ATT-13, out of scope | — | **Not in first build.** |

## Time-sheet processing (`att.usp_timesheet_process`)

Set-based over a company, an employee set (JSON ids, or everyone not left; optionally limited by a permission's scope)
and a date range (≤ 1 year), with a week of context either side. Reads `sch.fn_employee_day_schedule` (shifts, rest
days, holidays), `att.punch`, approved `req.request` (+ `req_leave`, `req_time_window`, `req_overtime`, type
`work_from_home`), `lv.leave_type` (sandwich), `core.company_setting`. Writes `timesheet_day` (MERGE, ids stable),
`timesheet_flag`, `timesheet_break`, then calls `att.usp_warning_raise` when a warning policy is active.

- **Punch window**: a day owns the punches between the midpoints to its neighbours' shifts (4 h from the shift next to a
  day without one, or midnight), so overnight shifts work. Several shifts on a day = one span.
- **First in / last out**: first check-in and last check-out; with "Ignore punch type" first and last punch.
- **Breaks**: break-out → break-in pairs; with "Use Check IN/Check OUT for computing breaks" also check-out → check-in
  inside the day (or every inner pair when types are ignored). Worked = span − breaks.
- **Status** (first match): HR mark → holiday (attendance-exempt) → rest day → full-day leave → no shift (`weekend`) →
  WFH → official visit without punches → no punches (`yet_to_start` before the shift ends, else `absent`) → half-day
  leave (`half_day`) → short day → present. Sandwich: an off day between two leave days of sandwich leave types.
- **Late**: check-in after expected start, less a relaxation window; up to `late_grace_minutes` it is a `grace` flag
  and `grace_consumed_minutes`, not late. **Early**: check-out before expected end, less a relaxation window.
  Not for flexible slots, holidays, rest days, WFH or a half leave without times. A half/short leave with times moves
  the expected start or end.
- **Short day**: finished day with worked < `minimum_workable_minutes` (or expected minutes when 0); flexible slots
  always, fixed ones when "Short duration applicable on non-flexible" is on.
- **Overtime**: before start when "on check-in" is on, after end when "on check-out" is on (flexible: worked − workable);
  zero when "after duty duration" is on and the duty was not completed; work on a day off counts only when "on holidays"
  is on. Approved overtime = approved requests' minutes when approval is required, else requests or computed.
- **Flags**: late, early, grace, overtime, missing_punch, relaxation, official_visit, half_leave, short_leave.
- **Frozen** days are never written. **Manually updated** days keep HR's expected/actual times, mark and breaks (minutes
  and flags recomputed) unless `overwriteManual`.
- Triggered by: every punch write (import, manual, clock, ignore), day edit, approval effects, first read of a day, and
  `POST /time-sheet/process`.

## Approval effects (called by the requests engine in its transaction)

`att.usp_request_apply_<kind>` / `att.usp_request_revert_<kind>` `@company_id, @actor_user_id, @request_id`, no result
sets: **punch** (adds a `punch_request` punch; revert deletes it), **time_window** (relaxation / official visit:
re-process; the processor reads the window), **overtime** (re-process; approved minutes = `approved_minutes` or
`applied_minutes`; also records on `req.req_overtime` the overtime policy and a copy of the slab the minutes fell under,
revert clears them), **work_from_home** (marks the request days' shifts `sch.schedule.is_wfh = 1`, revert sets 0, then re-process from_date..to_date; WFH days are the request's `req.request_day` rows, not the whole range). Each counts its own request whatever its status
at that moment (`@include_request_id` / `@exclude_request_id`). A frozen day refuses the approval (409
ATTENDANCE_FROZEN, OQ C9 open). Days HR edited by hand are not changed by an approval.

## Gaps

- **Documents → frontend**: device registry and enrolment; overtime settings and policies; Subordinates tab; warnings
  columns from real warnings; photo / location / IP on clock-in; manual-update protection and history per field.
- **Frontend → documents**: direct row actions (missing punch, relaxation, absence-as-leave, overtime approve) — the
  documents make them requests; "Workable shifts/hours", "Leave Applied", "Official Duty", "Relaxation" legend states
  are FE-only (relaxation and official visit are flags here); IP restriction `name`, geo-fence/IP "Active" switch on the
  list (kept as `isActive`); 31-day log range (followed).
- **Neither**: automatic device pull (C1/C2), offline buffering (NFR-5) — a connector posting to the device punches
  endpoint covers both once C1 is answered; a nightly processing job (no job runner in the stack).

- **Overtime (Oct 2026, gray structure)**: `OvertimePolicyOut.usageCount` (approved overtime requests that fell
  under the policy); `DELETE /attendance/settings/overtime-policies/{id}` answers 409 `IN_USE` while it is in use
  (make it inactive instead). Which policy applies: the company's first active daily policy with a slab holding the
  approved minutes. TODO: assigning policies to people / departments, monthly policies, capping approved minutes by
  the top slab, encashment (leave credit or full-day pay). Bulk overtime filing and the typed overtime `details` are
  in 04-requests.md.

## ERD changes (05-att.md)

- All date-times are local wall-clock (company time zone), like `sch.schedule.start_at`; no UTC conversion of punches.
- `device`: + `port`, `address`, `UNIQUE (company_id, name)`; `branch_id` optional; `status` active/inactive.
- `device_enrolment`: `device_user_no` NN, `UNIQUE (device_id, device_user_no)`.
- `geo_fence`: + `applies_to_all`, `joining_from_date/joining_to_date`, `is_for_shift`, `is_active`, unique name.
- `geo_fence_target`, `ip_restriction_target`: `target_type` + `target_id` or `target_value` (religion, nationality);
  `ip_restriction_employee` replaced by `ip_restriction_target` (design: "Add Criteria", not only employees).
- `punch`: + `company_id`, `remarks`, `is_manually_updated`; `UNIQUE (employee_id, punched_at, punch_type)`.
- `timesheet_day`: + `company_id`, `expected_minutes`, `shift_worked_minutes`, `approved_overtime_minutes`,
  `marked_status`, `leave_request_id`; − `sync_status` (undefined); `yet_to_start` status.
- New `timesheet_break` (breaks of the day, from punches or HR's edit).
- `overtime_policy`: + `description`, `is_active`, unique name; slab `encashment_type` full_day / leave + `leave_type_id`.
- Warning tables are in 16-warning.md (leaves agent).

## Decisions on unclear points

1. Settings live in `core.company_setting`: module `attendance` keys `ignore_punch_type`, `use_check_in_out_for_breaks`,
   `short_duration_on_non_flexible`, `dashboard_punch`, `allow_multi_shift` (read by scheduling),
   `picture_on_dashboard_punch`, `minimum_workable_minutes`, `late_grace_minutes`; module `overtime` keys
   `overtime_on_check_in`, `overtime_on_check_out`, `overtime_approval_required`, `do_not_auto_create_requests`,
   `overtime_on_holidays`, `overtime_after_duty_duration`, `encashment_shift_minutes`. Never saved = off/0. The form's
   rowVersion is the newest row version of the module's rows.
2. `late_grace_minutes` is a daily grace on the Basic tab (FE shows 5 minutes; documents only put grace on warning
   policies, which keep their own period grace).
3. Clock-in is refused unless "Employee can mark punch from their dashboard" is on (biometric is primary, C6). Geo:
   when "Geo Fences Required On Shift" (`scheduling.geo_fence_required_on_shift`) is on and the current shift has a fence,
   the punch must be inside it; otherwise inside any active fence that applies to the employee; no fence = no check.
   IP: inside any applicable active restriction; none = no check. Client IP is the socket address (behind a proxy run
   uvicorn with `--proxy-headers`). Photo: a `photoFileId` of `core.stored_file` (C7: stored only).
4. Fence / restriction targets: one value per row; same type = OR, different types = AND.
5. Device punch types: check_in/check_out/break_out/break_in or a break type's start/end identifier; missing type is
   check_in only when "Ignore punch type" is on.
6. Nobody enters, edits or deletes their own punches or edits their own day (self-approval); they raise a punch request.
7. Geo fence used by shifts and devices with punches cannot be deleted (409, set inactive). Overtime policies are
   configuration only until the documents say who they apply to.
8. Codes: MCH-, GF-, IPR- from `core.number_sequence`.
9. **Editing a day is a partial update** (`PUT /days/{employeeId}/{date}`): a field the client does not send keeps
   its value; to clear one the client sends it as `null` (`breaks: null` or `[]` removes the breaks). The service
   passes the sent field names (`model_fields_set`) to `att.usp_timesheet_day_save @sent`; only changed fields
   reach the audit trail. (Before, an omitted `expectedIn` / `expectedOut` cleared them and the day turned into
   a weekend.)

## Cross-module needs

- **Scheduling**: punches and time-sheet times are local wall-clock — no UTC conversion (your README says "after
  converting them from UTC"). After creating, editing or deleting shifts, rest days or holidays, call
  `att.usp_timesheet_process @company_id, @actor_user_id, @from_date, @to_date, @employee_ids (JSON), @quiet = 1`.
  Reads key `allow_multi_shift` as agreed.
- **Leaves**: `lv.usp_request_apply_leave` / revert should call `att.usp_timesheet_process` for the leave dates
  (`@include_request_id` / `@exclude_request_id` = the request) so leave days show at once.
- **Requests**: request types `work_from_home`, `relaxation`, `official_visit` codes are read; `req_punch.punch_type`
  may be check_in/check_out (any spelling) or a break identifier.
- **Shared / core**: a file upload endpoint for the clock-in photo (`core.stored_file`); a scheduled job to run
  processing nightly; `default_roles.py` employee role could exclude `attendance.logs.create` (the service refuses own
  punches anyway).
- **Payroll**: sets `att.timesheet_day.is_frozen` for the payroll period; reads worked / late / approved overtime.
- **Frontend**: day key paths `/days/{employeeId}/{date}`; settings paths `/settings/{basic,overtime,devices,
  ip-restrictions,geo-fences,overtime-policies}`; row actions go to the requests module.
