# 01 Organisation, employees, access, dashboard, inbox: frontend vs documents vs ERD

Status: built (first build). Backend: `/api/organisation`, `/api/employees`, `/api/access`, `/api/dashboard`,
`/api/inbox` (133 endpoints). Tests: `tests/test_organisation.py`, `test_departments.py`, `test_employees.py`,
`test_access.py`, `test_dashboard.py`, `test_inbox.py` (31 tests with `test_auth.py`).

Sources: `requirements/HRango - UI design/All Dashboards/07-Settings-Control-Panel` (CP), `.../03-Employee-and-Profile-Dashboard`
(EMPD), `.../01-CEO-Dashboard` (CEO), `.../02-HR-Dashboard` (HRD), `.../Design/08-Website-and-Menus` (MENU),
`.../App` (APP), Mini SRS v0.2 (SRS: ORG-1..4, EMP-1..4, ACC-1..16, DSH-1, section 3), Functional Requirements PDF
(FRD: Promotion request p. 60, Transfer request pp. 86-88, Bank Details (Talent Management) p. 114), Open Questions (OQ).

## Screens and features

| Screen / feature | Frontend (route) | Documents | ERD tables | Decision |
|---|---|---|---|---|
| General Settings | `/settings/control-panel/general` | CP "Control Panel also has General Settings" (no frame); SRS NFR-8 (PKR, Pakistan time) | `org.company` | Build with changes: fields follow the frontend (documents silent); stored on `org.company`, per company. `GET/PUT /organisation/general` |
| Companies (several per database) | none (company switcher not drawn) | SRS ORG-1, ACC-8; OQ A4 | `org.company`, `auth.user_company` | Build: list / get / add / edit, `lookups/companies` for the switcher (`X-Company-Id`). A new company gets default roles, default employment types, and its creator becomes its Company Administrator |
| Location list + create/edit | `/settings/control-panel/locations` | CP Location Create; SRS ORG-2 | `org.location` | Build. CP's "Branch: Select Company" is read as the company, which is the active company, so no company field is sent |
| Area list + create/edit | `/settings/control-panel/areas` | CP sidebar lists Area, no frame | `org.area` | Build with changes: name, location, description (frontend); `company_id` added for filtering |
| Branch list + create/edit | `/settings/control-panel/branches` | CP Branch Create (all fields); SRS ORG-2 | `org.branch`, `org.country/state/city` | Build. Area must be in the location; state in the country; city in the state |
| Job Title list + create/edit (head-count limit) | `/settings/control-panel/job-titles` | CP Job Title (two frames); SRS ORG-2 | `org.job_title` | Build. The map on the Job Title frame is a design leftover (CP "Issues") and is not built. The limit is enforced when an employee takes the title |
| Departments | not in the frontend | SRS M1 module list, ORG-2 | `org.department` | Build (worked example, unchanged behaviour; audit rows now carry `company_id`) |
| Divisions, cost centers, designations, grades, job levels, employee groups, employment types | none | SRS EMP-1 (grade, level, employment type); FRD Promotion (grade, designation, job title); frontend payroll filters | `org.*` | Build: one generic list/get/add/edit/delete each. Grades and job levels carry `sort_order` |
| Country / state / city pickers | used by Branch form (`/geo/*` in the mock) | CP Branch Create | `org.country/state/city` | Build: `/organisation/geo/countries`, `geo/states?country=PK`, `geo/cities?state=PK-PB` |
| "Search Location" geocoder | `/geo/search` mock | CP map and search box | none | Not built: needs an external map service (not chosen) |
| Picker lists for other modules | the mock's `/companies`, `/employees` | SRS ORG-4 filters on every list | all masters | Build: `GET /organisation/lookups/{kind}` (any signed-in user), `GET /employees/lookup?permission=` |
| Users, Subscriptions, Help & Support (Control Panel) | placeholders | CP menu items only | — | Users: built under Access. Subscriptions, Help: not built (no design, no tables; ERD "not in first build") |
| System User, User Group Permissions | `/settings/system-users`, `/settings/user-group-permissions` placeholders | SRS 3.1 ACC-1..16, ORG-3 (no design) | `auth.*` | Build (see Access below) |
| Biometric Devices, Custom Forms, Off Boarding settings | placeholders | other modules | — | Not mine (attendance, none, separation) |
| Employee directory (list, filters, picker) | none (Talent Management placeholder) | SRS EMP-1, EMP-4; FRD filters "Employee, Location, Branch, Department, Designation" | `hr.employee` | Build with filters q, status, branch, location, area, department, division, designation, job title, grade, employment type, group, line manager |
| Employee card / record (add, edit, switch off) | none | SRS EMP-1, EMP-4; APP Personal Info (first, last, parent name, CNIC, email, contact 1/2) | `hr.employee`, `hr.employment_period` | Build. Code generated from branch, else location, `employee_prefix` |
| Employment periods (joining, probation, confirmation, rehire) | none | SRS EMP-1 joining date, SEP-6 rehire | `hr.employment_period` | Build list / add / edit; overlap refused |
| Employment history (transfers, promotions) | Transfer log in the requests mock | FRD Promotion, Transfer; ERD | `hr.employee_history` | Build: history list, field-change list (audit), and the approval effects |
| Salary history | Salary Revision in payroll mock | FRD Salary Revision (payroll), Profile "Salary" tab (EMPD) | `hr.employee_salary` | Build employee salary tab (list/add/edit/delete, sensitive). The payroll Salary Revision screen (bulk, import) is payroll's |
| Bank details | none (mobile Bank Accounts) | SRS EMP-2; FRD "Bank Details (Talent Management)"; APP Bank Accounts | `hr.employee_bank_account` | Build (sensitive). APP's card Expiry/CV not built (OQ H6) |
| Documents, experience, agreement, contract tabs | none | SRS EMP-3; EMPD Experience, tabs | `hr.employee_document/experience/agreement` | Not built: needs file storage (`core.stored_file` has no upload service yet) |
| Roles (create, rename, copy, retire, ticks with scope + units) | none | SRS 3.1 ACC-2..8, ACC-16 | `auth.role`, `role_permission`, `role_permission_unit` | Build |
| Users (create, edit, link employee, companies, roles, password, switch off) | none | SRS ACC-6, ACC-8, ACC-11 | `auth.user_account`, `user_role`, `user_company` | Build |
| User grants and denials | none | SRS ACC-6 | `auth.user_permission_override` | Build (no selected_units for personal grants, see decisions) |
| Sessions list / end | none | SRS ACC-14 | `auth.user_session` | Build (one session, or all of a user) |
| Access change history | none | SRS ACC-15 | `core.audit_log` | Build `GET /access/audit` |
| Change own password | none on web; APP Change Password | APP | `auth.user_account` | Build `POST /access/me/password` (other sessions end) |
| HR dashboard | `/` (one summary card set) | HRD v2 | hr, att, req, eng | Build with changes, see Dashboard widgets |
| CEO dashboard | none | CEO | hr, att, req | Build with changes, see Dashboard widgets |
| My (employee) dashboard | none | EMPD | att, req, eng | Build with changes |
| Notifications (inbox) | top-bar inbox menu (`GET /inbox`, `POST /inbox/{kind}/read`) | APP Notifications; SRS APR-10 | `core.notification` | Build: summary, list, mark read, read all, clear, clear all |
| Messages (inbox "messages" tab) | inbox menu | Website lists "Chat Messenger"; SRS 8 out of scope | none | Not built: internal chat is out of the first release (SRS 8) |
| Announcements (notice board, events) | none | HRD Notice Board, Upcoming Events; EMPD Notice Board; APP "Announcement" | `eng.announcement` | Build CRUD under `organisation.announcements` (the boards need something to show) |

