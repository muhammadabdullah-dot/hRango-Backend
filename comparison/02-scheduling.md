# 02 Scheduling: roster, shift planner, time slots, break types, rest days, holidays

Sources: `requirements/HRango - UI design/Design/04-Scheduling-and-Roster/README.md` (D-04),
`requirements/HRango - UI design/Design/03-Attendance/README.md` (D-03, settings parts),
`requirements/HRango - Shift Module UX/README.md` (SUX), `requirements/HRango - UI design/All Dashboards/06-Attendance-and-Leave`,
`HRango - Mini SRS.pdf` (SRS: SCH-1..6, ATT-7, ATT-11, REQ-7, WF5), `Functional Requirements for HRango.pdf` (FRD, Rest Days
Request), `HRango - Open Questions.pdf` (OQ), `HRango - Overview.pdf`, `erd/source/04-sch.md`. The frontend (`frontend/`) shows
which screens exist; its mock data and payloads are not a specification. No written requirements exist for this module
(OQ B4): the designs are the source, and the frontend is followed only where they are silent.

Backend: `/api/roster/...` (11 endpoints) and `/api/scheduling/...` (36 endpoints). Procedures in `backend/db/procedures/sch/`.

## Screens and features

| Screen / feature | Frontend (route) | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Time slots: list, create, edit, delete | none (slot fields only inside Create Scheduling step 2) | D-03 "Time Slots"; SRS SCH-1 | time_slot, time_slot_break | **Build** `/scheduling/settings/time-slots`. Code TS-00001 from core.number_sequence. Overnight is derived (end at or before start). Workable minutes: given for flexible slots, computed for fixed ones (duration minus non-inclusive breaks). Breaks belong to the slot. Frontend needs a Time Slots tab. |
| Break types | `/attendance/settings` Break Types tab | D-03 "Break Types"; SRS ATT-7 | break_type | **Build** `/scheduling/settings/break-types`. Identifiers unique across the company's types (a device sends them). Delete refused while a slot or shift uses the type (a punch stops it with 409 IN_USE). |
| Rest days (Create New Rest Day, view, delete, delete a range) | `/attendance/settings` Rest Days tab; Scheduling "+" → Create rest day | D-03 "Rest Day"; D-04 "Create New Rest Day"; SRS SCH-5 | rest_day_rule, rest_day_rule_employee, rest_day | **Build with changes** `/scheduling/settings/rest-days` (+ `/delete-range`). A rule = employees, from/to, weekdays, repeat 0..8 weeks, step, payable; saving (re)generates its rest_day rows. Dates already a rest day are left alone. |
| Holidays and holiday rules | `/attendance/settings` Holidays tab | D-03 "Holidays"; SRS ATT-11 | holiday, holiday_rule | **Build with changes** `/scheduling/settings/holidays`. Rule kinds as designed: employee; org_structure (location + branch); geo_location (country + state + city, matched against the employee's branch); religion. No rules = everyone. |
| Scheduling configuration switches (Geo Fences Required On Shift, Ignore rest days for shift selection) and Basic "Allow Multi Shift on single day" | `/attendance/settings` Basic and Scheduling tabs | D-03 "Basic", "Scheduling Configurations"; SRS SCH-6 | core.company_setting | **Not mine**: attendance settings (attendance agent). I read `allow_multi_shift` (see cross-module needs). |
| Roster group list, add, edit, view ("Time Roster View") | `/roster` | D-04 "Roster", "Time Roster View" | roster_group, roster_group_day | **Build with changes** `/roster/groups`. The week is a time slot (or a day off) per weekday, not free clock times, so a roster carries the slot's breaks, flexibility and overtime flags. Status (is_active) follows the frontend (documents silent). |
| Enrol employees in a roster for a period, discontinue | `/roster?dialog=enroll` | D-04 only shows "Employee Enrolled"; SRS term "Roster" | roster_group_member | **Build** `/roster/groups/{id}/enrolments`, `/roster/enrolments/{id}` (+ `/discontinue`). Follows the frontend: start/end date inside the group's period, one roster per employee at a time, active / discontinued tabs. Branch on the enrolment not built (not in documents). |
| Shift planner board, My / Subordinates / All, week / month, filters, planned hours | `/scheduling` | D-04 "Scheduling"; SRS SCH-3 | schedule, schedule_break, rest_day, holiday | **Build** `GET /scheduling/schedules?tab&from&to&...` (≤ 93 days): a page of employees with shifts, rest days, holidays, and planned minutes per date over every matching employee. Filtered by `auth.fn_visible_employees`. Filters as designed (employee, type, status, department, designation, branch, location, grade, group, time slot, roster). |
| Year view | `/scheduling` period Year | older D-04 frames (Month, Year) | schedule, rest_day | **Build** `GET /scheduling/schedules/year` (frontend; documents only hint). |
| Create Scheduling (batch) | Scheduling Create | D-04 "Create Scheduling"; SRS SCH-2 | schedule_batch, schedule, schedule_break | **Build with changes** `POST /scheduling/schedules/batches`: dates, employees (or a roster group's members), a time slot **or** a roster group, weekdays, repeat never / every 1..8 weeks with step, breaks override, geo fence, work from home. Overlaps refused (409) unless `replaceExisting`. Rest days are skipped. The frontend's "Rest Days" toggle (weekend days become rest days) is not built: rest days are made with the rest-day form. |
| Apply Default Shift | Scheduling Apply Default Shift | D-04 "Apply Default Shift"; SRS SCH-4 | schedule_batch (kind default_shift), hr.employee.default_time_slot_id | **Build** `POST /scheduling/schedules/default-shift`: each day, the roster the employee is enrolled in, otherwise their default time slot. |
| Add one shift, View / Edit Scheduling | click a cell | D-04 "View / Edit Scheduling" | schedule, schedule_break | **Build** `POST/GET/PUT/DELETE /scheduling/schedules/{id}`: date, slot, optional other times, breaks, geo fence, WFH. "Mark Break In / Out" in the design writes punches: attendance's. |
| Swap Shift | Swap / drag | D-04 "Swap Shift"; SRS SCH-4 | schedule | **Build** `POST /scheduling/schedules/{id}/swap`: exchange with another person's shift, or give the shift to someone on the same date. Moving a shift to another date is an edit. |
| Multi Edit, Multi Delete, Delete Scheduling (range, "Delete Rest Days") | multiselect, Delete | D-04 toolbar, "Delete Scheduling"; SRS SCH-4, SCH-5 | schedule, rest_day | **Build** `POST /scheduling/schedules/bulk-edit`, `/bulk-delete` (ids, or a range for employees / everyone; rest days only when asked). |
| Export | All tab Export | D-04 toolbar; SRS SCH-4 | | **Build** `GET /scheduling/schedules/export` (CSV, one line per employee and date). |
| Import | All tab Import (CSV) | D-04 toolbar; SRS SCH-4 | | **Not in first build**: no document defines the file. |
| Reverse Decision | slot flag in Create step 2 | D-04 "Reverse Decision on a schedule entry" | | **Not in first build**: meaning undefined. |
| Total Duration (48 hrs) / "total" mode, overtime minutes per slot | Create step 2 | D-04 step 2 shows "Total Duration (48 hrs)" | | **Not in first build**: no rule says what is counted against it. |
| Geo fence on a shift / batch | Create step 1 "Apply Geo Fence" | D-04 step 5 | att.geo_fence | **Pick only** (`geoFenceId`); fences are created in attendance settings. One fence per shift (ERD); the frontend allows several. |
| Pickers for the planner forms | | | | **Build** `/scheduling/options/time-slots`, `/break-types`, `/roster-groups` (reachable with the planner's view permission, so HR officers without settings access can pick). |
| Shift Request / Shift Approval | requests module | D-04 "Shift Request + Approval"; OQ D3 | req.req_shift_swap | **Effect built**: `sch.usp_request_apply_shift_swap` / `usp_request_revert_shift_swap`. Screens: requests agent. |
| Rest Days Request | requests module | FRD "Rest Days Request"; SRS REQ-7 | req.req_rest_day, req.request_day | **Effect built**: `sch.usp_request_apply_rest_day` / `usp_request_revert_rest_day`. |
| Shift colours, shift chips | board | SUX §02 | time_slot.color | **Build**: one colour per slot. Colour scheme itself is a frontend matter. |
| Time sheet against the shift | attendance | SUX §01; SRS WF1, ATT-8 | | **Provided**: `sch.fn_employee_day_schedule` (below). |
| Mobile "shifts" | | SRS MOB-4 | | Later (mobile). |

## Gaps both ways

- **In the documents, not the frontend**: a Time Slots screen (D-03 lists TS- codes, tags Flexible / Full Overtime / Short
  Overtime, "Create New Slot"); breaks defined on a slot; Apply Default Shift using the employee's default shift.
- **In the frontend, not the documents**: roster status switch, per-weekday free clock times in a roster, enrolment
  branch, the year view, "Rest Days" toggle in Create Scheduling, several geo fences per shift, overtime minutes and
  "total" mode on a slot, moving a shift by drag. Built: status and year view; the rest as noted above.
- Frontend changes the backend implies: a Time Slots tab; the roster week picks a time slot per day; rest-day forms send
  weekdays as 1..7 (Monday = 1); Create Scheduling sends either `timeSlotId` or `rosterGroupId`; one geo fence per shift;
  conflicts come back as 409 `SCHEDULE_OVERLAP` / `SCHEDULE_DAY_TAKEN` / `REST_DAY` and can be resent with
  `replaceExisting: true`.

## ERD changes (`erd/source/04-sch.md`) and why

- `time_slot`: start/end, duration, workable minutes NOT NULL; `UNIQUE (company_id, name)`.
- `break_type`: identifiers NOT NULL; `UNIQUE (company_id, name)`.
- `time_slot_break`: break type and times NOT NULL.
- `roster_group`: dropped `time_slot_id` (one slot cannot describe a week); added `description`, `is_active`;
  `from_date` NOT NULL; `UNIQUE (company_id, title)`.
- **New** `roster_group_day` (weekday 1..7, is_day_off, time_slot_id; `UNIQUE (roster_group_id, weekday)`): the weekly pattern.
- `roster_group_member`: was a link table; now has `id`, `start_date`, `end_date` (enrolment for a period, discontinue,
  history of enrolments).
- `schedule_batch`: added `batch_kind` (create, default_shift, import), `weekdays`, `step`, `is_wfh`; slot and roster optional.
- `schedule`: added `company_id` (every query filters on it), `planned_minutes` (board footer, year view, attendance);
  `time_slot_id` NOT NULL. `start_at`/`end_at` are documented as local wall-clock date-times (the plan is a business date
  plus a local time; punches stay UTC).
- `schedule_break`: break type and times NOT NULL.
- `rest_day_rule`: `repeat_mode` replaced by `repeat_every_weeks` (same "Repeat" list as Create Scheduling); weekdays,
  repeat, step NOT NULL.
- `rest_day`: added `company_id`; rule and request optional.
- `holiday`: type and dates NOT NULL; `UNIQUE (company_id, name, start_date)`.
- `holiday_rule`: `rule_type, ref_id` could not hold "location + branch", "country + state + city" or a religion name.
  Now `rule_type` plus `employee_id`, `location_id`, `branch_id`, `country_id`, `state_id`, `city_id`, `religion`.

## Decisions on unclear points

1. **Overnight**: a slot whose end is at or before its start ends the next day; the flag is derived, not entered. A
   shift belongs to the date it starts on (`work_date`).
2. **Inclusive break** = counted as working time (not taken off the planned minutes). Flexible slots plan their workable
   minutes.
3. **Repeat and step** (Create Scheduling and rest days): repeat 0 = every week in the range; n = cycles of n weeks
   counted from the Monday of the start date, the first `step` weeks on (every 3 weeks, step 2 = two on, one off).
4. **Precedence of a day**: exempt holiday > rest day > shift. A rest day does not delete shifts; new batches skip rest
   days; a single shift on a rest day is refused. A holiday that is not attendance-exempt is listed but worked.
5. **Conflicts**: one employee's shifts never overlap; without "Allow Multi Shift on single day" one shift per date.
   Batches refuse conflicts (409) unless `replaceExisting`, which replaces shifts on the same dates or overlapping.
   A shift that a time sheet day or a request points at cannot be replaced or deleted (409 IN_USE).
6. **Apply Default Shift** = the roster the employee is enrolled in on each date, else `hr.employee.default_time_slot_id`.
7. **Roster group with no employees** in Create Scheduling = its members enrolled on each date.
8. **Editing a time slot** does not move shifts already scheduled from it (shifts keep their times).
9. **Holiday geo rule** matches the employee's branch country/state/city (the employee record has no address fields).
10. **Rest-day request** effect: rest days on the selected days (`request_day`), or every date from/to when none; payable
    from `req_rest_day.is_payable`; existing rest days kept. Revert deletes the request's rest days.
11. **Shift request** effect: with a colleague, exchange (or give) the shifts; without one and with a time slot, move the
    requester's shift (or a new one on `shift_date`) to that slot. Revert swaps back / restores the previous slot and
    times (kept in `core.audit_log`, `field_name = request:<id>`) / deletes the shift it created.
12. **Scope**: settings are company-wide (settings permissions). Shifts and enrolments are employee records: every
    procedure takes the endpoint's permission code and joins `auth.fn_visible_employees`; the My / Subordinates tabs
    narrow that further. Unreachable records read as 404; writing to an unreachable employee is 403.
13. **Permissions**: `roster.groups.*` (CRUD), `roster.enrolments.{view,enroll,edit,delete,export}`,
    `scheduling.schedules.{view,create,edit,delete,export}` (edit covers swap and multi edit; create covers batches and
    default shift), `scheduling.settings.{time_slots,break_types,rest_days,holidays}.*` (CRUD). With the default roles an
    employee sees their own schedule only; a line manager reads the team; HR officers plan but do not delete or change
    settings.
14. **Reference data**: none. The documents give sample break types, slots and holidays only; nothing is seeded.

## What this module provides to others

- **Attendance** (time-sheet processing):
  - `sch.fn_employee_day_schedule(@company_id, @employee_id NULL = everyone, @from, @to)`: one row per employee and date
    (one per shift on a multi-shift day): `schedule_id, time_slot_id, time_slot_code, time_slot_name, start_at, end_at,
    planned_minutes, workable_minutes, is_flexible, is_overnight, full_overtime, short_overtime, is_wfh, geo_fence_id,
    is_rest_day, rest_day_payable, holiday_id, holiday_name, holiday_exempt, day_kind` (`holiday`, `rest_day`, `shift`,
    `unscheduled`). `start_at`/`end_at` are local wall-clock (company time zone); compare with punches after converting
    them from UTC.
  - `sch.fn_employee_holidays(@company_id, @from, @to)`: employee, date, holiday, type, attendance_exempt.
  - Planned breaks per shift: `sch.schedule_break` (break_type_id, start_at, end_at, is_inclusive); break identifiers in
    `sch.break_type`. `att.timesheet_day.schedule_id` may point at `sch.schedule`.
  - `sch.fn_dates(@from, @to)` and `sch.fn_pattern_dates(...)` (calendar helpers) may be reused.
- **Requests**: `sch.usp_request_apply_rest_day`, `sch.usp_request_revert_rest_day`, `sch.usp_request_apply_shift_swap`,
  `sch.usp_request_revert_shift_swap` (`@company_id, @actor_user_id, @request_id`); no result sets; THROW 504xx blocks.
  Request forms can read a person's day with `sch.fn_employee_day_schedule`.

## Cross-module needs

- **Attendance agent**: store the Basic switch "Allow Multi Shift on single day" as `core.company_setting`
  (`module = 'attendance'`, `setting_key = 'allow_multi_shift'`, `setting_value = 'true'`/`'false'`), which the
  scheduling procedures read; or tell me the key used.
- **Requests agent**: in `req_shift_swap` mark `from_schedule_id`, `time_slot_id`, `with_employee_id`, `to_schedule_id`
  `{NULL}`: the table has no `id`, so build.py makes every FK NOT NULL, which forces a colleague and a slot on every
  shift request (a swap needs no slot; a slot change has no colleague).
- **Employees agent**: the employee form should set `hr.employee.default_time_slot_id` (options from
  `GET /api/scheduling/options/time-slots`); Apply Default Shift uses it.
- **Shared**: none to change. Uses `core.number_sequence` prefix `TS-` and writes `core.audit_log` with `company_id`.
