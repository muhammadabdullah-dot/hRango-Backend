# Frontend vs documents vs ERD — and what the backend builds

One file per module group. Each compares the frontend's screens (`frontend/`, a React app with a
mocked API) with the documents (`requirements/`, the Functional Requirements PDF, the Mini SRS) and
the ERD (`erd/source/`), and records what the backend builds and why. **The documents are the
authority**; the frontend shows which modules and screens exist and will be moved to the backend's
routes and shapes (each file lists them).

State on 26 Oct 2026: 250 tables, 261 procedure files (752 procedures, 84 functions), 671 permission
codes, 985 API operations, 237 tests passing on one merged database.

| File | Modules | Endpoints | Tests |
|---|---|---|---|
| [01-organisation.md](01-organisation.md) | Control Panel (organisation set-up), employees, users and roles, dashboard, inbox | 133 (+3 sign-in) | 32 |
| [02-scheduling.md](02-scheduling.md) | Roster, scheduling, time slots, breaks, rest days, holidays | 47 | 21 |
| [03-attendance.md](03-attendance.md) | Attendance: devices, punches, time sheet, overview, logs, settings | 48 | 31 |
| [04-requests.md](04-requests.md) | Requests engine, 13 request types, approval flows, delegation, loans | 159 | 21 |
| [05-leaves-and-warning.md](05-leaves-and-warning.md) | Leaves, warning policies and penalties | 38 | 13 |
| [06-payroll.md](06-payroll.md) | Payroll | 131 | 19 |
| [07-assets-offboarding.md](07-assets-offboarding.md) | Assets, end of employment, off-boarding checklist | 39 | 14 |
| [08-projects.md](08-projects.md) | Project management | 79 | 21 |
| [09-manpower-benefits.md](09-manpower-benefits.md) | Manpower planning, e-budgeting, benefits | 70 | 12 |
| [10-recruitment.md](10-recruitment.md) | Recruitment: openings, applicants, pipeline, interviews, offers, hiring | 42 | 8 |
| [11-performance-training.md](11-performance-training.md) | Performance (goals, KPIs, appraisals, increments) and training | 74 | 9 |
| [12-employee-profile.md](12-employee-profile.md) | Employee profile tabs, photo, documents, Update Information requests | 35 added | 5 |
| [13-engagement.md](13-engagement.md) | Newsfeed and surveys | 34 | 13 |
| [14-files-and-events.md](14-files-and-events.md) | Real uploads and events across 11 existing modules (what changed, for the frontend) | changed | 134 |

Also added on 26 Oct: Expense claims, Air Tickets and Requisitions as request types (04-requests.md),
file uploads (`/api/files`), and webhooks (`/api/integrations/webhooks`).


## How the modules are wired together

- **Approvals.** On a request's final approval the requests engine runs
  `<schema>.usp_request_apply_<kind>` inside its transaction; when an approved request's cancellation
  is approved it runs `usp_request_revert_<kind>`; `usp_request_validate_<kind>` runs on submit.
  leave → lv, punch / time window / overtime / work from home → att, rest day / shift swap → sch,
  promotion / transfer → hr, resignation → sep, loan → loan, task extension → pm (approved inside
  projects today), travel → none.
- **Attendance follows the others.** Approving or cancelling leave, rest days and shift requests
  re-processes the affected past days; days payroll has used are locked (409 `ATTENDANCE_FROZEN`).
  Direct schedule edits are picked up by `scripts/process_attendance.py` (run nightly) or the time
  sheet's Process button.
- **Payroll reads** time-sheet days, the leave ledger and encashments, loan installments and warning
  penalties, marks what it paid, freezes the days it used, and on closing a final settlement lets the
  end-of-employment record complete.
- **Balances.** Leave balance is one function (`lv.fn_leave_balance`) used by requests, leaves and
  payroll's encashment.

## Decisions taken that you may want to confirm

| # | Decision | Where |
|---|---|---|
| 1 | Default roles hold salary, bank, CNIC, loan and payslip figures back from Line Manager, Department Head and Executive (own records excepted) until open question E6 (who sees salaries) is answered. Managers keep voucher approval; department heads keep their department's budget approvals. | `backend/app/core/default_roles.py` |
| 2 | Resignation approved = end-of-employment starts (open question E8 taken as "yes"). | 07 |
| 3 | Attendance and scheduling times are local wall-clock time (as devices report them); audit stamps stay UTC. | 03, ERD conventions |
| 4 | A daily late-grace setting was added; the documents give grace only on warning policies. | 03 |
| 5 | Approving a request for a day payroll has already used is refused (open question C9). | 03 |
| 6 | Closing a payroll is irreversible (no reopen, no arrears), as the documents say. | 06 |
| 7 | Manpower budgets and benefit elections are approved inside their modules, not through the requests engine (a budget belongs to a department, not an employee). | 09 |
| 8 | Benefits is built from the designs although it was on the earlier "not in the first build" list; Health Benefits and Perks fields come from the Dashboard App Version notes. | 09 |
| 9 | Leave year follows the company's fiscal year (new companies default to July–June). | 05, 01 |
| 10 | Three BRD task rules are not enforced because they block normal use (unique task names per list, all fields required, no past due dates). | 08 |

## Shared services

- **Files**: `POST /api/files` stores uploads under `uploads/<company>/<module>/<yyyy>/<mm>/`; forms send file ids;
  records return signed, expiring download links. Unused uploads are removed nightly.
- **Notifications and webhooks**: every inbox notification and every module event goes to the subscribed
  webhooks, signed and retried. E-mail is not built (a mail gateway can subscribe to `notification.created`).
- **Nightly** (`backend/scripts/nightly.py`): attendance processing, document expiry reminders, unused uploads.

## Not built yet

- Punch fields and pulling punches from devices (open question C1): a device connector pushes to
  `POST /api/attendance/settings/devices/{id}/punches`. To be designed later.
- E-mail sending.
- Custom Forms and Configuration: menu items only, nothing defines them.
- Careers site (public applying), AI features (job descriptions, screening, leave applications): need decisions.