### Dashboard widgets

| Widget | Source | Decision |
|---|---|---|
| Headcount, women/men, women ratio, hired, left, turnover %, by department, by employment type, by gender, by age band, hired/left per month, department by gender, women % by job title | CEO, HRD | Built from `hr.employee` + `hr.employment_period` |
| Present / absent / on leave today, absenteeism %, attendance per month, today's attendance table | CEO, HRD, EMPD | Built from `att.timesheet_day` (read as the ERD defines it) |
| Leave applications table | CEO, HRD, EMPD | Built from `req.request` + `req.req_leave` (type code `leave`) |
| Notice board, upcoming events | HRD, EMPD | Built from `eng.announcement` |
| Salary statistics, total/average salary, pay hold, salary remains | CEO, EMPD | Not built: payroll results (`pay.payslip`) belong to payroll; salary is sensitive and the CEO dashboard permission is not. Payroll can add a dashboard endpoint behind its own codes |
| Loan applied/repaid, loan by department, loan management | CEO, EMPD | Not built: loans module's tables |
| Leave balance pie | EMPD | Not built: leaves module (`lv.leave_ledger`) |
| Project statistics, high priority tasks, tasks summary | CEO, HRD, EMPD | Not built: project module |
| Job overview (applications, shortlisted) | HRD | Not built: recruitment (`rec`) has no module in the first build |
| Employees retention | HRD | Not built: no definition in any document |
| Recent activity feed, upcoming birthdays | EMPD (early concepts only) | Not built: superseded concepts |

## Gaps both ways

Frontend has, documents do not: General Settings fields (legal name, contact details, date format, week start);
Area form; list screens for every organisation record (CP notes none are designed); the mock geocoder.
Kept: General Settings and Area as the frontend has them; geocoder not built.

Documents have, frontend does not: several companies and company switching (ORG-1); departments, divisions,
cost centers, designations, grades, levels, groups, employment types; the whole employee record (EMP-1..4);
roles, users, grants, sessions, audit (ACC-1..16); CEO and Employee dashboards; announcements; approval
effects of promotion and transfer. All built here; the frontend needs screens for them.

## ERD changes (my files only)

- `01-org.md`: `company` gains `legal_name, email, phone, website, address, country_id, date_format,
  week_start_day, is_active`, `UNIQUE (name)` (General Settings live on the company: they differ per legal entity,
  e.g. PKR / Asia/Karachi vs AED / Asia/Dubai; `core.company_setting` stays for module switches).
  `country.iso_code` is `CHAR(2)` (ISO 3166-1 alpha-2) and unique; `state.code` (ISO 3166-2, e.g. PK-PB) added and
  unique; `city UNIQUE (state_id, name)`. `location` gains `description`; `area` gains `company_id`,
  `description`. `grade` and `job_level` gain `sort_order`. `UNIQUE (company_id, name)` on every master,
  `UNIQUE (location_id, name)` on area.
- `02-hr.md`: `employee.status` adds `inactive` (switched off by HR); `employment_period.joining_date` NN;
  `employee_history` gains `change_type` (joining, transfer, promotion, demotion, edit), `location_id`,
  `final_authority_id`, `previous_values` (JSON snapshot used to undo a cancelled request), `is_reverted`;
  `employee_salary` gains `source_request_id`, `remarks`; bank `account_number`, `bank_name` NN.
- `13-core.md`: `audit_log.company_id` (nullable, so the access history and lists can filter by company);
  `notification` gains `company_id` (NN), `entity_type`, `entity_id`, `title` NN.
- `14-eng.md`: `announcement` gains `kind` (notice, event) and `event_date`; `author_id` optional.

## Decisions on unclear points

1. **Scope on administration screens.** Control Panel, users, roles, sessions are company-wide settings, not
   employee-owned records: holding the permission is enough, its scope is ignored. Employee records, salary,
   bank, CNIC, history and the dashboards use `auth.fn_visible_employees` with the endpoint's code.
2. **Sensitive data (ACC-9).** `employees.identity` (CNIC), `employees.salary`, `employees.bank_accounts` are
   separate codes marked sensitive. The CNIC is returned only to holders of `employees.identity.view`
   (`canSeeIdentity`); it is changed through `PUT /employees/{id}/identity`, never by the main form. CNIC and
   account numbers are not copied into the audit log. CNIC format: 13 digits, stored `#####-#######-#`.
3. **Deactivate = the directory's delete action.** Switching an employee off sets status `inactive`, switches
   off and signs out their accounts; switching on sets `active` and leaves accounts off. Leaving the company
   (status `left`, end of employment) is the separation module's.
4. **Employee codes** come from `core.number_sequence` per prefix (branch prefix, else location prefix, else
   `EMP`): `LHR-0001`. A typed code is kept.
5. **Line-manager cycles** are refused on save and in the transfer effect (`hr.fn_manager_chain`).
6. **Job title limit** counts employees not left or inactive; it is checked on add, on title change and in the
   promotion effect.
7. **Promotion / transfer effect timing.** The change is applied on final approval; `employee_history` keeps
   the request's effective date (no scheduler exists to apply future dates later). A promotion with a new salary
   adds an `employee_salary` row (source promotion). Applying twice is a no-op. Cancelling an approved request
   runs `hr.usp_request_revert_<kind>`, which restores the snapshot unless a later placement change exists (409).
   Promotion benefits (`req_promotion_benefit`) are not applied: pay items per employee are payroll's.
8. **ACC-11.** A scope rank (own 1, team 2, department / branch / selected_units 3, company 4) compares what is
   given with what the actor holds. Checked when ticking a role (new or widened ticks only), giving roles to a
   user, creating a user with roles, and personal grants. Nobody changes their own roles or grants, or switches
   off / demotes themselves; only a system administrator creates, edits, resets or signs out a system
   administrator. Companies can be given only among those the actor reaches.
9. **ACC-15.** Role create / rename / ticks / copy / retire / delete, user create / edit / role add and remove /
   password reset / grants / sessions ended are written to `core.audit_log` (entity `auth.role`,
   `auth.user_account`) with the company.
10. **Default roles cannot be deleted**, only retired (the next release would re-create them by code).
11. **Personal grants** do not offer `selected_units` (the ERD has no units per override; `fn_visible_employees`
    reads units from `role_permission_unit` only).
12. **Week start** values follow the frontend (monday, saturday, sunday); **date formats** likewise.
    Time zones are checked by pattern (IANA name); the server has no tz database (`tzdata` not installed).
13. **New company defaults**: employment types Permanent, Contractual, Daily Wager, Management Trainee (ERD note)
    are added once at creation; nothing is re-added by later seeds.
14. **Inbox permission**: `inbox.notifications.view` guards the user's own inbox (all default roles hold it).
15. **Dashboards** follow scope: a Department Head's HR dashboard counts their department; the Employee role's
    `*.view own` grant makes the HR / CEO dashboards show only themselves.

## Cross-module needs (recorded, not done here)

- **Requests**: call `hr.usp_request_apply_promotion` / `_transfer` on final approval and
  `hr.usp_request_revert_promotion` / `_transfer` on cancelling an approved one (same three parameters). Use
  `GET /api/employees/lookup?permission=<your create code>` for "Select Employee". Add notifications with
  `core.usp_notification_add` (to a user) or `core.usp_notification_add_employee` (to an employee's accounts).
- **Payroll**: the Salary Revision screen can write `hr.employee_salary` through `hr.usp_employee_salary_save`
  (it validates scope against `employees.salary.edit`; payroll may prefer its own procedure on the same table).
- **Separation**: rehire adds a period through `hr.usp_employment_period_save`; leaving sets status `left`.
- **Shared `app/core/default_roles.py`** (owner of shared files): the Employee role's `*.create own` pattern gives
  `employees.directory.create` (harmless: the procedure refuses anyone outside the caller's scope, but the
  frontend would show an Add button); and the Line Manager / Department Head / Executive `*.view` patterns give
  `employees.salary.view`, `employees.bank_accounts.view`, `employees.identity.view` to their scope. Suggest
  excluding `employees.directory.create` from Employee and `employees.salary.*`, `employees.bank_accounts.*`,
  `employees.identity.*` from Line Manager, Department Head and Executive until OQ E6 is answered.
- **Auth ERD (`03-auth.md`)**: `user_permission_override` has no `company_id`, so a personal grant applies in
  every company the user reaches; suggest adding it. `auth.usp_session_create` stamps `last_login_at`, which
  changes the user's rowVersion, so an admin's open edit form conflicts after the user signs in.
- **Requirements**: add `tzdata` to the backend requirements if strict time-zone validation is wanted.

## Not in this build

Subscriptions, Help & Support (no design, no tables); geocoder search; employee documents, experience,
agreement, contract (file storage); employee self-service edits of own profile or bank details (no rule in the
documents; HR edits them); messages / chat (out of scope, SRS 8); dashboard widgets listed above as not built;
saved filter presets (ORG-4, `core.filter_preset`; a shared mechanism for every list, not one module's);
list exports (the `export` codes exist for the frontend's own export).
