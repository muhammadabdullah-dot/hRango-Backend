# HRango — ERD (SQL Server, first build)

Generated from `erd/source/*.md` by `erd/build.py`. Edit the source, not this file.

## Conventions

- **Database:** SQL Server from day one. One database for now; every business table carries `company_id`.
- **Schemas:** one SQL Server schema per module (table below). The same name is the backend module.
- **Keys:** `id BIGINT IDENTITY(1,1)` primary key. Link tables (no `id`) use the pair of foreign keys as the primary key.
- **Foreign keys:** `ON DELETE NO ACTION` everywhere (SQL Server rejects multiple cascade paths). Deleting is done by the service layer.
- **Every table also has:** `created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()`, `created_by BIGINT NULL`, `updated_at DATETIME2(0) NULL`, `updated_by BIGINT NULL`, `row_version ROWVERSION` (stops two people overwriting each other).
- **Text:** `NVARCHAR` (Urdu names work). Enum-like values are `NVARCHAR(30)` holding a code; the allowed codes live in the backend.
- **Money:** `DECIMAL(18,2)`. Leave days: `DECIMAL(6,2)` (half days).
- **Time:** audit columns and system stamps are UTC. Attendance and scheduling times (punches, shifts, time-sheet days) are the company's local wall-clock time, as biometric devices report them. `DATE` and `TIME` columns are local business dates.
- **NN** = NOT NULL. Everything else is nullable. `BIT` columns are `NOT NULL DEFAULT 0`.
- Reserved words avoided: `user` → `user_account`, `file` → `stored_file`, `order` → `sort_order`, `key`/`value` → `setting_key`/`setting_value`, `group` → `status_group`, `view` → `list_view`, `list` → `task_list`.

## Modules, schemas and backend layers

Each module gets one file per layer: `app/routers/<module>.py`, `app/controllers/<module>_controller.py`, `app/services/<module>_service.py`, `app/repos/<module>_repo.py`, `app/schemas/<module>.py`. Data access goes through stored procedures in `db/procedures/<schema>/`. The tables come from `db/migrations/0001_baseline.sql`, generated from this ERD.

| # | Module | SQL schema | Backend module | Tables |
|---|---|---|---|---|
| 1 | Organisation | `org` | `organisation` | 16 |
| 2 | Employee | `hr` | `employees` | 15 |
| 3 | Users and access | `auth` | `access` | 10 |
| 4 | Shifts and scheduling | `sch` | `scheduling` | 14 |
| 5 | Attendance | `att` | `attendance` | 12 |
| 6 | Leave | `lv` | `leave` | 9 |
| 7 | Requests and approvals | `req` | `requests` | 33 |
| 8 | Loans | `loan` | `loans` | 5 |
| 9 | Payroll | `pay` | `payroll` | 22 |
| 10 | Assets and separation | `sep` | `separation` | 10 |
| 11 | Recruitment | `rec` | `recruitment` | 9 |
| 12 | Manpower planning | `mp` | `manpower` | 7 |
| 13 | Shared | `core` | `core` | 10 |
| 14 | Engagement | `eng` | `engagement` | 16 |
| 15 | Project and task management | `pm` | `projects` | 31 |
| 16 | Warnings | `att` | `attendance` | 4 |
| 17 | Benefits | `ben` | `benefits` | 10 |
| 18 | Performance | `perf` | `performance` | 11 |
| 19 | Training | `trn` | `training` | 6 |
| | **Total** | | | **250** |

---

## 1. Organisation  (`org`)

```
org.company    -- one legal entity; a customer database holds several (e.g. a Pakistani company and a Dubai FZ-LLC)
  id                        BIGINT IDENTITY   NN  PK
  name                      NVARCHAR(200)     NN    -- organisation name shown in the app (General Settings)
  legal_name                NVARCHAR(200)    -- registered name
  logo_file_id              BIGINT                    FK → core.stored_file
  email                     NVARCHAR(254)
  phone                     NVARCHAR(30)
  website                   NVARCHAR(200)
  address                   NVARCHAR(500)
  country_id                BIGINT                    FK → org.country    -- optional: where the company is registered
  currency                  CHAR(3)    -- ISO 4217; PKR for a Pakistani company, AED for a UAE one
  timezone                  NVARCHAR(64)    -- IANA name; Asia/Karachi, Asia/Dubai
  date_format               NVARCHAR(200)    -- dd/MM/yyyy, MM/dd/yyyy, yyyy-MM-dd, dd MMM yyyy
  week_start_day            NVARCHAR(30)    -- monday, saturday, sunday
  fiscal_year_start_month   INT    -- 1 to 12; 7 (July) in Pakistan
  is_active                 BIT               NN
  UNIQUE (name)
```

```
org.country    -- ISO 3166-1
  id         BIGINT IDENTITY   NN  PK
  name       NVARCHAR(200)     NN
  iso_code   CHAR(2)           NN
  UNIQUE (iso_code)
```

```
org.state    -- province, emirate or territory; code is the ISO 3166-2 subdivision code
  id           BIGINT IDENTITY   NN  PK
  country_id   BIGINT            NN      FK → org.country
  code         NVARCHAR(30)      NN
  name         NVARCHAR(200)     NN
  UNIQUE (code)
```

```
org.city
  id         BIGINT IDENTITY   NN  PK
  state_id   BIGINT            NN      FK → org.state
  name       NVARCHAR(200)     NN
  UNIQUE (state_id, name)
```

```
org.location
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  name              NVARCHAR(200)     NN
  employee_prefix   NVARCHAR(10)
  description       NVARCHAR(MAX)
  latitude          DECIMAL(9,6)
  longitude         DECIMAL(9,6)
  UNIQUE (company_id, name)
```

```
org.area    -- part of a location
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  location_id   BIGINT            NN      FK → org.location
  name          NVARCHAR(200)     NN
  description   NVARCHAR(MAX)
  UNIQUE (location_id, name)
```

```
org.branch
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  location_id       BIGINT            NN      FK → org.location
  area_id           BIGINT                    FK → org.area    -- optional
  name              NVARCHAR(200)     NN
  employee_prefix   NVARCHAR(10)
  description       NVARCHAR(MAX)
  manager_id        BIGINT                    FK → hr.employee
  country_id        BIGINT                    FK → org.country
  state_id          BIGINT                    FK → org.state
  city_id           BIGINT                    FK → org.city
  latitude          DECIMAL(9,6)
  longitude         DECIMAL(9,6)
  UNIQUE (company_id, name)
```

```
org.department
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  parent_id    BIGINT                    FK → org.department    -- sub-department
  name         NVARCHAR(200)     NN
  head_id      BIGINT                    FK → hr.employee    -- HOD
  UNIQUE (company_id, name)
```

```
org.division
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  UNIQUE (company_id, name)
```

```
org.cost_center
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  code         NVARCHAR(30)      NN
  name         NVARCHAR(200)     NN
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
org.designation
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  UNIQUE (company_id, name)
```

```
org.job_title
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  name               NVARCHAR(200)     NN
  limit_head_count   BIT               NN
  max_head_count     INT
  description        NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
org.grade    -- sort_order ranks grades, so a promotion can be told from a demotion
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  sort_order   INT
  UNIQUE (company_id, name)
```

```
org.job_level
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  sort_order   INT
  UNIQUE (company_id, name)
```

```
org.employee_group
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  UNIQUE (company_id, name)
```

```
org.employment_type    -- a new company starts with Permanent, Contractual, Daily Wager, Management Trainee
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  UNIQUE (company_id, name)
```

Relationships:
```
company     1──* location 1──* area
company     1──* branch   (branch sits in a location, optionally an area)
company     1──* department 1──* department (sub)
country     1──* state 1──* city
```

---

## 2. Employee  (`hr`)

```
hr.employee
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  code                   NVARCHAR(30)      NN    -- prefix from branch/location + number
  first_name             NVARCHAR(200)     NN
  last_name              NVARCHAR(200)     NN
  parent_name            NVARCHAR(200)
  gender                 NVARCHAR(30)
  marital_status         NVARCHAR(30)
  religion               NVARCHAR(50)
  nationality            NVARCHAR(50)
  date_of_birth          DATE
  cnic                   NVARCHAR(15)
  email                  NVARCHAR(254)
  phone_1                NVARCHAR(30)
  phone_2                NVARCHAR(30)
  home_address           NVARCHAR(500)    -- Personal tab / Benefits "Home Address"; changed by HR or an approved Update Information request
  home_city_id           BIGINT                    FK → org.city    -- optional
  photo_file_id          BIGINT                    FK → core.stored_file    -- profile photo (an image upload); responses give photoUrl, a signed link
  branch_id              BIGINT            NN      FK → org.branch
  location_id            BIGINT                    FK → org.location
  area_id                BIGINT                    FK → org.area
  department_id          BIGINT                    FK → org.department
  division_id            BIGINT                    FK → org.division
  cost_center_id         BIGINT                    FK → org.cost_center
  designation_id         BIGINT                    FK → org.designation
  job_title_id           BIGINT                    FK → org.job_title
  grade_id               BIGINT                    FK → org.grade
  job_level_id           BIGINT                    FK → org.job_level
  employee_group_id      BIGINT                    FK → org.employee_group
  employment_type_id     BIGINT                    FK → org.employment_type
  line_manager_id        BIGINT                    FK → hr.employee    -- no cycles: nobody manages their own manager
  final_authority_id     BIGINT                    FK → hr.employee
  default_time_slot_id   BIGINT                    FK → sch.time_slot
  status                 NVARCHAR(30)      NN    -- active, probation, notice, left, inactive (switched off by HR)
  salary_frequency       NVARCHAR(30)    -- monthly, daily, hourly
  UNIQUE (company_id, code)
  UNIQUE (company_id, cnic)
```

```
hr.employment_period    -- one row per joining; rehire adds a row
  id                     BIGINT IDENTITY   NN  PK
  employee_id            BIGINT            NN      FK → hr.employee
  joining_date           DATE              NN
  confirmation_date      DATE
  probation_end_date     DATE
  end_date               DATE
  end_of_employment_id   BIGINT                    FK → sep.end_of_employment
```

```
hr.employee_history    -- what changed and when: joining, transfer, promotion, demotion, edit
  id                   BIGINT IDENTITY   NN  PK
  employee_id          BIGINT            NN      FK → hr.employee
  change_type          NVARCHAR(30)      NN    -- joining, transfer, promotion, demotion, edit
  effective_date       DATE              NN
  location_id          BIGINT                    FK → org.location
  branch_id            BIGINT                    FK → org.branch
  department_id        BIGINT                    FK → org.department
  designation_id       BIGINT                    FK → org.designation
  job_title_id         BIGINT                    FK → org.job_title
  grade_id             BIGINT                    FK → org.grade
  job_level_id         BIGINT                    FK → org.job_level
  line_manager_id      BIGINT                    FK → hr.employee
  final_authority_id   BIGINT                    FK → hr.employee
  source_request_id    BIGINT                    FK → req.request
  previous_values      NVARCHAR(MAX)    -- JSON of the placement before this change; a cancelled request puts it back
  is_reverted          BIT               NN    -- set when the request behind it is cancelled after approval
```

```
hr.employee_salary    -- salary over time; the Salary Revision screen lists this
  id                  BIGINT IDENTITY   NN  PK
  employee_id         BIGINT            NN      FK → hr.employee
  effective_date      DATE              NN
  amount              DECIMAL(18,2)     NN
  previous_amount     DECIMAL(18,2)
  change_type         NVARCHAR(30)    -- flat, percent
  change_value        DECIMAL(18,2)
  source              NVARCHAR(30)    -- joining, revision, promotion, import
  source_request_id   BIGINT                    FK → req.request
  remarks             NVARCHAR(MAX)
```

```
hr.employee_pay_item    -- fixed allowances / deductions per person
  id               BIGINT IDENTITY   NN  PK
  employee_id      BIGINT            NN      FK → hr.employee
  pay_item_id      BIGINT                    FK → pay.pay_item
  amount           DECIMAL(18,2)
  effective_date   DATE
```

```
hr.employee_bank_account    -- sensitive (employees.bank_accounts)
  id               BIGINT IDENTITY   NN  PK
  employee_id      BIGINT            NN      FK → hr.employee
  account_holder   NVARCHAR(200)
  account_number   NVARCHAR(50)      NN
  bank_name        NVARCHAR(200)     NN
  branch_name      NVARCHAR(200)
  branch_code      NVARCHAR(30)
  tax_payer_id     NVARCHAR(30)
  is_primary       BIT               NN
  UNIQUE (employee_id, account_number)
```

```
hr.employee_document    -- Documents tab (SRS EMP-3, APP Documents): CNIC copy, degree, letters
  id                   BIGINT IDENTITY   NN  PK
  employee_id          BIGINT            NN      FK → hr.employee
  document_type        NVARCHAR(30)      NN    -- cnic, passport, driving_licence (identity: employees.identity too);
  title                NVARCHAR(200)
  document_number      NVARCHAR(100)
  issue_date           DATE
  expiry_date          DATE
  file_id              BIGINT            NN      FK → core.stored_file
  remarks              NVARCHAR(MAX)
  expiry_notified_at   DATETIME2(0)    -- set when the employee was told it expires soon (hr.usp_employee_document_expiry_notify)
```

```
hr.employee_experience    -- Professional experience: Company Name, Job Title, From / To (to empty = present)
  id             BIGINT IDENTITY   NN  PK
  employee_id    BIGINT            NN      FK → hr.employee
  company_name   NVARCHAR(200)     NN
  role_title     NVARCHAR(100)     NN
  from_date      DATE              NN
  to_date        DATE
```

```
hr.employee_agreement
  id            BIGINT IDENTITY   NN  PK
  employee_id   BIGINT            NN      FK → hr.employee
  file_id       BIGINT                    FK → core.stored_file
  accepted_at   DATETIME2(0)
```

```
hr.employee_emergency_contact    -- Emergency Contact # on the Personal tab is the primary contact's phone
  id            BIGINT IDENTITY   NN  PK
  employee_id   BIGINT            NN      FK → hr.employee
  name          NVARCHAR(200)     NN
  relation      NVARCHAR(30)      NN
  phone         NVARCHAR(30)      NN
  alt_phone     NVARCHAR(30)
  address       NVARCHAR(500)
  is_primary    BIT               NN
```

```
hr.employee_dependent    -- Dependents tab: First Name, Last Name, Relation, Occupation
  id              BIGINT IDENTITY   NN  PK
  employee_id     BIGINT            NN      FK → hr.employee
  first_name      NVARCHAR(200)     NN
  last_name       NVARCHAR(200)
  relation        NVARCHAR(30)      NN    -- spouse, son, daughter, father, mother, brother, sister, other
  occupation      NVARCHAR(200)
  date_of_birth   DATE
```

```
hr.employee_skill    -- Skills tab: Skill Title, Skill Level
  id            BIGINT IDENTITY   NN  PK
  employee_id   BIGINT            NN      FK → hr.employee
  skill_title   NVARCHAR(200)     NN
  skill_level   NVARCHAR(30)      NN    -- beginner, intermediate, advanced, expert
  UNIQUE (employee_id, skill_title)
```

```
hr.employee_education    -- Add Academic: Academic Title, Institute, From / To, In Process, document
  id              BIGINT IDENTITY   NN  PK
  employee_id     BIGINT            NN      FK → hr.employee
  title           NVARCHAR(200)     NN
  institute       NVARCHAR(200)     NN
  from_date       DATE
  to_date         DATE
  is_in_process   BIT               NN
  file_id         BIGINT                    FK → core.stored_file
```

```
hr.employee_contract    -- Add Contract: Contract Type, Duration in Months (or Custom), From / To, attachment.
  id                BIGINT IDENTITY   NN  PK
  employee_id       BIGINT            NN      FK → hr.employee
  contract_type     NVARCHAR(30)      NN    -- permanent, temporary, contractual, probation, internship, consultant
  duration_months   INT    -- empty = custom dates
  from_date         DATE              NN
  to_date           DATE
  file_id           BIGINT                    FK → core.stored_file
  remarks           NVARCHAR(MAX)
```

```
hr.employee_change_request    -- "Update Information": an employee asks, HR approves; approval writes hr.employee
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  employee_id          BIGINT            NN      FK → hr.employee
  status               NVARCHAR(30)      NN    -- pending, approved, rejected, cancelled
  changes              NVARCHAR(MAX)     NN    -- JSON of the asked values (snake_case keys): date_of_birth, marital_status,
  previous_values      NVARCHAR(MAX)    -- JSON of the same fields when asked
  remarks              NVARCHAR(MAX)
  decided_by_user_id   BIGINT                    FK → auth.user_account
  decided_at           DATETIME2(0)
  decision_remarks     NVARCHAR(MAX)
```

Relationships:
```
employee 1──* employment_period / employee_history / employee_salary
employee 1──* employee_bank_account / employee_document / employee_experience
employee 1──* employee_emergency_contact / employee_dependent / employee_skill / employee_education
employee 1──* employee_contract / employee_change_request
employee 1──* employee (line manager → team)
```

---

## 3. Users and access  (`auth`)

```
auth.user_account
  id                BIGINT IDENTITY   NN  PK
  employee_id       BIGINT                    FK → hr.employee    -- optional: blank for system users
  company_id        BIGINT            NN      FK → org.company    -- home company: the one active after sign-in
  display_name      NVARCHAR(200)    -- used when there is no employee
  email             NVARCHAR(254)     NN
  password_hash     NVARCHAR(255)     NN
  is_active         BIT               NN
  is_system_admin   BIT               NN
  UNIQUE (email)
```

```
auth.permission    -- the catalogue: one row per view or button (module.screen.action)
  id             BIGINT IDENTITY   NN  PK
  code           NVARCHAR(150)     NN    -- leave.requests.approve
  module         NVARCHAR(30)      NN    -- leave
  screen         NVARCHAR(100)     NN    -- leave.requests
  action_code    NVARCHAR(50)      NN    -- view, create, edit, delete, approve, reject, export, import ...
  label          NVARCHAR(200)     NN
  hint           NVARCHAR(500)
  is_sensitive   BIT               NN    -- salary, bank, CNIC, loan and payslip figures
  sort_order     INT
  UNIQUE (code)
```

```
auth.role    -- per company; default roles are copied in when a company is created
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  code          NVARCHAR(30)      NN
  name          NVARCHAR(200)     NN
  description   NVARCHAR(MAX)
  is_system     BIT               NN
  is_active     BIT               NN
  UNIQUE (company_id, code)
```

```
auth.role_permission    -- one tick on the role screen
  role_id         BIGINT            NN  PK  FK → auth.role
  permission_id   BIGINT            NN  PK  FK → auth.permission
  scope           NVARCHAR(30)      NN
```

```
auth.role_permission_unit    -- when scope = selected_units
  id              BIGINT IDENTITY   NN  PK
  role_id         BIGINT            NN      FK → auth.role
  permission_id   BIGINT            NN      FK → auth.permission
  unit_type       NVARCHAR(30)      NN
  unit_id         BIGINT            NN
  UNIQUE (role_id, permission_id, unit_type, unit_id)
```

```
auth.role_default_offer    -- codes a default role has already been offered; one the customer removed is not offered again
  role_id         BIGINT            NN  PK  FK → auth.role
  permission_id   BIGINT            NN  PK  FK → auth.permission
```

```
auth.user_role
  user_account_id   BIGINT            NN  PK  FK → auth.user_account
  role_id           BIGINT            NN  PK  FK → auth.role
```

```
auth.user_permission_override    -- a grant or a denial for one person in one company; a denial wins
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  user_account_id   BIGINT            NN      FK → auth.user_account
  permission_id     BIGINT            NN      FK → auth.permission
  effect            NVARCHAR(30)      NN    -- grant, deny
  scope             NVARCHAR(30)    -- for grants
  reason            NVARCHAR(MAX)
  UNIQUE (company_id, user_account_id, permission_id)
```

```
auth.user_company    -- which companies a user may see
  user_account_id   BIGINT            NN  PK  FK → auth.user_account
  company_id        BIGINT            NN  PK  FK → org.company
```

```
auth.user_session    -- one sign-in; the token names it, so ending it signs that device out
  id                   BIGINT IDENTITY   NN  PK
  user_account_id      BIGINT            NN      FK → auth.user_account
  company_id           BIGINT            NN      FK → org.company
  refresh_token_hash   NVARCHAR(255)
  device               NVARCHAR(200)
  ip_address           NVARCHAR(45)
  last_seen_at         DATETIME2(0)
  expires_at           DATETIME2(0)
  revoked_at           DATETIME2(0)
```

Relationships:
```
user_account *──* role   (user_role)
permission 1──* role_permission *──1 role
role_permission 1──* role_permission_unit
user_account 1──* user_permission_override *──1 permission
user_account 1──* user_session
```

---

## 4. Shifts and scheduling  (`sch`)

```
sch.time_slot    -- a shift template (Attendance settings, Time Slots)
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  code               NVARCHAR(30)      NN    -- TS-00004, from core.number_sequence prefix TS-
  name               NVARCHAR(200)     NN
  color              NVARCHAR(20)
  start_time         TIME(0)           NN    -- local time; for a flexible slot the window the hours may fall in
  end_time           TIME(0)           NN    -- an end at or before the start ends the next day
  duration_minutes   INT               NN    -- end minus start, overnight counted into the next day
  workable_minutes   INT               NN    -- flexible: hours to work per day; fixed: duration minus breaks that are not inclusive
  is_flexible        BIT               NN
  is_overnight       BIT               NN
  full_overtime      BIT               NN
  short_overtime     BIT               NN
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
sch.break_type    -- Lunch, Prayer, Tea ...; identifiers are what a device or log sends
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  name               NVARCHAR(200)     NN
  start_identifier   NVARCHAR(50)      NN
  end_identifier     NVARCHAR(50)      NN
  UNIQUE (company_id, name)
```

```
sch.time_slot_break    -- the slot's planned breaks
  id              BIGINT IDENTITY   NN  PK
  time_slot_id    BIGINT            NN      FK → sch.time_slot
  break_type_id   BIGINT            NN      FK → sch.break_type
  start_time      TIME(0)           NN
  end_time        TIME(0)           NN
  is_inclusive    BIT               NN
```

```
sch.roster_group    -- a named weekly pattern employees are enrolled in for a period
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  title         NVARCHAR(200)     NN
  from_date     DATE              NN
  to_date       DATE    -- open-ended when blank
  description   NVARCHAR(MAX)
  is_active     BIT               NN
  UNIQUE (company_id, title)
```

```
sch.roster_group_day    -- one row per weekday of the pattern
  id                BIGINT IDENTITY   NN  PK
  roster_group_id   BIGINT            NN      FK → sch.roster_group
  weekday           TINYINT           NN    -- 1 = Monday ... 7 = Sunday
  is_day_off        BIT               NN
  time_slot_id      BIGINT                    FK → sch.time_slot    -- optional: blank on a day off
  UNIQUE (roster_group_id, weekday)
```

```
sch.roster_group_member    -- an enrolment; one roster per employee at a time
  id                BIGINT IDENTITY   NN  PK
  roster_group_id   BIGINT            NN      FK → sch.roster_group
  employee_id       BIGINT            NN      FK → hr.employee
  start_date        DATE              NN
  end_date          DATE    -- open-ended when blank; set when discontinued
```

```
sch.schedule_batch    -- one "Create Scheduling" or "Apply Default Shift" action
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  batch_kind           NVARCHAR(30)      NN    -- create, default_shift, import
  start_date           DATE              NN
  end_date             DATE              NN
  time_slot_id         BIGINT                    FK → sch.time_slot    -- optional: one slot for every day
  roster_group_id      BIGINT                    FK → sch.roster_group    -- optional: each weekday's slot from the roster pattern
  weekdays             NVARCHAR(30)    -- 1..7 comma separated; blank = every day
  repeat_every_weeks   INT               NN    -- 0 = never, 1..8
  step                 INT               NN    -- weeks on in each repeat cycle
  geo_fence_id         BIGINT                    FK → att.geo_fence    -- optional
  is_wfh               BIT               NN
```

```
sch.schedule    -- planned shift: one employee, one shift
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  employee_id         BIGINT            NN      FK → hr.employee
  work_date           DATE              NN    -- the business date the shift belongs to (its start)
  start_at            DATETIME2(0)      NN
  end_at              DATETIME2(0)      NN
  time_slot_id        BIGINT            NN      FK → sch.time_slot
  schedule_batch_id   BIGINT                    FK → sch.schedule_batch    -- optional
  geo_fence_id        BIGINT                    FK → att.geo_fence    -- optional
  is_wfh              BIT               NN
  planned_minutes     INT               NN    -- flexible: workable minutes; fixed: shift minus breaks that are not inclusive
  UNIQUE (employee_id, start_at)
```

```
sch.schedule_break
  id              BIGINT IDENTITY   NN  PK
  schedule_id     BIGINT            NN      FK → sch.schedule
  break_type_id   BIGINT            NN      FK → sch.break_type
  start_at        DATETIME2(0)      NN
  end_at          DATETIME2(0)      NN
  is_inclusive    BIT               NN
```

```
sch.rest_day_rule    -- "Create New Rest Day": employees, dates, repeat, step, weekdays, payable
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  from_date            DATE              NN
  to_date              DATE              NN
  weekdays             NVARCHAR(30)      NN    -- 1..7 comma separated (1 = Monday)
  repeat_every_weeks   INT               NN    -- 0 = every week in the range, 1..8 = every n weeks
  step                 INT               NN    -- weeks on in each repeat cycle
  is_payable           BIT               NN
```

```
sch.rest_day_rule_employee
  rest_day_rule_id   BIGINT            NN  PK  FK → sch.rest_day_rule
  employee_id        BIGINT            NN  PK  FK → hr.employee
```

```
sch.rest_day    -- each resulting rest day; wins over a shift on the same date
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  employee_id        BIGINT            NN      FK → hr.employee
  rest_date          DATE              NN
  is_payable         BIT               NN
  rest_day_rule_id   BIGINT                    FK → sch.rest_day_rule    -- optional: from a rule
  request_id         BIGINT                    FK → req.request    -- optional: from an approved rest-day request
  UNIQUE (employee_id, rest_date)
```

```
sch.holiday
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  name                NVARCHAR(200)     NN
  holiday_type        NVARCHAR(30)      NN    -- public, local
  start_date          DATE              NN
  end_date            DATE              NN
  description         NVARCHAR(MAX)
  attendance_exempt   BIT               NN    -- on: the day is a holiday in the time sheet; off: listed, still worked
  UNIQUE (company_id, name, start_date)
```

```
sch.holiday_rule    -- who the holiday applies to; no rules = everyone
  id            BIGINT IDENTITY   NN  PK
  holiday_id    BIGINT            NN      FK → sch.holiday
  rule_type     NVARCHAR(30)      NN    -- employee, org_structure, geo_location, religion
  employee_id   BIGINT                    FK → hr.employee    -- optional: rule_type employee
  location_id   BIGINT                    FK → org.location    -- optional: rule_type org_structure
  branch_id     BIGINT                    FK → org.branch    -- optional: rule_type org_structure
  country_id    BIGINT                    FK → org.country    -- optional: rule_type geo_location (employee's branch)
  state_id      BIGINT                    FK → org.state    -- optional: rule_type geo_location
  city_id       BIGINT                    FK → org.city    -- optional: rule_type geo_location
  religion      NVARCHAR(50)    -- rule_type religion
```

Relationships:
```
time_slot 1──* time_slot_break *──1 break_type
roster_group 1──* roster_group_day *──1 time_slot
roster_group 1──* roster_group_member *──1 employee
schedule_batch 1──* schedule 1──* schedule_break
employee 1──* schedule / rest_day
rest_day_rule 1──* rest_day
holiday 1──* holiday_rule
```

---

## 5. Attendance  (`att`)

```
att.device    -- biometric machine (ATT-1 to ATT-3); fingerprints stay on the device (NFR-10)
  id               BIGINT IDENTITY   NN  PK
  company_id       BIGINT            NN      FK → org.company
  code             NVARCHAR(30)      NN    -- MCH-00001, from core.number_sequence prefix MCH-
  name             NVARCHAR(200)     NN
  model            NVARCHAR(100)
  serial_no        NVARCHAR(50)
  ip_address       NVARCHAR(45)
  port             INT
  branch_id        BIGINT                    FK → org.branch    -- optional: where the machine stands
  address          NVARCHAR(500)    -- where the machine stands, as text
  status           NVARCHAR(30)      NN    -- active, inactive
  last_synced_at   DATETIME2(0)    -- last time punches arrived from it
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
att.device_enrolment    -- an employee's user number on a machine
  device_id        BIGINT            NN  PK  FK → att.device
  employee_id      BIGINT            NN  PK  FK → hr.employee
  device_user_no   NVARCHAR(30)      NN
  UNIQUE (device_id, device_user_no)
```

```
att.geo_fence    -- where web and mobile punches are allowed (ATT-6); Scheduling offers the ones marked for shifts
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  code                NVARCHAR(30)      NN    -- GF-00001, from core.number_sequence prefix GF-
  name                NVARCHAR(200)     NN
  shape               NVARCHAR(30)      NN    -- circle, polygon
  center_lat          DECIMAL(9,6)
  center_lng          DECIMAL(9,6)
  radius_m            INT
  polygon_points      NVARCHAR(MAX)    -- polygon: JSON list of lat and lng points, at least 3
  applies_to_all      BIT               NN    -- on: everyone; off: the employees the targets select
  joining_from_date   DATE
  joining_to_date     DATE
  is_for_shift        BIT               NN    -- "For Shift": offered when scheduling shifts
  is_active           BIT               NN
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
att.geo_fence_target    -- who the fence applies to: one value per row; rows of one type are OR, types are AND
  id             BIGINT IDENTITY   NN  PK
  geo_fence_id   BIGINT            NN      FK → att.geo_fence
  target_type    NVARCHAR(30)      NN    -- employee, country, location, branch, area, department, designation, grade, job_title, religion, nationality
  target_id      BIGINT    -- the id, for every type except religion and nationality
  target_value   NVARCHAR(200)    -- religion, nationality
```

```
att.ip_restriction    -- addresses web and mobile punches must come from (ATT-6)
  id               BIGINT IDENTITY   NN  PK
  company_id       BIGINT            NN      FK → org.company
  code             NVARCHAR(30)      NN    -- IPR-00001, from core.number_sequence prefix IPR-
  ipv4             NVARCHAR(45)
  ipv6             NVARCHAR(45)
  netmask          NVARCHAR(45)    -- subnet mask for ipv4, e.g. 255.255.255.0
  range_start      NVARCHAR(45)
  range_end        NVARCHAR(45)
  applies_to_all   BIT               NN    -- on: everyone; off: the employees the targets select
  is_active        BIT               NN
  UNIQUE (company_id, code)
```

```
att.ip_restriction_target    -- who the restriction applies to; same rules as geo_fence_target
  id                  BIGINT IDENTITY   NN  PK
  ip_restriction_id   BIGINT            NN      FK → att.ip_restriction
  target_type         NVARCHAR(30)      NN    -- employee, country, location, branch, area, department, designation, grade, job_title, religion, nationality
  target_id           BIGINT
  target_value        NVARCHAR(200)
```

```
att.punch    -- every raw clock event
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  employee_id           BIGINT            NN      FK → hr.employee
  punched_at            DATETIME2(0)      NN    -- local wall-clock time
  punch_type            NVARCHAR(30)      NN    -- check_in, check_out, break_out, break_in
  break_type_id         BIGINT                    FK → sch.break_type
  source                NVARCHAR(30)      NN    -- biometric, mobile, web, manual, import_file, punch_request
  device_id             BIGINT                    FK → att.device
  latitude              DECIMAL(9,6)
  longitude             DECIMAL(9,6)
  ip_address            NVARCHAR(45)
  photo_file_id         BIGINT                    FK → core.stored_file    -- "Take Picture For Attendance For Dashboard"
  request_id            BIGINT                    FK → req.request    -- when it came from an approved punch request
  remarks               NVARCHAR(MAX)
  is_manually_updated   BIT               NN    -- a manual or imported punch changed after it was entered
  is_ignored            BIT               NN    -- left out of the time sheet (a device punch cannot be edited, only ignored)
  UNIQUE (employee_id, punched_at, punch_type)
```

```
att.timesheet_day    -- computed result for one employee, one day
  id                          BIGINT IDENTITY   NN  PK
  company_id                  BIGINT            NN      FK → org.company
  employee_id                 BIGINT            NN      FK → hr.employee
  work_date                   DATE              NN
  schedule_id                 BIGINT                    FK → sch.schedule    -- the first shift of the day; several shifts are one day from first start to last end
  expected_in                 DATETIME2(0)
  expected_out                DATETIME2(0)
  expected_minutes            INT    -- planned minutes of the day's shifts
  first_in                    DATETIME2(0)
  last_out                    DATETIME2(0)
  worked_minutes              INT
  break_minutes               INT
  shift_worked_minutes        INT
  late_minutes                INT
  early_left_minutes          INT
  overtime_before_minutes     INT
  overtime_after_minutes      INT
  approved_overtime_minutes   INT    -- from approved overtime requests, or the computed overtime when approval is not required
  grace_consumed_minutes      INT
  day_status                  NVARCHAR(30)      NN    -- present, absent, holiday, weekend, rest_day, leave, half_day, short_day, wfh, official_visit, sandwich, yet_to_start
  marked_status               NVARCHAR(30)    -- what HR marked on the day: absent, half_day, short_day
  leave_request_id            BIGINT                    FK → req.request    -- the approved leave covering the day
  is_manually_updated         BIT               NN    -- HR edited the day; processing keeps the edited times unless told to overwrite
  comments                    NVARCHAR(MAX)
  processed_at                DATETIME2(0)
  is_frozen                   BIT               NN    -- locked once payroll has used it; processing and edits leave it alone
  UNIQUE (employee_id, work_date)
```

```
att.timesheet_flag    -- several per day: late, early, grace, overtime, missing_punch, relaxation, official_visit, half_leave, short_leave
  id                 BIGINT IDENTITY   NN  PK
  timesheet_day_id   BIGINT            NN      FK → att.timesheet_day
  flag               NVARCHAR(30)      NN
  minutes            INT
```

```
att.timesheet_break    -- breaks taken on the day, from punches or entered by HR
  id                 BIGINT IDENTITY   NN  PK
  timesheet_day_id   BIGINT            NN      FK → att.timesheet_day
  break_type_id      BIGINT                    FK → sch.break_type
  out_at             DATETIME2(0)      NN
  in_at              DATETIME2(0)
  minutes            INT
```

```
att.overtime_policy    -- how overtime minutes convert to leave or a day (design: Overtime Policy)
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  name          NVARCHAR(200)     NN
  period        NVARCHAR(30)      NN    -- daily, monthly
  description   NVARCHAR(MAX)
  is_active     BIT               NN
  UNIQUE (company_id, name)
```

```
att.overtime_policy_slab
  id                   BIGINT IDENTITY   NN  PK
  overtime_policy_id   BIGINT            NN      FK → att.overtime_policy
  min_minutes          INT               NN
  max_minutes          INT               NN
  encashment_type      NVARCHAR(30)      NN    -- full_day, leave
  leave_type_id        BIGINT                    FK → lv.leave_type    -- when encashment_type is leave
```

Relationships:
```
device 1──* punch *──1 employee
device 1──* device_enrolment *──1 employee
employee 1──* timesheet_day 1──* timesheet_flag / timesheet_break
timesheet_day *──1 schedule
geo_fence 1──* geo_fence_target
ip_restriction 1──* ip_restriction_target
overtime_policy 1──* overtime_policy_slab
```

---

## 6. Leave  (`lv`)

```
lv.leave_type    -- Settings -> Leave Types ("Add Leave Types")
  id                                BIGINT IDENTITY   NN  PK
  company_id                        BIGINT            NN      FK → org.company
  title                             NVARCHAR(200)     NN
  short_code                        NVARCHAR(10)
  allowance                         DECIMAL(6,2)    -- No of Leaves Allowed, per tenure
  is_active                         BIT               NN
  is_probation_type                 BIT               NN
  auto_allotment                    BIT               NN
  auto_balance_on_joining           BIT               NN
  is_composite                      BIT               NN
  is_short_leave                    BIT               NN
  show_in_payslip                   BIT               NN
  is_deductible                     BIT               NN
  is_sandwich                       BIT               NN
  sandwich_across_types             BIT               NN
  is_earned                         BIT               NN
  allow_back_date                   BIT               NN
  back_date_limit_days              INT
  has_future_limit                  BIT               NN
  future_limit_days                 INT
  attachment_required               BIT               NN
  attachment_rule                   NVARCHAR(30)    -- refuse, note (Do When Attachment is Required)
  allow_encashment                  BIT               NN
  encashment_min                    DECIMAL(6,2)
  encashment_max                    DECIMAL(6,2)
  carry_forward                     BIT               NN
  pro_rated                         BIT               NN
  gender                            NVARCHAR(30)      NN    -- any, male, female
  marital_status                    NVARCHAR(30)      NN    -- any, single, married
  allowed_in_probation              BIT               NN
  min_experience_months             INT
  max_applications                  INT
  gap_between_applications_months   INT
  tenure                            NVARCHAR(30)      NN    -- yearly, monthly, employment
  balance_basis                     NVARCHAR(30)      NN    -- flat, experience
  accumulative_count                INT    -- tenures unused days may pile up over; NULL = no cap
  UNIQUE (company_id, short_code)
  UNIQUE (company_id, title)
```

```
lv.leave_type_experience_slab    -- Balance According to = Experience
  id              BIGINT IDENTITY   NN  PK
  leave_type_id   BIGINT            NN      FK → lv.leave_type
  min_months      INT               NN
  max_months      INT
  balance         DECIMAL(6,2)      NN
```

```
lv.leave_type_short_slab    -- with Short Leave
  id              BIGINT IDENTITY   NN  PK
  leave_type_id   BIGINT            NN      FK → lv.leave_type
  name            NVARCHAR(200)     NN
  balance         DECIMAL(6,2)
  value_type      NVARCHAR(30)      NN
  slab_value      DECIMAL(9,2)
```

```
lv.leave_policy    -- Settings -> Leave Policies
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  title               NVARCHAR(200)     NN
  policy_kind         NVARCHAR(30)      NN    -- distribution, half_short
  policy_level        NVARCHAR(30)      NN    -- company (everyone), employee (the enrolled)
  allow_half_day      BIT               NN
  allow_short_leave   BIT               NN
  is_active           BIT               NN
  UNIQUE (company_id, title)
```

```
lv.leave_policy_type    -- the types a distribution policy gives, with its own allowance
  leave_policy_id   BIGINT            NN  PK  FK → lv.leave_policy
  leave_type_id     BIGINT            NN  PK  FK → lv.leave_type
  allowance         DECIMAL(6,2)
```

```
lv.leave_policy_employee    -- enrolment in an employee-level policy
  leave_policy_id   BIGINT            NN  PK  FK → lv.leave_policy
  employee_id       BIGINT            NN  PK  FK → hr.employee
```

```
lv.leave_ledger    -- every change to a balance; balance = sum
  id                    BIGINT IDENTITY   NN  PK
  employee_id           BIGINT            NN      FK → hr.employee
  leave_type_id         BIGINT            NN      FK → lv.leave_type
  fiscal_year           SMALLINT          NN    -- leave year (year the company fiscal year starts in)
  entry_date            DATE              NN
  days                  DECIMAL(6,2)      NN    -- + credit, − debit
  reason                NVARCHAR(30)    -- opening, allotment, earned, carry_forward, adjustment, overtime, availed, encashed, penalty, restored
  remarks               NVARCHAR(MAX)
  request_id            BIGINT                    FK → req.request    -- optional; availed and restored postings
  leave_encashment_id   BIGINT                    FK → lv.leave_encashment
  warning_id            BIGINT                    FK → att.warning    -- optional; penalty postings
```

```
lv.leave_encashment    -- Payroll -> Leave Encashment (one run for a type and year)
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  leave_type_id      BIGINT            NN      FK → lv.leave_type
  fiscal_year        SMALLINT          NN
  encashment_date    DATE              NN
  applies_to_all     BIT               NN
  basis              NVARCHAR(30)      NN    -- overtime, earned_salary, per_hour_rate, overnight
  amount_per_leave   DECIMAL(18,2)     NN
  mode               NVARCHAR(30)      NN    -- payroll, manual
```

```
lv.leave_encashment_employee
  id                    BIGINT IDENTITY   NN  PK
  leave_encashment_id   BIGINT            NN      FK → lv.leave_encashment
  employee_id           BIGINT            NN      FK → hr.employee
  days                  DECIMAL(6,2)      NN
  amount                DECIMAL(18,2)     NN
  payslip_id            BIGINT                    FK → pay.payslip
  UNIQUE (leave_encashment_id, employee_id)
```

Relationships:
```
leave_type 1──* leave_type_experience_slab / leave_type_short_slab
leave_policy *──* leave_type / employee
employee 1──* leave_ledger *──1 leave_type
leave_encashment 1──* leave_encashment_employee
leave_ledger *──1 request / leave_encashment / warning   (what posted it)
```

---

## 7. Requests and approvals  (`req`)

```
req.request_type    -- the fixed list of request types (reference data, every company); see comparison/04-requests.md
  id              BIGINT IDENTITY   NN  PK
  code            NVARCHAR(30)      NN    -- leave, punch, relaxation, official_visit, work_from_home, overtime, rest_day, shift_swap, promotion, transfer, resignation, loan, travel, expense, air_ticket, requisition, task_extension
  name            NVARCHAR(200)     NN
  kind            NVARCHAR(30)      NN    -- detail table req_<kind> and effect <schema>.usp_request_apply_<kind>
  prefix          NVARCHAR(10)    -- request code prefix: RQ-<prefix>-0001
  is_admin_only   BIT               NN    -- filed by HR for an employee, never for oneself (promotion, transfer)
  is_active       BIT               NN
  sort_order      INT
  UNIQUE (code)
```

```
req.request    -- shared header for every request
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  code                  NVARCHAR(30)      NN    -- RQ-LV-0001
  request_type_id       BIGINT            NN      FK → req.request_type
  employee_id           BIGINT            NN      FK → hr.employee    -- who it is for
  created_by_user_id    BIGINT                    FK → auth.user_account
  from_date             DATE
  to_date               DATE
  days                  DECIMAL(6,2)    -- the Count column: days (leave, WFH, rest days) or 1
  reason                NVARCHAR(MAX)
  description           NVARCHAR(MAX)
  application           NVARCHAR(MAX)    -- the application text (written by hand or generated)
  status                NVARCHAR(30)      NN    -- pending, approved, rejected, cancelling, cancelled
  approval_flow_id      BIGINT                    FK → req.approval_flow    -- the flow (version) the request is walking now; cancellation flow while cancelling
  current_node_id       BIGINT                    FK → req.approval_node
  submitted_at          DATETIME2(0)
  decided_at            DATETIME2(0)
  cancel_reason         NVARCHAR(MAX)
  cancel_requested_at   DATETIME2(0)
  is_deleted            BIT               NN    -- deleted by the requester before anyone acted (kept for audit)
  UNIQUE (company_id, code)
```

```
req.request_day    -- each day a multi-day request covers (leave, work from home, rest days)
  id             BIGINT IDENTITY   NN  PK
  request_id     BIGINT            NN      FK → req.request
  request_date   DATE              NN
  schedule_id    BIGINT                    FK → sch.schedule
  UNIQUE (request_id, request_date)
```

```
req.req_leave
  request_id         BIGINT            NN  PK  FK → req.request
  leave_type_id      BIGINT            NN  PK  FK → lv.leave_type
  is_short           BIT               NN
  short_leave_type   NVARCHAR(30)
  start_time         TIME(0)
  end_time           TIME(0)
  days               DECIMAL(6,2)
```

```
req.req_punch
  request_id   BIGINT            NN  PK  FK → req.request
  punch_date   DATE              NN
  punch_type   NVARCHAR(30)      NN
  punch_time   TIME(0)           NN
```

```
req.req_time_window
  request_id         BIGINT            NN  PK  FK → req.request
  kind               NVARCHAR(30)      NN
  window_date        DATE              NN
  start_time         TIME(0)           NN
  end_time           TIME(0)           NN
  time_slot_id       BIGINT                PK  FK → sch.time_slot
  duration_minutes   INT
```

```
req.req_rest_day
  request_id        BIGINT            NN  PK  FK → req.request
  department_id     BIGINT            NN  PK  FK → org.department
  roster_group_id   BIGINT            NN  PK  FK → sch.roster_group
  is_payable        BIT               NN
```

```
req.req_overtime
  request_id         BIGINT            NN  PK  FK → req.request
  department_id      BIGINT            NN  PK  FK → org.department
  location_id        BIGINT                PK  FK → org.location
  branch_id          BIGINT                PK  FK → org.branch
  overtime_date      DATE              NN
  start_time         TIME(0)           NN
  end_time           TIME(0)           NN
  applied_minutes    INT               NN
  approved_minutes   INT
```

```
req.req_loan
  request_id         BIGINT            NN  PK  FK → req.request
  loan_type_id       BIGINT            NN  PK  FK → loan.loan_type
  loan_category_id   BIGINT                PK  FK → loan.loan_category
  amount_requested   DECIMAL(18,2)     NN
  required_date      DATE              NN
  extension_no       NVARCHAR(20)
  approved_amount    DECIMAL(18,2)
  currency           CHAR(3)
  payment_method     NVARCHAR(30)
  repayment_date     DATE
```

```
req.req_travel
  request_id         BIGINT            NN  PK  FK → req.request
  purpose            NVARCHAR(500)     NN
  extension_no       NVARCHAR(20)
  alt_phone          NVARCHAR(30)
  advance_required   BIT               NN
```

```
req.req_promotion
  request_id        BIGINT            NN  PK  FK → req.request
  is_demotion       BIT               NN
  grade_id          BIGINT            NN  PK  FK → org.grade
  job_level_id      BIGINT                PK  FK → org.job_level
  designation_id    BIGINT            NN  PK  FK → org.designation
  job_title_id      BIGINT            NN  PK  FK → org.job_title
  previous_salary   DECIMAL(18,2)
  new_salary        DECIMAL(18,2)     NN
  effective_date    DATE              NN
```

```
req.req_transfer
  request_id           BIGINT            NN  PK  FK → req.request
  location_id          BIGINT            NN  PK  FK → org.location
  branch_id            BIGINT            NN  PK  FK → org.branch
  department_id        BIGINT            NN  PK  FK → org.department
  line_manager_id      BIGINT            NN  PK  FK → hr.employee
  final_authority_id   BIGINT            NN  PK  FK → hr.employee
  effective_date       DATE              NN
```

```
req.req_resignation
  request_id           BIGINT            NN  PK  FK → req.request
  resignation_type     NVARCHAR(30)      NN
  resignation_date     DATE              NN
  last_working_date    DATE
  notice_period_days   INT
  serve_notice         BIT               NN
```

```
req.req_shift_swap
  request_id         BIGINT            NN  PK  FK → req.request
  shift_date         DATE              NN
  from_schedule_id   BIGINT                PK  FK → sch.schedule
  time_slot_id       BIGINT                PK  FK → sch.time_slot
  with_employee_id   BIGINT                PK  FK → hr.employee
  to_schedule_id     BIGINT                PK  FK → sch.schedule
```

```
req.loan_guarantor
  id             BIGINT IDENTITY   NN  PK
  request_id     BIGINT            NN      FK → req.request
  name           NVARCHAR(200)     NN
  cnic           NVARCHAR(15)      NN
  known_since    DATE              NN
  relationship   NVARCHAR(200)     NN
  extension_no   NVARCHAR(20)
  description    NVARCHAR(MAX)
  file_id        BIGINT                    FK → core.stored_file
```

```
req.travel_advance
  id           BIGINT IDENTITY   NN  PK
  request_id   BIGINT            NN      FK → req.request
  amount       DECIMAL(18,2)     NN
  currency     CHAR(3)           NN
```

```
req.travel_leg
  id              BIGINT IDENTITY   NN  PK
  request_id      BIGINT            NN      FK → req.request
  travel_type     NVARCHAR(30)      NN
  from_place      NVARCHAR(200)     NN
  to_place        NVARCHAR(200)     NN
  travel_mode     NVARCHAR(30)      NN
  distance_km     DECIMAL(9,2)
  depart_at       DATETIME2(0)      NN
  arrive_at       DATETIME2(0)      NN
  stay_required   BIT               NN
```

```
req.travel_stay
  id           BIGINT IDENTITY   NN  PK
  request_id   BIGINT            NN      FK → req.request
  stay_type    NVARCHAR(30)      NN
  address      NVARCHAR(500)     NN
  city         NVARCHAR(200)     NN
  from_date    DATE              NN
  to_date      DATE              NN
  nights       INT               NN
  phone        NVARCHAR(30)      NN
  email        NVARCHAR(254)     NN
```

```
req.travel_ticket
  id             BIGINT IDENTITY   NN  PK
  request_id     BIGINT            NN      FK → req.request
  ticket_no      NVARCHAR(50)      NN
  travel_class   NVARCHAR(30)
  from_place     NVARCHAR(200)
  to_place       NVARCHAR(200)
  travel_at      DATETIME2(0)      NN
  file_id        BIGINT                    FK → core.stored_file
  description    NVARCHAR(MAX)
```

```
req.req_promotion_benefit    -- benefits ticked on a promotion (many to many)
  request_id    BIGINT            NN  PK  FK → req.request
  pay_item_id   BIGINT            NN  PK  FK → pay.pay_item
```

```
req.req_expense    -- one expense request = the claims prepared together ("Generate Claim", "Submit All")
  request_id        BIGINT            NN  PK  FK → req.request
  currency          CHAR(3)
  total_amount      DECIMAL(18,2)     NN
  approved_amount   DECIMAL(18,2)
```

```
req.expense_line    -- one claim of an expense request, each with its own receipt
  id                    BIGINT IDENTITY   NN  PK
  request_id            BIGINT            NN      FK → req.request
  line_no               INT               NN
  title                 NVARCHAR(200)     NN    -- Expense Claim Title*
  claim_date            DATE              NN    -- Expense Claim Date (today when empty)
  expense_category_id   BIGINT            NN      FK → req.expense_category
  amount                DECIMAL(18,2)     NN
  approved_amount       DECIMAL(18,2)    -- the approver may lower it (0 = not reimbursed); the amount when left empty
  description           NVARCHAR(MAX)     NN
  file_id               BIGINT                    FK → core.stored_file    -- the receipt
  opening_balance_id    BIGINT                    FK → pay.opening_balance
  UNIQUE (request_id, line_no)
```

```
req.req_air_ticket    -- an air ticket the employee paid and claims back
  request_id           BIGINT            NN  PK  FK → req.request
  title                NVARCHAR(200)     NN
  claim_date           DATE              NN
  travel_date          DATE              NN
  from_place           NVARCHAR(200)
  to_place             NVARCHAR(200)
  amount               DECIMAL(18,2)     NN
  approved_amount      DECIMAL(18,2)
  currency             CHAR(3)
  description          NVARCHAR(MAX)
  file_id              BIGINT                PK  FK → core.stored_file    -- the ticket
  opening_balance_id   BIGINT                PK  FK → pay.opening_balance
```

```
req.req_requisition    -- items, assets or stationery wanted; approval only, then fulfilled by the admin side
  request_id          BIGINT            NN  PK  FK → req.request
  title               NVARCHAR(200)     NN
  requisition_type    NVARCHAR(30)      NN    -- stationery, it_equipment, furniture, asset, consumable, service, other
  needed_by_date      DATE              NN
  delivery_location   NVARCHAR(200)
  estimated_amount    DECIMAL(18,2)    -- the lines' quantity x estimated unit cost
  currency            CHAR(3)
```

```
req.requisition_line
  id                    BIGINT IDENTITY   NN  PK
  request_id            BIGINT            NN      FK → req.request
  line_no               INT               NN
  item_name             NVARCHAR(200)     NN
  quantity              DECIMAL(18,2)     NN
  unit                  NVARCHAR(200)
  estimated_unit_cost   DECIMAL(18,2)
  description           NVARCHAR(MAX)
  UNIQUE (request_id, line_no)
```

```
req.expense_category    -- Request Settings -> Expense Categories (Travel Fee, Tech & Soft, Venue Rental ...)
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  name               NVARCHAR(200)     NN
  pay_item_id        BIGINT                    FK → pay.pay_item    -- the reimbursement pay item claims of this category are paid under; empty: the default below
  max_amount         DECIMAL(18,2)    -- per claim; empty: no limit
  receipt_required   BIT               NN
  is_active          BIT               NN
  description        NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
req.reimbursement_setting    -- Request Settings -> Reimbursement: how approved claims reach payroll (one row per company)
  id                       BIGINT IDENTITY   NN  PK
  company_id               BIGINT            NN      FK → org.company
  expense_pay_item_id      BIGINT                    FK → pay.pay_item
  air_ticket_pay_item_id   BIGINT                    FK → pay.pay_item
  UNIQUE (company_id)
```

```
req.approval_flow    -- one version of a flow; editing saves a new version so requests on the way keep theirs
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  request_type_id   BIGINT            NN      FK → req.request_type
  purpose           NVARCHAR(30)    -- request, cancellation
  name              NVARCHAR(200)     NN
  scope_type        NVARCHAR(30)    -- company, branch, department, employee (the most specific active flow wins)
  scope_id          BIGINT    -- the branch, department or employee; empty for company
  description       NVARCHAR(MAX)
  is_active         BIT               NN
  is_current        BIT               NN    -- 0 once a newer version replaced it or it was deleted
```

```
req.approval_node
  id                     BIGINT IDENTITY   NN  PK
  approval_flow_id       BIGINT            NN      FK → req.approval_flow
  step_no                INT               NN    -- the node number shown in the editor; Next / If True / If False point at these
  approver_kind          NVARCHAR(30)    -- employee, line_manager, hod, branch_manager, final_authority, role, or an authority (team_lead, hr_manager, finance_manager ...)
  approver_employee_id   BIGINT                    FK → hr.employee
  role_id                BIGINT                    FK → auth.role    -- when approver_kind = role: anyone holding the role decides
  is_condition           BIT               NN
  expression             NVARCHAR(MAX)    -- as typed: days > 3, amount >= 100000, department_id = 12
  condition_field        NVARCHAR(200)    -- parsed from expression: days, amount, minutes, department_id, branch_id, location_id, grade_id, designation_id, employment_type_id
  condition_operator     NVARCHAR(2)    -- =, <>, >, >=, <, <=
  condition_value        DECIMAL(18,4)
  next_node_id           BIGINT                    FK → req.approval_node    -- empty: the next node by number
  true_node_id           BIGINT                    FK → req.approval_node
  false_node_id          BIGINT                    FK → req.approval_node
  can_edit               BIT               NN    -- the approver may change the request's details
  can_disagree           BIT               NN    -- a consent step: agree or disagree, the flow goes on either way
  is_observer            BIT               NN    -- "On Looker": informed only, does not decide
  UNIQUE (approval_flow_id, step_no)
```

```
req.approval_authority    -- who holds an authority (HR Manager, Finance Manager ...): the Request Flow screen of the requirements
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  authority         NVARCHAR(30)    -- team_lead, hr_manager, operations_manager, finance_manager, director, compliance_officer, project_manager, admin_supervisor, it_administrator, area_manager, admin_manager
  employee_id       BIGINT            NN      FK → hr.employee
  request_type_id   BIGINT                    FK → req.request_type    -- empty: every request type
  branch_id         BIGINT                    FK → org.branch    -- empty: every branch
  department_id     BIGINT                    FK → org.department    -- empty: every department
  description       NVARCHAR(MAX)
  is_active         BIT               NN
```

```
req.delegation
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  delegator_id      BIGINT            NN      FK → hr.employee
  delegatee_id      BIGINT            NN      FK → hr.employee
  request_type_id   BIGINT            NN      FK → req.request_type
  description       NVARCHAR(MAX)
  is_active         BIT               NN
```

```
req.request_restriction    -- block a request type for a company between two dates
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  request_type_id   BIGINT            NN      FK → req.request_type
  start_date        DATE              NN
  end_date          DATE              NN
  description       NVARCHAR(MAX)
```

```
req.request_step    -- one row per event and approver action; the Flow and History popups
  id                 BIGINT IDENTITY   NN  PK
  request_id         BIGINT            NN      FK → req.request
  approval_node_id   BIGINT                    FK → req.approval_node    -- empty for the submit, cancel and colleague-consent rows
  purpose            NVARCHAR(30)    -- request, cancellation
  approver_kind      NVARCHAR(30)    -- copied from the node (or colleague, requester)
  approver_id        BIGINT                    FK → hr.employee    -- who should act
  approver_role_id   BIGINT                    FK → auth.role    -- when any holder of a role may act
  acted_by_id        BIGINT                    FK → hr.employee    -- who did act (delegate if different)
  is_delegate        BIT               NN
  is_consent         BIT               NN    -- a consent step (Can Disagree node, or the colleague of a shift swap)
  action_taken       NVARCHAR(30)      NN    -- submitted, pending, approved, rejected, consented, disagreed, forwarded, skipped, informed, cancel_requested, withdrawn, cancelled
  remarks            NVARCHAR(MAX)
  acted_at           DATETIME2(0)
```

Relationships:
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

---

## 8. Loans  (`loan`)

```
loan.loan_type    -- Loan & Advance Types settings
  id                                BIGINT IDENTITY   NN  PK
  company_id                        BIGINT            NN      FK → org.company
  name                              NVARCHAR(200)     NN
  is_active                         BIT               NN
  guarantor_required                BIT               NN
  non_payable                       BIT               NN
  min_experience_months             INT               NN
  gap_between_requests_months       INT
  installments                      INT               NN
  gap_between_installments_months   INT
  formula_id                        BIGINT                    FK → pay.formula    -- optional until payroll formulas exist (Formula* in the requirements)
  deduction_pay_item_id             BIGINT                    FK → pay.pay_item
  description                       NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
loan.loan_type_employment_type    -- Employment Contract Type*: the contract types that may apply
  loan_type_id         BIGINT            NN  PK  FK → loan.loan_type
  employment_type_id   BIGINT            NN  PK  FK → org.employment_type
```

```
loan.loan_category
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  name          NVARCHAR(200)     NN
  is_active     BIT               NN
  description   NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
loan.loan    -- created when a loan request is finally approved
  id                                BIGINT IDENTITY   NN  PK
  company_id                        BIGINT            NN      FK → org.company
  employee_id                       BIGINT            NN      FK → hr.employee
  request_id                        BIGINT                    FK → req.request
  loan_type_id                      BIGINT            NN      FK → loan.loan_type
  loan_category_id                  BIGINT                    FK → loan.loan_category
  principal                         DECIMAL(18,2)     NN
  installment_amount                DECIMAL(18,2)
  installments                      INT
  gap_between_installments_months   INT
  currency                          CHAR(3)
  payment_method                    NVARCHAR(30)    -- bank, cash, pay_order, cheque
  start_month                       DATE    -- first installment month (from the repayment date)
  status                            NVARCHAR(30)      NN    -- active, settled, non_payable, written_off
  settled_at                        DATETIME2(0)
  UNIQUE (request_id)
```

```
loan.loan_installment    -- the Repayment tab; payroll marks rows paid
  id               BIGINT IDENTITY   NN  PK
  loan_id          BIGINT            NN      FK → loan.loan
  installment_no   INT               NN
  due_month        DATE              NN
  amount           DECIMAL(18,2)     NN
  paid_amount      DECIMAL(18,2)
  payslip_id       BIGINT                    FK → pay.payslip
  paid_at          DATETIME2(0)
  status           NVARCHAR(30)      NN
  UNIQUE (loan_id, installment_no)
```

Relationships:
```
request(loan) 1──1 loan 1──* loan_installment *──1 payslip
loan_type *──* employment_type
```

---

## 9. Payroll  (`pay`)

```
pay.tax_structure    -- Settings -> Tax -> Tax Structure
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  code              NVARCHAR(30)      NN    -- TXS-0004, from core.number_sequence prefix TXS-
  name              NVARCHAR(200)     NN
  start_date        DATE              NN
  end_date          DATE              NN
  surcharge_type    NVARCHAR(30)    -- flat, percentage (optional)
  surcharge_value   DECIMAL(18,2)
  description       NVARCHAR(MAX)
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
pay.tax_slab    -- tax = fixed_amount + (annual taxable - min_amount) x percentage / 100
  id                 BIGINT IDENTITY   NN  PK
  tax_structure_id   BIGINT            NN      FK → pay.tax_structure
  min_amount         DECIMAL(18,2)     NN
  max_amount         DECIMAL(18,2)
  fixed_amount       DECIMAL(18,2)     NN
  percentage         DECIMAL(5,2)      NN
```

```
pay.tax_rebate    -- Settings -> Tax -> Tax Rebate; lowers the year's tax
  id            BIGINT IDENTITY   NN  PK
  employee_id   BIGINT            NN      FK → hr.employee
  rebate_date   DATE              NN
  amount        DECIMAL(18,2)     NN
  file_id       BIGINT                    FK → core.stored_file
  description   NVARCHAR(MAX)
```

```
pay.formula    -- Pay Components -> Formulas; {variables}, pay items and other formulas
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  name                 NVARCHAR(200)     NN
  expression           NVARCHAR(MAX)     NN
  is_salary_division   BIT               NN
  for_integration      BIT               NN
  is_custom            BIT               NN    -- 0 for the formulas the system adds for its own pay items
  description          NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
pay.pay_item    -- Pay Components -> Pay Items
  id                       BIGINT IDENTITY   NN  PK
  company_id               BIGINT            NN      FK → org.company
  name                     NVARCHAR(200)     NN
  label                    NVARCHAR(200)
  item_type                NVARCHAR(30)      NN    -- earning, deduction, reimbursement, employee_data, other
  calculation_type         NVARCHAR(30)      NN    -- fixed (per-person amount), manual (typed on the payslip), formula
  tax_distribution         NVARCHAR(30)      NN    -- current_month, remaining_months
  employee_formula_id      BIGINT                    FK → pay.formula
  employer_formula_id      BIGINT                    FK → pay.formula
  is_taxable               BIT               NN    -- default for the Taxable tick when the item is added to a payroll
  is_display_only          BIT               NN
  is_benefit               BIT               NN
  is_advance_payment       BIT               NN
  eligibility_expression   NVARCHAR(MAX)    -- true/false expression; blank = everyone
  system_code              NVARCHAR(30)    -- salary, overtime, absent_deduction, leave_deduction, short_deduction, penalty_deduction, loan_deduction, leave_encashment, tax
  description              NVARCHAR(MAX)
  UNIQUE (company_id, name)
  UNIQUE (company_id, system_code)
```

```
pay.pay_rule    -- Pay Components -> Rules: evaluated per person on every run, posts to an employee account
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  name              NVARCHAR(200)     NN
  expression        NVARCHAR(MAX)     NN
  account_type_id   BIGINT            NN      FK → pay.account_type
  description       NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
pay.account_type    -- Settings -> Account Type
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  code         NVARCHAR(30)      NN    -- ACT-0001, from core.number_sequence prefix ACT-
  category     NVARCHAR(30)      NN    -- benefit, leave_quota, custom_pay_item
  ref_id       BIGINT    -- reward_benefit, lv.leave_type or pay_item, by category
  name         NVARCHAR(200)     NN
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
pay.reward_benefit    -- Settings -> Rewards -> Benefits ("Benefit Create")
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  name              NVARCHAR(200)     NN
  benefit_type      NVARCHAR(30)      NN
  pay_item_id       BIGINT            NN      FK → pay.pay_item
  formula_id        BIGINT                    FK → pay.formula
  is_group          BIT               NN
  is_accumulative   BIT               NN
  description       NVARCHAR(MAX)
  UNIQUE (company_id, name)
```

```
pay.reward_benefit_member    -- who gets it: employees, or employee groups when is_group
  id                  BIGINT IDENTITY   NN  PK
  reward_benefit_id   BIGINT            NN      FK → pay.reward_benefit
  employee_id         BIGINT                    FK → hr.employee
  employee_group_id   BIGINT                    FK → org.employee_group
```

```
pay.reward_benefit_field    -- "Additional Information" fields of a benefit
  id                  BIGINT IDENTITY   NN  PK
  reward_benefit_id   BIGINT            NN      FK → pay.reward_benefit
  name                NVARCHAR(200)     NN
  field_type          NVARCHAR(30)      NN
  is_required         BIT               NN
  min_value           DECIMAL(18,4)
  max_value           DECIMAL(18,4)
  min_length          INT
  max_length          INT
  field_value         NVARCHAR(MAX)
```

```
pay.sales_incentive    -- Settings -> Rewards -> Incentives (stored; no sales source yet)
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  branch_id          BIGINT            NN      FK → org.branch
  applicable_month   DATE              NN
  incentive_type     NVARCHAR(30)      NN
  target_amount      DECIMAL(18,2)     NN
  value_type         NVARCHAR(30)      NN
  reward_value       DECIMAL(18,2)     NN
  description        NVARCHAR(MAX)
```

```
pay.disbursement_bank    -- Settings -> Disbursement Banks (the company's paying accounts)
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  account_holder    NVARCHAR(200)     NN
  account_number    NVARCHAR(50)      NN
  bank_name         NVARCHAR(200)     NN
  branch_name       NVARCHAR(200)
  branch_code       NVARCHAR(30)      NN
  branch_location   NVARCHAR(200)     NN
  tax_payer_id      NVARCHAR(30)      NN
  effective_date    DATE
  description       NVARCHAR(MAX)
  UNIQUE (company_id, account_number)
```

```
pay.payroll    -- Payrolls -> Monthly and Daily Wages
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  code                   NVARCHAR(30)      NN    -- PR-00008, from core.number_sequence prefix PR-
  name                   NVARCHAR(200)     NN
  kind                   NVARCHAR(30)      NN    -- monthly, daily_wage
  payroll_month          DATE    -- monthly runs: first day of the month
  work_date              DATE    -- daily-wage runs
  time_slot_id           BIGINT                    FK → sch.time_slot
  currency               CHAR(3)
  tax_structure_id       BIGINT                    FK → pay.tax_structure
  tax_applicable         BIT               NN
  processing_mode        NVARCHAR(30)    -- from_date, month_end
  processing_date        DATE
  applicable_days        NVARCHAR(30)    -- actual, fixed
  fixed_days             INT
  disbursement_bank_id   BIGINT                    FK → pay.disbursement_bank
  description            NVARCHAR(MAX)
  status                 NVARCHAR(30)      NN    -- open, running, on_hold, closed
  last_run_at            DATETIME2(0)
  closed_at              DATETIME2(0)
  closed_by_user_id      BIGINT                    FK → auth.user_account
  UNIQUE (company_id, code)
```

```
pay.payroll_pay_item    -- which pay items this run uses
  id                  BIGINT IDENTITY   NN  PK
  payroll_id          BIGINT            NN      FK → pay.payroll
  pay_item_id         BIGINT            NN      FK → pay.pay_item
  is_taxable          BIT               NN
  arrear_applicable   BIT               NN
  final_settlement    BIT               NN
  calculate_only      BIT               NN
  UNIQUE (payroll_id, pay_item_id)
```

```
pay.payroll_employee    -- who is in the run
  payroll_id    BIGINT            NN  PK  FK → pay.payroll
  employee_id   BIGINT            NN  PK  FK → hr.employee
```

```
pay.payroll_run_log    -- Payrolls History
  id                BIGINT IDENTITY   NN  PK
  payroll_id        BIGINT            NN      FK → pay.payroll
  kind              NVARCHAR(30)      NN
  started_at        DATETIME2(0)
  finished_at       DATETIME2(0)
  status            NVARCHAR(30)      NN
  run_by_user_id    BIGINT                    FK → auth.user_account
  processed_count   INT
  error_count       INT
```

```
pay.payroll_run_error    -- Payrolls History Error
  id                   BIGINT IDENTITY   NN  PK
  payroll_run_log_id   BIGINT            NN      FK → pay.payroll_run_log
  employee_id          BIGINT                    FK → hr.employee
  message              NVARCHAR(MAX)
```

```
pay.payslip    -- one per person per run; final settlement slips have no run
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  payroll_id             BIGINT                    FK → pay.payroll
  employee_id            BIGINT            NN      FK → hr.employee
  payslip_month          DATE              NN
  applicable_days        DECIMAL(6,2)
  worked_days            DECIMAL(6,2)
  worked_minutes         INT
  expected_minutes       INT
  leave_days             DECIMAL(6,2)
  absent_days            DECIMAL(6,2)
  overtime_minutes       INT
  gross                  DECIMAL(18,2)
  total_earnings         DECIMAL(18,2)
  total_deductions       DECIMAL(18,2)
  total_reimbursements   DECIMAL(18,2)
  net_payable            DECIMAL(18,2)
  taxable_income         DECIMAL(18,2)
  tax_amount             DECIMAL(18,2)
  status                 NVARCHAR(30)      NN    -- ready, on_hold, released
  payment_method         NVARCHAR(30)    -- bank, cash
  released_at            DATETIME2(0)
  paid_at                DATETIME2(0)
  is_final_settlement    BIT               NN
  is_manually_updated    BIT               NN    -- daily wages: totals typed by hand
  UNIQUE (payroll_id, employee_id)
```

```
pay.payslip_line
  id                      BIGINT IDENTITY   NN  PK
  payslip_id              BIGINT            NN      FK → pay.payslip
  pay_item_id             BIGINT            NN      FK → pay.pay_item
  amount                  DECIMAL(18,2)     NN
  employer_contribution   DECIMAL(18,2)
  is_taxable              BIT               NN
  is_manually_updated     BIT               NN
  UNIQUE (payslip_id, pay_item_id)
```

```
pay.opening_balance    -- Balances -> Opening Balance; added to the pay item in that month's run
  id              BIGINT IDENTITY   NN  PK
  employee_id     BIGINT            NN      FK → hr.employee
  balance_month   DATE              NN
  pay_item_id     BIGINT            NN      FK → pay.pay_item
  amount          DECIMAL(18,2)     NN
  is_taxable      BIT               NN
  kind            NVARCHAR(30)      NN
  description     NVARCHAR(MAX)
```

```
pay.employee_account_entry    -- Provident Fund, EOBI, medical … ledger (Employee Accounts, Statement)
  id                BIGINT IDENTITY   NN  PK
  employee_id       BIGINT            NN      FK → hr.employee
  account_type_id   BIGINT            NN      FK → pay.account_type
  entry_month       DATE              NN
  credit            DECIMAL(18,2)
  debit             DECIMAL(18,2)
  is_processed      BIT               NN
  payslip_id        BIGINT                    FK → pay.payslip
  pay_rule_id       BIGINT                    FK → pay.pay_rule
  description       NVARCHAR(MAX)
```

```
pay.voucher    -- Vouchers / Employee Voucher; daily-wage vouchers
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  voucher_no            NVARCHAR(30)      NN
  employee_id           BIGINT            NN      FK → hr.employee
  voucher_type          NVARCHAR(30)      NN    -- expense_reimbursement, salary_advance, bonus, travel_allowance, daily_wage
  voucher_date          DATE              NN
  currency              CHAR(3)
  amount                DECIMAL(18,2)     NN
  payment_method        NVARCHAR(30)
  purpose               NVARCHAR(500)
  notes                 NVARCHAR(MAX)
  file_id               BIGINT                    FK → core.stored_file    -- attachment
  payroll_id            BIGINT                    FK → pay.payroll    -- daily-wage voucher
  requested_by_id       BIGINT                    FK → hr.employee
  approved_by_id        BIGINT                    FK → hr.employee
  decided_by_user_id    BIGINT                    FK → auth.user_account
  approved_at           DATETIME2(0)
  verified_by_id        BIGINT                    FK → hr.employee
  verified_by_user_id   BIGINT                    FK → auth.user_account
  verified_at           DATETIME2(0)
  remarks               NVARCHAR(MAX)    -- approver's or verifier's remarks
  status                NVARCHAR(30)      NN    -- pending, approved, rejected, processed
  UNIQUE (company_id, voucher_no)
  UNIQUE (payroll_id, employee_id)
```

Relationships:
```
tax_structure 1──* tax_slab
formula 1──* pay_item (employee / employer formula)
pay_rule *──1 account_type
reward_benefit 1──* reward_benefit_member / reward_benefit_field
payroll 1──* payroll_pay_item *──1 pay_item
payroll *──* employee   (payroll_employee)
payroll 1──* payslip 1──* payslip_line *──1 pay_item
payroll 1──* payroll_run_log 1──* payroll_run_error
employee 1──* opening_balance / employee_account_entry / tax_rebate / voucher
```

---

## 10. Assets and separation  (`sep`)

```
sep.asset_type    -- Assets -> Asset Types
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  code          NVARCHAR(30)      NN
  name          NVARCHAR(200)     NN
  description   NVARCHAR(MAX)
  is_active     BIT               NN
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
sep.asset    -- Assets -> Company Assets
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  code                NVARCHAR(30)      NN    -- AST-00001
  asset_type_id       BIGINT            NN      FK → sep.asset_type
  name                NVARCHAR(200)     NN
  identification_no   NVARCHAR(100)    -- serial / identification number
  is_taxable          BIT               NN
  asset_condition     NVARCHAR(30)    -- old, new, fair (condition when recorded)
  manufacturer        NVARCHAR(100)
  model               NVARCHAR(100)
  current_value       DECIMAL(18,2)
  acquired_date       DATE
  description         NVARCHAR(MAX)
  status              NVARCHAR(30)      NN    -- active, damaged, lost, decommissioned; who holds it comes from the open asset_allocation
  file_id             BIGINT                    FK → core.stored_file    -- attachment
  UNIQUE (company_id, code)
  UNIQUE (company_id, identification_no)
```

```
sep.asset_allocation    -- one row per hand-over; deallocated_on NULL while the employee holds it
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  asset_id               BIGINT            NN      FK → sep.asset
  employee_id            BIGINT            NN      FK → hr.employee
  allocated_on           DATE              NN
  deallocated_on         DATE
  status                 NVARCHAR(30)      NN    -- allocated, deallocated
  description            NVARCHAR(MAX)
  return_condition       NVARCHAR(30)    -- good, fair, damaged (at deallocation)
  deallocation_remarks   NVARCHAR(500)
  file_id                BIGINT                    FK → core.stored_file
  asset_clearance_id     BIGINT                    FK → sep.asset_clearance
```

```
sep.end_of_employment    -- End of Employment (All / Pending / Completed)
  id                       BIGINT IDENTITY   NN  PK
  company_id               BIGINT            NN      FK → org.company
  employee_id              BIGINT            NN      FK → hr.employee
  reason                   NVARCHAR(30)      NN    -- resignation, termination, retirement, other
  resignation_request_id   BIGINT                    FK → req.request
  serve_notice             BIT               NN    -- the Notice Period tick
  notice_period_days       INT
  last_working_date        DATE              NN    -- the day it is made when there is no notice period
  needs_final_settlement   BIT               NN
  needs_asset_clearance    BIT               NN
  asset_clear_by_date      DATE    -- off-boarding checklist "Asset Clear" date
  replacement_id           BIGINT                    FK → hr.employee
  delegatee_id             BIGINT                    FK → hr.employee
  description              NVARCHAR(MAX)
  file_id                  BIGINT                    FK → core.stored_file    -- attachment
  status                   NVARCHAR(30)      NN    -- pending, completed
  completed_at             DATETIME2(0)
  UNIQUE (resignation_request_id)
```

```
sep.asset_clearance    -- Asset Clearance Form, one per leaver at a time
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  employee_id            BIGINT            NN      FK → hr.employee
  end_of_employment_id   BIGINT                    FK → sep.end_of_employment
  clearance_date         DATE              NN
  checked_by_id          BIGINT                    FK → hr.employee
  approved_by_id         BIGINT                    FK → hr.employee
  approval_date          DATE
  file_id                BIGINT                    FK → core.stored_file
  status                 NVARCHAR(30)      NN    -- in_progress, approved
```

```
sep.asset_clearance_item    -- one Asset Details block: an allocation being cleared
  id                       BIGINT IDENTITY   NN  PK
  asset_clearance_id       BIGINT            NN      FK → sep.asset_clearance
  asset_allocation_id      BIGINT            NN      FK → sep.asset_allocation
  condition_at_clearance   NVARCHAR(30)
  reason                   NVARCHAR(MAX)
  return_status            NVARCHAR(30)
  comments                 NVARCHAR(MAX)
  UNIQUE (asset_clearance_id, asset_allocation_id)
```

```
sep.final_settlement    -- started by end of employment; payroll fills the payslip and closes it
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  end_of_employment_id   BIGINT            NN      FK → sep.end_of_employment
  payslip_id             BIGINT                    FK → pay.payslip
  status                 NVARCHAR(30)      NN
  closed_at              DATETIME2(0)
  file_id                BIGINT                    FK → core.stored_file    -- the signed settlement letter, given on Close FS
  UNIQUE (end_of_employment_id)
```

```
sep.offboarding_checklist    -- Settings -> Off Boarding Checklist (ECL-00001)
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  code          NVARCHAR(30)      NN
  name          NVARCHAR(200)     NN
  description   NVARCHAR(MAX)
  is_active     BIT               NN
  UNIQUE (company_id, code)
  UNIQUE (company_id, name)
```

```
sep.checklist_field    -- "Additional Information": number, string, date, boolean
  id                         BIGINT IDENTITY   NN  PK
  offboarding_checklist_id   BIGINT            NN      FK → sep.offboarding_checklist
  name                       NVARCHAR(200)     NN
  field_type                 NVARCHAR(30)
  is_required                BIT               NN
  min_value                  DECIMAL(18,4)
  max_value                  DECIMAL(18,4)
  min_length                 INT
  max_length                 INT
  sort_order                 INT
  UNIQUE (offboarding_checklist_id, name)
```

```
sep.checklist_answer
  id                     BIGINT IDENTITY   NN  PK
  end_of_employment_id   BIGINT            NN      FK → sep.end_of_employment
  checklist_field_id     BIGINT            NN      FK → sep.checklist_field
  answer                 NVARCHAR(MAX)
  UNIQUE (end_of_employment_id, checklist_field_id)
```

Relationships:
```
asset_type 1──* asset 1──* asset_allocation *──1 employee
employee 1──* end_of_employment
end_of_employment 1──* asset_clearance 1──* asset_clearance_item *──1 asset_allocation
end_of_employment 1──1 final_settlement
end_of_employment 1──* checklist_answer *──1 checklist_field *──1 offboarding_checklist
```

---

## 11. Recruitment  (`rec`)

```
rec.job_opening    -- "New Job Position": a vacancy advertised and recruited for
  id                      BIGINT IDENTITY   NN  PK
  company_id              BIGINT            NN      FK → org.company
  code                    NVARCHAR(30)      NN    -- given, or the next JOB-0001 number
  title                   NVARCHAR(200)     NN    -- "Marketing Executive"
  open_position_id        BIGINT                    FK → mp.open_position    -- optional: the Manpower seat it fills (vacancies cannot exceed its open seats)
  job_title_id            BIGINT                    FK → org.job_title    -- optional: org.job_title, given to the employee on hire
  designation_id          BIGINT                    FK → org.designation    -- optional
  department_id           BIGINT                    FK → org.department    -- optional: scope and the hired employee's department
  branch_id               BIGINT                    FK → org.branch    -- optional: "Station"; scope and the hired employee's branch
  employment_type_id      BIGINT                    FK → org.employment_type
  hiring_manager_id       BIGINT                    FK → hr.employee
  city_id                 BIGINT                    FK → org.city    -- optional: "Enter City" (its state is "Enter State")
  work_mode               NVARCHAR(30)    -- on_site, remote, hybrid
  experience_from_years   INT    -- "Experience From"
  experience_to_years     INT    -- "Experience To"
  vacancies               INT               NN    -- "No. of Vacancies"
  posted_on               DATE    -- "Posted Date"; set on publish when blank
  apply_by                DATE    -- "Last Date to Apply"
  close_on                DATE    -- "Close Date"
  salary_from             DECIMAL(18,2)    -- "Salary From"
  salary_to               DECIMAL(18,2)    -- "Salary To"
  is_salary_visible       BIT               NN    -- show the range on the careers page
  description             NVARCHAR(MAX)    -- rich text (HTML) "Job Description" editor
  requirements            NVARCHAR(MAX)    -- skills and qualifications
  status                  NVARCHAR(30)      NN    -- draft, open, on_hold, closed
  published_at            DATETIME2(0)
  closed_at               DATETIME2(0)
  UNIQUE (company_id, code)
```

```
rec.applicant    -- a candidate in the talent pool; one per e-mail address per company
  id                        BIGINT IDENTITY   NN  PK
  company_id                BIGINT            NN      FK → org.company
  first_name                NVARCHAR(200)     NN
  last_name                 NVARCHAR(200)     NN
  email                     NVARCHAR(254)     NN
  phone                     NVARCHAR(30)
  gender                    NVARCHAR(30)
  date_of_birth             DATE
  city_id                   BIGINT                    FK → org.city    -- optional
  address                   NVARCHAR(500)
  current_employer          NVARCHAR(200)
  current_job_title         NVARCHAR(200)
  experience_years          DECIMAL(4,1)    -- total years of experience
  current_salary            DECIMAL(18,2)
  expected_salary           DECIMAL(18,2)
  notice_period_days        INT
  highest_education         NVARCHAR(200)
  linkedin_url              NVARCHAR(500)
  source                    NVARCHAR(30)    -- career_site, referral, job_board, linkedin, walk_in, agency, other
  referred_by_employee_id   BIGINT                    FK → hr.employee
  cv_file_id                BIGINT                    FK → core.stored_file    -- the CV, uploaded first through /api/files
  notes                     NVARCHAR(MAX)
  UNIQUE (company_id, email)
```

```
rec.application    -- one applicant for one opening, moving through the pipeline
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  job_opening_id        BIGINT            NN      FK → rec.job_opening
  applicant_id          BIGINT            NN      FK → rec.applicant
  applied_on            DATE              NN
  source                NVARCHAR(30)    -- how this application came; defaults to the applicant's source
  cover_letter          NVARCHAR(MAX)
  stage                 NVARCHAR(30)      NN    -- applied, screening, shortlisted, interview, offer, hired, rejected, withdrawn
  stage_changed_at      DATETIME2(0)
  rejection_reason_id   BIGINT                    FK → rec.rejection_reason
  rejected_stage        NVARCHAR(30)    -- the stage it was rejected or withdrawn at ("non qualified" = rejected at screening)
  remarks               NVARCHAR(MAX)
  employee_id           BIGINT                    FK → hr.employee    -- set on hire: the employee created from this application
  hired_at              DATETIME2(0)
  UNIQUE (job_opening_id, applicant_id)
```

```
rec.application_stage_history    -- every stage change, for the pipeline timeline and the dashboard
  id                   BIGINT IDENTITY   NN  PK
  application_id       BIGINT            NN      FK → rec.application
  from_stage           NVARCHAR(30)
  to_stage             NVARCHAR(30)      NN
  changed_at           DATETIME2(0)      NN
  changed_by_user_id   BIGINT                    FK → auth.user_account
  remarks              NVARCHAR(MAX)
```

```
rec.interview    -- one round with one candidate ("re-interview" is a further round)
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  application_id     BIGINT            NN      FK → rec.application
  round_no           INT               NN    -- 1, 2, 3 ... per application
  title              NVARCHAR(200)     NN    -- "HR interview", "Technical"
  mode               NVARCHAR(30)    -- in_person, phone, video
  scheduled_at       DATETIME2(0)      NN    -- local wall-clock time, like attendance times
  duration_minutes   INT               NN
  venue              NVARCHAR(500)    -- address or meeting link
  status             NVARCHAR(30)      NN    -- scheduled, completed, cancelled, no_show
  result             NVARCHAR(30)    -- passed, failed, on_hold (set when completed)
  remarks            NVARCHAR(MAX)
```

```
rec.interview_interviewer    -- the panel of an interview
  interview_id   BIGINT            NN  PK  FK → rec.interview
  employee_id    BIGINT            NN  PK  FK → hr.employee
```

```
rec.interview_evaluation    -- one interviewer's feedback on one interview
  id                     BIGINT IDENTITY   NN  PK
  interview_id           BIGINT            NN      FK → rec.interview
  employee_id            BIGINT            NN      FK → hr.employee    -- the interviewer
  rating                 INT               NN    -- 1 to 5
  recommendation         NVARCHAR(30)      NN    -- strong_hire, hire, no_hire, strong_no_hire
  strengths              NVARCHAR(MAX)
  concerns               NVARCHAR(MAX)
  comments               NVARCHAR(MAX)
  evaluated_at           DATETIME2(0)      NN
  evaluated_by_user_id   BIGINT                    FK → auth.user_account
  UNIQUE (interview_id, employee_id)
```

```
rec.offer    -- the offer made to a candidate; a revised offer is a new row
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  application_id         BIGINT            NN      FK → rec.application
  job_title_id           BIGINT                    FK → org.job_title
  designation_id         BIGINT                    FK → org.designation
  department_id          BIGINT                    FK → org.department
  branch_id              BIGINT                    FK → org.branch
  employment_type_id     BIGINT                    FK → org.employment_type
  offered_salary         DECIMAL(18,2)     NN    -- gross a month (or a day / an hour by salary_frequency)
  salary_frequency       NVARCHAR(30)    -- monthly, daily, hourly
  joining_date           DATE              NN
  probation_months       INT    -- 0 = no probation
  expires_on             DATE
  offer_letter_file_id   BIGINT                    FK → core.stored_file
  status                 NVARCHAR(30)      NN    -- draft, sent, accepted, declined, withdrawn
  sent_at                DATETIME2(0)
  responded_at           DATETIME2(0)
  response_remarks       NVARCHAR(MAX)    -- the candidate's answer, the reason for declining
  remarks                NVARCHAR(MAX)
```

```
rec.rejection_reason    -- Settings -> Rejection reasons
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  is_active    BIT               NN
  sort_order   INT
  UNIQUE (company_id, name)
```

Relationships:
```
open_position 1──* job_opening 1──* application *──1 applicant
application 1──* application_stage_history
application 1──* interview 1──* interview_interviewer *──1 employee
interview 1──* interview_evaluation
application 1──* offer
rejection_reason 1──* application
application ──> employee (hired)
```

---

## 12. Manpower planning  (`mp`)

```
mp.budget_duration    -- E-Budget Settings -> Budget Duration; the "Plan Year" of plans and budgets
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN    -- "2024", "2024-2025"
  start_date   DATE              NN
  end_date     DATE              NN
  is_current   BIT               NN    -- IsCurrentBudgetDurationPeriod: at most one per company (kept by mp.usp_budget_duration_save)
  UNIQUE (company_id, name)
```

```
mp.position    -- E-Budget Settings -> Employee Position: an approved seat
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  code                NVARCHAR(30)      NN    -- given, or the next POS-0001 number
  branch_id           BIGINT            NN      FK → org.branch    -- shown as "Station" (required on the form)
  job_title_id        BIGINT            NN      FK → org.job_title    -- shown as "Position Title" (org.job_title)
  employee_group_id   BIGINT            NN      FK → org.employee_group
  division_id         BIGINT                    FK → org.division    -- optional
  department_id       BIGINT                    FK → org.department
  sub_department_id   BIGINT                    FK → org.department
  cost_center_id      BIGINT                    FK → org.cost_center
  grade_id            BIGINT                    FK → org.grade
  reports_to_id       BIGINT                    FK → mp.position
  employee_id         BIGINT                    FK → hr.employee    -- who holds it, blank if open
  status              NVARCHAR(30)      NN    -- active, inactive
  UNIQUE (company_id, code)
```

```
mp.position_salary_range    -- the Min / Max Salary of the Employee Position form, kept over time
  id               BIGINT IDENTITY   NN  PK
  position_id      BIGINT            NN      FK → mp.position
  effective_date   DATE              NN    -- the band in force is the latest one on or before the day asked about
  min_salary       DECIMAL(18,2)     NN
  max_salary       DECIMAL(18,2)     NN
  UNIQUE (position_id, effective_date)
```

```
mp.manpower_plan    -- "Add Planning"; saving submits it and makes its budgets
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  title                NVARCHAR(200)     NN
  budget_duration_id   BIGINT            NN      FK → mp.budget_duration
  division_id          BIGINT                    FK → org.division    -- optional
  branch_id            BIGINT                    FK → org.branch    -- "Station"
  department_id        BIGINT                    FK → org.department
  sub_department_id    BIGINT                    FK → org.department
  employee_group_id    BIGINT                    FK → org.employee_group
  description          NVARCHAR(MAX)
  monthly_amount       DECIMAL(18,2)     NN    -- sum of the lines' total_salary (computed by the procedure)
  annual_amount        DECIMAL(18,2)     NN    -- sum of the lines' annual_gross (computed by the procedure)
  status               NVARCHAR(30)      NN    -- pending, approved, rejected (follows its budgets)
  submitted_at         DATETIME2(0)
```

```
mp.manpower_plan_line    -- Plan for New Positions (kind new_position) / Existing Positions (existing_employee)
  id                 BIGINT IDENTITY   NN  PK
  manpower_plan_id   BIGINT            NN      FK → mp.manpower_plan
  kind               NVARCHAR(30)      NN    -- new_position, existing_employee
  sort_order         INT
  position_id        BIGINT                    FK → mp.position    -- new-position lines
  employee_id        BIGINT                    FK → hr.employee    -- existing-employee lines
  e_budget_id        BIGINT                    FK → mp.e_budget    -- the budget this line is counted in
  headcount          INT               NN    -- vacancies on a new-position line; 1 on an existing-employee line
  start_date         DATE              NN    -- "Plan Date" from (first day of the month)
  end_date           DATE              NN    -- "Plan Date" to; both inside the plan year
  months             INT               NN    -- calendar months from start to end, both counted
  min_salary         DECIMAL(18,2)
  max_salary         DECIMAL(18,2)
  monthly_salary     DECIMAL(18,2)    -- existing employees: defaulted from hr.employee_salary
  total_allowance    DECIMAL(18,2)     NN
  total_salary       DECIMAL(18,2)     NN    -- a month: (max_salary + allowance) x headcount, or monthly_salary + allowance
  annual_gross       DECIMAL(18,2)     NN    -- total_salary x months
```

```
mp.e_budget    -- "E-Budgeting" list and "Budget Approvals"
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  budget_duration_id   BIGINT            NN      FK → mp.budget_duration
  manpower_plan_id     BIGINT                    FK → mp.manpower_plan    -- optional: blank for a budget added by hand
  job_title_id         BIGINT                    FK → org.job_title    -- the position title the money is for
  department_id        BIGINT                    FK → org.department    -- rows are per department in the samples
  title                NVARCHAR(200)     NN
  amount               DECIMAL(18,2)     NN
  total_positions      INT               NN    -- new seats it opens once approved
  start_date           DATE              NN
  end_date             DATE              NN
  status               NVARCHAR(30)      NN    -- pending, approved, rejected
  decided_by_user_id   BIGINT                    FK → auth.user_account
  decided_at           DATETIME2(0)
  remarks              NVARCHAR(MAX)
```

```
mp.open_position    -- positions released for hiring when a budget is approved
  id                      BIGINT IDENTITY   NN  PK
  company_id              BIGINT            NN      FK → org.company
  e_budget_id             BIGINT            NN      FK → mp.e_budget
  manpower_plan_line_id   BIGINT                    FK → mp.manpower_plan_line
  position_id             BIGINT                    FK → mp.position
  job_title_id            BIGINT                    FK → org.job_title
  department_id           BIGINT                    FK → org.department
  branch_id               BIGINT                    FK → org.branch
  title                   NVARCHAR(200)     NN
  approved_positions      INT               NN    -- seats the budget approved
  total_positions         INT               NN    -- seats open now (Edit)
  end_date                DATE
  jd_file_id              BIGINT                    FK → core.stored_file    -- "JD's" download
  status                  NVARCHAR(30)      NN    -- active, closed
```

Relationships:
```
budget_duration 1──* manpower_plan 1──* manpower_plan_line ──> position
budget_duration 1──* e_budget 1──* manpower_plan_line
manpower_plan 1──* e_budget 1──* open_position 1──* job_position
position 1──* position_salary_range
position ──> position (reports to)
```

---

## 13. Shared  (`core`)

```
core.stored_file    -- an uploaded file: the bytes on the server's disk, this row in the database
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  module                NVARCHAR(30)      NN    -- the uploading module; also the folder it is stored in
  name                  NVARCHAR(255)     NN    -- the original file name, used for downloads only
  extension             NVARCHAR(20)      NN
  mime_type             NVARCHAR(100)     NN
  size_bytes            BIGINT            NN
  sha256                CHAR(64)          NN
  storage_path          NVARCHAR(500)     NN    -- relative to the upload root: <company>/<module>/<yyyy>/<mm>/<uuid>.<ext>
  uploaded_by_user_id   BIGINT                    FK → auth.user_account
  UNIQUE (storage_path)
```

```
core.attachment    -- any file on any record
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  entity_type   NVARCHAR(50)      NN
  entity_id     BIGINT            NN
  file_id       BIGINT                    FK → core.stored_file
  label         NVARCHAR(200)
  UNIQUE (entity_type, entity_id, file_id)
```

```
core.audit_log    -- every "History" popup reads this; also the access change history (ACC-15)
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT                    FK → org.company
  entity_type            NVARCHAR(50)
  entity_id              BIGINT
  field_name             NVARCHAR(100)
  old_value              NVARCHAR(MAX)
  new_value              NVARCHAR(MAX)
  action_name            NVARCHAR(30)
  performed_by_user_id   BIGINT                    FK → auth.user_account
  performed_at           DATETIME2(0)
```

```
core.company_setting    -- switches and values: attendance basic, the 22 payroll options, leave general, overtime
  id              BIGINT IDENTITY   NN  PK
  company_id      BIGINT            NN      FK → org.company
  module          NVARCHAR(30)
  setting_key     NVARCHAR(100)
  setting_value   NVARCHAR(MAX)
  UNIQUE (company_id, module, setting_key)
```

```
core.number_sequence    -- codes like RQ-, PR-, AST-, TS-
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  prefix        NVARCHAR(10)
  next_number   INT
  UNIQUE (company_id, prefix)
```

```
core.filter_preset    -- "Save Preset" on every list
  id                BIGINT IDENTITY   NN  PK
  user_account_id   BIGINT            NN      FK → auth.user_account
  screen            NVARCHAR(100)
  name              NVARCHAR(200)     NN
  filters           NVARCHAR(MAX)
```

```
core.notification    -- the inbox; any module adds rows through core.usp_notification_add
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  user_account_id     BIGINT            NN      FK → auth.user_account
  notification_type   NVARCHAR(30)
  title               NVARCHAR(200)     NN
  body                NVARCHAR(MAX)
  link                NVARCHAR(500)
  entity_type         NVARCHAR(50)
  entity_id           BIGINT
  read_at             DATETIME2(0)
  cleared_at          DATETIME2(0)
```

```
core.webhook    -- an outside system told about events (Settings → Integrations); signed with its secret
  id                 BIGINT IDENTITY   NN  PK
  company_id         BIGINT            NN      FK → org.company
  name               NVARCHAR(200)     NN
  url                NVARCHAR(1000)    NN
  secret             NVARCHAR(100)     NN    -- HMAC-SHA256 key; shown once when the webhook is created
  events             NVARCHAR(MAX)     NN    -- JSON list of event types, "module.*" or "*"
  is_active          BIT               NN
  failure_count      INT               NN    -- consecutive failed deliveries
  last_delivery_at   DATETIME2(0)
  last_status_code   INT
```

```
core.outbox_event    -- every event a module publishes, written in the same transaction as the change
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  event_type    NVARCHAR(100)     NN    -- notification.created, request.approved ...
  entity_type   NVARCHAR(50)
  entity_id     BIGINT
  payload       NVARCHAR(MAX)     NN    -- JSON
  occurred_at   DATETIME2(0)      NN
```

```
core.webhook_delivery    -- one event to one webhook, retried with back-off
  id                BIGINT IDENTITY   NN  PK
  webhook_id        BIGINT            NN      FK → core.webhook
  outbox_event_id   BIGINT                    FK → core.outbox_event
  status            NVARCHAR(30)      NN    -- pending, delivered, failed
  attempts          INT               NN
  next_attempt_at   DATETIME2(0)
  last_attempt_at   DATETIME2(0)
  response_code     INT
  response_body     NVARCHAR(2000)
  error             NVARCHAR(1000)
  UNIQUE (webhook_id, outbox_event_id)
```

Relationships:
```
stored_file 1──* attachment
webhook 1──* webhook_delivery *──1 outbox_event
```

---

## 14. Engagement  (`eng`)

```
eng.announcement    -- "Announcements" list; the dashboards' Notice Board (kind notice) and Upcoming Events (kind event)
  id             BIGINT IDENTITY   NN  PK
  company_id     BIGINT            NN      FK → org.company
  author_id      BIGINT                    FK → hr.employee    -- optional: blank when posted by a user with no employee record
  kind           NVARCHAR(30)      NN    -- notice, event
  title          NVARCHAR(200)     NN
  body           NVARCHAR(MAX)
  event_date     DATE    -- the day an event happens (kind event)
  publish_from   DATE
  publish_to     DATE
```

```
eng.announcement_read    -- "Mark as read" / "Mark all as read" / "Clear All", per employee
  announcement_id   BIGINT            NN  PK  FK → eng.announcement
  employee_id       BIGINT            NN  PK  FK → hr.employee
  read_at           DATETIME2(0)
  cleared_at        DATETIME2(0)
```

```
eng.post    -- newsfeed post ("What would you like to share?")
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  author_id            BIGINT            NN      FK → hr.employee
  body                 NVARCHAR(MAX)    -- text, up to 5000 characters; blank when the post is only photos or videos
  visibility           NVARCHAR(30)      NN    -- public (chip "Public"), department, branch
  department_id        BIGINT                    FK → org.department    -- the audience when visibility is department (sub-departments included)
  branch_id            BIGINT                    FK → org.branch    -- the audience when visibility is branch
  posted_at            DATETIME2(0)      NN
  edited_at            DATETIME2(0)    -- "Edit Post" on My Posts
  is_pinned            BIT               NN    -- pinned posts open the feed
  pinned_at            DATETIME2(0)
  pinned_by_user_id    BIGINT                    FK → auth.user_account
  is_hidden            BIT               NN    -- hidden by a moderator: only the author and moderators see it
  hidden_at            DATETIME2(0)
  hidden_by_user_id    BIGINT                    FK → auth.user_account
  hidden_reason        NVARCHAR(500)
  is_deleted           BIT               NN    -- "Delete" on My Posts, or a moderator; kept for the audit trail
  deleted_at           DATETIME2(0)
  deleted_by_user_id   BIGINT                    FK → auth.user_account
```

```
eng.post_media    -- several photos and videos per post, in order
  id           BIGINT IDENTITY   NN  PK
  post_id      BIGINT            NN      FK → eng.post
  file_id      BIGINT            NN      FK → core.stored_file
  media_type   NVARCHAR(30)
  sort_order   INT
  UNIQUE (post_id, file_id)
```

```
eng.post_reaction    -- "Liked" and the "Reactions on Post" list; one per person per post
  id            BIGINT IDENTITY   NN  PK
  post_id       BIGINT            NN      FK → eng.post
  employee_id   BIGINT            NN      FK → hr.employee
  kind          NVARCHAR(30)      NN
  reacted_at    DATETIME2(0)      NN
  UNIQUE (post_id, employee_id)
```

```
eng.post_comment    -- comments with Reply (one level: a reply to a reply joins the same thread)
  id             BIGINT IDENTITY   NN  PK
  post_id        BIGINT            NN      FK → eng.post
  employee_id    BIGINT            NN      FK → hr.employee
  parent_id      BIGINT                    FK → eng.post_comment    -- the top-level comment a reply belongs to
  body           NVARCHAR(MAX)     NN    -- up to 2000 characters
  commented_at   DATETIME2(0)      NN
  edited_at      DATETIME2(0)
```

```
eng.post_comment_like    -- "Like" on a comment
  post_comment_id   BIGINT            NN  PK  FK → eng.post_comment
  employee_id       BIGINT            NN  PK  FK → hr.employee
  liked_at          DATETIME2(0)      NN
```

```
eng.post_view    -- "2.5k Views": counted once per person
  post_id       BIGINT            NN  PK  FK → eng.post
  employee_id   BIGINT            NN  PK  FK → hr.employee
  viewed_at     DATETIME2(0)      NN
```

```
eng.post_mention    -- @person in a post (post_comment_id blank) or in a comment
  id                BIGINT IDENTITY   NN  PK
  post_id           BIGINT            NN      FK → eng.post
  post_comment_id   BIGINT                    FK → eng.post_comment
  employee_id       BIGINT            NN      FK → hr.employee
```

```
eng.survey    -- survey builder: title, closing date, questions; "Survey Available" popup for the audience
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  title                  NVARCHAR(200)     NN
  description            NVARCHAR(MAX)
  is_anonymous           BIT               NN    -- answers are kept without the employee (survey_participant records who answered)
  status                 NVARCHAR(30)      NN    -- draft, published, closed (a published survey past its closing date reads as closed)
  opens_on               DATE    -- blank: from publishing
  closes_on              DATE    -- last day to respond
  published_at           DATETIME2(0)
  published_by_user_id   BIGINT                    FK → auth.user_account
  closed_at              DATETIME2(0)
  closed_by_user_id      BIGINT                    FK → auth.user_account
```

```
eng.survey_audience    -- who is asked; no rows = everyone in the company
  id          BIGINT IDENTITY   NN  PK
  survey_id   BIGINT            NN      FK → eng.survey
  unit_type   NVARCHAR(30)      NN
  unit_id     BIGINT            NN
  UNIQUE (survey_id, unit_type, unit_id)
```

```
eng.survey_question
  id                BIGINT IDENTITY   NN  PK
  survey_id         BIGINT            NN      FK → eng.survey
  sort_order        INT
  question_type     NVARCHAR(30)      NN    -- single (Multiple Choice), dropdown, multiple (Check Boxes), text (Short Answer), paragraph, rating (Linear Scale)
  question_text     NVARCHAR(1000)    NN    -- "What would you like to ask?"
  is_required       BIT               NN
  scale_min         INT    -- rating: lowest value (0 or 1)
  scale_max         INT    -- rating: highest value (2 to 10)
  scale_min_label   NVARCHAR(100)
  scale_max_label   NVARCHAR(100)
```

```
eng.survey_option    -- "Add New Option"
  id                   BIGINT IDENTITY   NN  PK
  survey_question_id   BIGINT            NN      FK → eng.survey_question
  sort_order           INT
  option_text          NVARCHAR(500)     NN
```

```
eng.survey_participant    -- one per employee per survey: answered or skipped ("Skip" on the popup)
  survey_id      BIGINT            NN  PK  FK → eng.survey
  employee_id    BIGINT            NN  PK  FK → hr.employee
  responded_at   DATETIME2(0)
  skipped        BIT               NN
  skipped_at     DATETIME2(0)
```

```
eng.survey_response    -- the answers of one person; employee blank when the survey is anonymous
  id             BIGINT IDENTITY   NN  PK
  survey_id      BIGINT            NN      FK → eng.survey
  employee_id    BIGINT                    FK → hr.employee
  submitted_at   DATETIME2(0)      NN
```

```
eng.survey_answer    -- one row per chosen option, or one with the text or rating
  id                   BIGINT IDENTITY   NN  PK
  survey_response_id   BIGINT            NN      FK → eng.survey_response
  survey_question_id   BIGINT            NN      FK → eng.survey_question
  survey_option_id     BIGINT                    FK → eng.survey_option
  answer_text          NVARCHAR(MAX)
  rating_value         INT
```

Relationships:
```
announcement 1──* announcement_read
post 1──* post_media / post_reaction / post_comment / post_view / post_mention
post_comment 1──* post_comment (replies) / post_comment_like / post_mention
survey 1──* survey_audience / survey_question / survey_participant / survey_response
survey_question 1──* survey_option
survey_response 1──* survey_answer
```

---

## 15. Project and task management  (`pm`)

```
pm.template    -- reference data: the four workflow templates (Define Workflow) and the five status templates (Edit Statuses)
  id              BIGINT IDENTITY   NN  PK
  template_kind   NVARCHAR(30)      NN
  code            NVARCHAR(30)      NN
  name            NVARCHAR(200)     NN
  description     NVARCHAR(MAX)
  sort_order      INT
  UNIQUE (template_kind, code)
```

```
pm.template_item    -- what a template starts with: a view, a status or an organizer feature
  id             BIGINT IDENTITY   NN  PK
  template_id    BIGINT            NN      FK → pm.template
  item_type      NVARCHAR(30)      NN    -- view, status, feature
  item_code      NVARCHAR(50)    -- view or feature code; blank for a status
  name           NVARCHAR(200)     NN    -- status name, or the label of the view or feature
  status_group   NVARCHAR(30)    -- statuses: not_started, active, done, closed
  color          NVARCHAR(20)
  sort_order     INT
  is_default     BIT               NN    -- views: the view a workspace opens on
```

```
pm.workspace
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  name                   NVARCHAR(200)     NN    -- 3 to 50 characters, unique in the company
  description            NVARCHAR(MAX)    -- up to 300 characters
  privacy                NVARCHAR(30)      NN    -- private (members only), workspace (everyone in the company), public (everyone in the company reads, members edit)
  department_id          BIGINT            NN      FK → org.department    -- Define Workflow: Select Your Department
  workflow_template_id   BIGINT            NN      FK → pm.template    -- work_starter, project_management, marketing_team, product_engineering
  status_mode            NVARCHAR(30)      NN    -- default, custom
  status_template_id     BIGINT                    FK → pm.template    -- custom statuses started from this status template
  owner_id               BIGINT            NN      FK → hr.employee    -- Workspace Owner; always a member with workspace_admin
  cover_file_id          BIGINT                    FK → core.stored_file
  UNIQUE (company_id, name)
```

```
pm.workspace_member
  workspace_id   BIGINT            NN  PK  FK → pm.workspace
  employee_id    BIGINT            NN  PK  FK → hr.employee
  member_role    NVARCHAR(30)      NN
```

```
pm.workspace_status    -- the workspace's task statuses, in four groups
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  status_group   NVARCHAR(30)      NN
  name           NVARCHAR(200)     NN
  color          NVARCHAR(20)
  sort_order     INT
  wip_limit      INT
  UNIQUE (workspace_id, name)
```

```
pm.workspace_feature    -- organizer features switched on (priority, tags, time_tracking, story_points, wip_limits ...)
  id              BIGINT IDENTITY   NN  PK
  workspace_id    BIGINT            NN      FK → pm.workspace
  feature_code    NVARCHAR(50)      NN
  setting_value   NVARCHAR(MAX)
  UNIQUE (workspace_id, feature_code)
```

```
pm.folder
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  name           NVARCHAR(200)     NN
  sort_order     INT
  UNIQUE (workspace_id, name)
```

```
pm.task_list    -- a list (the BRD's "project"): colour, description up to 500, priority, start and end
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  folder_id      BIGINT                    FK → pm.folder
  name           NVARCHAR(200)     NN
  privacy        NVARCHAR(30)
  color          NVARCHAR(20)
  description    NVARCHAR(MAX)
  start_at       DATETIME2(0)
  end_at         DATETIME2(0)
  priority       NVARCHAR(30)
  sort_order     INT
  UNIQUE (workspace_id, name)
```

```
pm.task_list_member    -- who may see a private list (besides workspace admins and HR)
  task_list_id   BIGINT            NN  PK  FK → pm.task_list
  employee_id    BIGINT            NN  PK  FK → hr.employee
```

```
pm.sprint    -- not in the first build (Sprints column marked Skipped in the design)
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  name           NVARCHAR(200)     NN
  start_date     DATE
  end_date       DATE
```

```
pm.task
  id                      BIGINT IDENTITY   NN  PK
  company_id              BIGINT            NN      FK → org.company
  workspace_id            BIGINT            NN      FK → pm.workspace
  task_list_id            BIGINT                    FK → pm.task_list    -- blank: at the workspace's top level
  parent_task_id          BIGINT                    FK → pm.task    -- subtask
  code                    NVARCHAR(30)      NN    -- HR000000001, per company
  name                    NVARCHAR(200)     NN
  description             NVARCHAR(MAX)
  task_type               NVARCHAR(30)      NN    -- task, milestone
  status_id               BIGINT            NN      FK → pm.workspace_status
  priority                NVARCHAR(30)    -- urgent, high, normal, low
  start_date              DATE
  start_time              TIME(0)
  due_date                DATE
  due_time                TIME(0)
  original_due_date       DATE    -- the due date before an approved extension
  time_estimate_minutes   INT
  rating                  INT    -- 1 Fair, 2 Good, 3 Excellent Results
  url                     NVARCHAR(2000)    -- URL Connection
  recurrence              NVARCHAR(MAX)    -- JSON: every, unit, weekdays, ends
  sprint_id               BIGINT                    FK → pm.sprint
  cover_file_id           BIGINT                    FK → core.stored_file
  sort_order              INT
  closed_at               DATETIME2(0)    -- set when the status moves into the done or closed group
  is_closed_late          BIT               NN    -- completed after the due date without an approved extension (story point impact)
  UNIQUE (company_id, code)
```

```
pm.task_assignee
  task_id        BIGINT            NN  PK  FK → pm.task
  employee_id    BIGINT            NN  PK  FK → hr.employee
  story_points   INT
```

```
pm.task_dependency    -- stored as "task waits on other task"; Blocking is the same row seen from the other side
  id              BIGINT IDENTITY   NN  PK
  task_id         BIGINT            NN      FK → pm.task
  other_task_id   BIGINT            NN      FK → pm.task
  kind            NVARCHAR(30)      NN
  UNIQUE (task_id, other_task_id)
```

```
pm.tag
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  name           NVARCHAR(200)     NN
  color          NVARCHAR(20)
  UNIQUE (workspace_id, name)
```

```
pm.task_tag
  task_id   BIGINT            NN  PK  FK → pm.task
  tag_id    BIGINT            NN  PK  FK → pm.tag
```

```
pm.checklist_item
  id           BIGINT IDENTITY   NN  PK
  task_id      BIGINT            NN      FK → pm.task
  item_text    NVARCHAR(500)     NN
  is_done      BIT               NN
  sort_order   INT
```

```
pm.time_entry    -- a running timer has no end_at yet
  id            BIGINT IDENTITY   NN  PK
  task_id       BIGINT            NN      FK → pm.task
  employee_id   BIGINT            NN      FK → hr.employee
  start_at      DATETIME2(0)      NN
  end_at        DATETIME2(0)
  minutes       INT
  notes         NVARCHAR(MAX)
```

```
pm.task_comment
  id               BIGINT IDENTITY   NN  PK
  task_id          BIGINT            NN      FK → pm.task
  author_id        BIGINT            NN      FK → hr.employee
  body             NVARCHAR(MAX)     NN
  parent_id        BIGINT                    FK → pm.task_comment    -- reply
  assigned_to_id   BIGINT                    FK → hr.employee    -- Assigned to ... by ...
  assigned_by_id   BIGINT                    FK → hr.employee
  resolved_by_id   BIGINT                    FK → hr.employee    -- Mark as Resolve
  resolved_at      DATETIME2(0)
  edited_at        DATETIME2(0)
```

```
pm.comment_mention    -- @person or #task in a comment
  id                  BIGINT IDENTITY   NN  PK
  comment_id          BIGINT            NN      FK → pm.task_comment
  employee_id         BIGINT                    FK → hr.employee
  mentioned_task_id   BIGINT                    FK → pm.task
```

```
pm.comment_reaction    -- like or emoji, one per person per comment
  comment_id    BIGINT            NN  PK  FK → pm.task_comment
  employee_id   BIGINT            NN  PK  FK → hr.employee
  reaction      NVARCHAR(30)      NN
```

```
pm.reminder    -- stored only; nothing is sent yet
  id                      BIGINT IDENTITY   NN  PK
  workspace_id            BIGINT            NN      FK → pm.workspace
  entity_type             NVARCHAR(50)      NN    -- task, task_list, workspace
  entity_id               BIGINT            NN
  name                    NVARCHAR(200)     NN
  owner_id                BIGINT            NN      FK → hr.employee
  assignee_id             BIGINT                    FK → hr.employee
  remind_at               DATETIME2(0)      NN
  notify_before_minutes   INT
  reminder_kind           NVARCHAR(30)    -- soft, hard
  notified_at             DATETIME2(0)
```

```
pm.task_extension    -- Request Extension: one per task; approved keeps story points
  id                BIGINT IDENTITY   NN  PK
  task_id           BIGINT            NN      FK → pm.task
  requested_by_id   BIGINT            NN      FK → hr.employee
  old_due_date      DATE
  new_due_date      DATE              NN
  reason            NVARCHAR(MAX)
  status            NVARCHAR(30)      NN
  decided_by_id     BIGINT                    FK → hr.employee
  decided_at        DATETIME2(0)
  remarks           NVARCHAR(MAX)
  request_id        BIGINT                    FK → req.request
```

```
pm.custom_field    -- Add Fields
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  name           NVARCHAR(200)     NN
  field_type     NVARCHAR(30)      NN
  description    NVARCHAR(MAX)
  config         NVARCHAR(MAX)
  sort_order     INT
  UNIQUE (workspace_id, name)
```

```
pm.column_permission    -- Set Role Permission on a List view column; blank role and person = the workspace default
  id                 BIGINT IDENTITY   NN  PK
  workspace_id       BIGINT            NN      FK → pm.workspace
  column_key         NVARCHAR(50)      NN    -- built-in column key, or cf_<custom_field id>
  member_role        NVARCHAR(30)    -- blank, or one workspace role
  employee_id        BIGINT                    FK → hr.employee    -- a custom permission for one member
  permission_level   NVARCHAR(30)      NN    -- can_edit, can_view, private
```

```
pm.task_field_value
  task_id           BIGINT            NN  PK  FK → pm.task
  custom_field_id   BIGINT            NN  PK  FK → pm.custom_field
  field_value       NVARCHAR(MAX)
```

```
pm.list_view    -- views of a workspace (task_list_id blank) or of one list
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  task_list_id   BIGINT                    FK → pm.task_list
  owner_id       BIGINT                    FK → hr.employee
  view_type      NVARCHAR(30)      NN
  name           NVARCHAR(200)     NN
  config         NVARCHAR(MAX)
  is_pinned      BIT               NN
  is_private     BIT               NN
  is_protected   BIT               NN
  is_default     BIT               NN
  is_required    BIT               NN
  sort_order     INT
```

```
pm.share_link    -- Sharing and Permissions; stored, nothing is sent
  id                 BIGINT IDENTITY   NN  PK
  workspace_id       BIGINT            NN      FK → pm.workspace
  entity_type        NVARCHAR(50)      NN    -- task, task_list, workspace
  entity_id          BIGINT            NN
  share_scope        NVARCHAR(30)    -- list (single list view), page (whole page)
  token              NVARCHAR(100)     NN
  is_public          BIT               NN    -- Share link with anyone
  allow_open_tasks   BIT               NN
  valid_from         DATETIME2(0)
  valid_to           DATETIME2(0)
  max_access         INT
  access_count       INT
  properties         NVARCHAR(MAX)    -- JSON: task properties shown
  UNIQUE (token)
  UNIQUE (entity_type, entity_id)
```

```
pm.share_member
  id              BIGINT IDENTITY   NN  PK
  share_link_id   BIGINT            NN      FK → pm.share_link
  employee_id     BIGINT                    FK → hr.employee
  email           NVARCHAR(254)
  access_level    NVARCHAR(30)      NN
```

```
pm.favorite    -- Add to Favorites and Hide, per person
  id            BIGINT IDENTITY   NN  PK
  employee_id   BIGINT            NN      FK → hr.employee
  entity_type   NVARCHAR(50)      NN
  entity_id     BIGINT            NN
  kind          NVARCHAR(30)      NN
  UNIQUE (employee_id, entity_type, entity_id, kind)
```

```
pm.doc    -- not in the first build (no design)
  id             BIGINT IDENTITY   NN  PK
  workspace_id   BIGINT            NN      FK → pm.workspace
  title          NVARCHAR(200)     NN
  body           NVARCHAR(MAX)
  visibility     NVARCHAR(30)
```

```
pm.note    -- not in the first build (no design)
  id            BIGINT IDENTITY   NN  PK
  owner_id      BIGINT            NN      FK → hr.employee
  title         NVARCHAR(200)     NN
  body          NVARCHAR(MAX)
  archived_at   DATETIME2(0)
```

Relationships:
```
template 1──* template_item
workspace 1──* folder 1──* task_list 1──* task 1──* task (subtask)
workspace *──* employee (workspace_member)
workspace 1──* workspace_status / workspace_feature / tag / custom_field / column_permission / list_view
task *──* employee (task_assignee)
task 1──* time_entry / task_comment / checklist_item / task_dependency / task_extension
task_comment 1──* comment_mention / comment_reaction
custom_field 1──* task_field_value
share_link 1──* share_member
```

---

## 16. Warnings  (`att`)

```
att.warning_policy    -- Warning -> Policy
  id               BIGINT IDENTITY   NN  PK
  company_id       BIGINT            NN      FK → org.company
  title            NVARCHAR(200)     NN
  applies_to       NVARCHAR(30)      NN    -- late_arrival, early_departure, overtime, half_day_leave
  period           NVARCHAR(30)      NN    -- day, week, month, year
  grace_minutes    INT    -- Total Grace Minutes in a period before days count
  week_start_day   NVARCHAR(30)
  week_end_day     NVARCHAR(30)
  is_active        BIT               NN
  UNIQUE (company_id, title)
```

```
att.warning_policy_rule    -- one per clock event
  id                  BIGINT IDENTITY   NN  PK
  warning_policy_id   BIGINT            NN      FK → att.warning_policy
  clock_event         NVARCHAR(30)      NN
  minutes             INT               NN
  occurrence_count    INT               NN
  UNIQUE (warning_policy_id, clock_event)
```

```
att.penalty_rule    -- Warning -> Penalty: what the n-th warning in a period costs
  id                  BIGINT IDENTITY   NN  PK
  warning_policy_id   BIGINT            NN      FK → att.warning_policy
  after_count         INT               NN
  period              NVARCHAR(30)      NN    -- week, month, year
  penalty_type        NVARCHAR(30)      NN    -- half_day, full_day, percentage
  percentage          DECIMAL(5,2)      NN    -- share of a day: 50, 100 or the given percentage
  deduction           NVARCHAR(30)      NN    -- payroll, leave, both
  leave_type_id       BIGINT                    FK → lv.leave_type    -- the balance a leave deduction is taken from
  UNIQUE (warning_policy_id, period, after_count)
```

```
att.warning    -- a warning actually raised (att.usp_warning_raise)
  id                       BIGINT IDENTITY   NN  PK
  company_id               BIGINT            NN      FK → org.company
  employee_id              BIGINT            NN      FK → hr.employee
  warning_policy_id        BIGINT            NN      FK → att.warning_policy
  warning_policy_rule_id   BIGINT            NN      FK → att.warning_policy_rule
  timesheet_day_id         BIGINT            NN      FK → att.timesheet_day
  work_date                DATE              NN
  minutes                  INT    -- minutes measured that day
  occurrence_no            INT    -- n-th occurrence in the policy period
  penalty_rule_id          BIGINT                    FK → att.penalty_rule
  penalty_type             NVARCHAR(30)
  penalty_percentage       DECIMAL(5,2)
  deduction                NVARCHAR(30)    -- payroll, leave, both
  payslip_id               BIGINT                    FK → pay.payslip    -- where the penalty was deducted
  UNIQUE (warning_policy_rule_id, timesheet_day_id)
```

Relationships:
```
warning_policy 1──* warning_policy_rule / penalty_rule / warning
timesheet_day 1──* warning
warning 1──0..1 leave_ledger   (leave deductions)
```

---

## 17. Benefits  (`ben`)

```
ben.plan_year    -- "Benefit Plan Years"
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  name                  NVARCHAR(200)     NN
  start_date            DATE              NN
  end_date              DATE              NN
  new_hire_start        NVARCHAR(30)      NN    -- immediately, waiting_period, per_employee
  waiting_period_days   INT    -- when new_hire_start = waiting_period
  election_period       INT               NN    -- "How long do new employees have to complete elections?"
  election_unit         NVARCHAR(10)      NN    -- day, week, month
  UNIQUE (company_id, name)
```

```
ben.benefit_plan    -- "Benefit Plans" (Add {Category} Plan)
  id              BIGINT IDENTITY   NN  PK
  company_id      BIGINT            NN      FK → org.company
  category        NVARCHAR(30)      NN    -- medical, dental, vision, retirement, hsa, life, others
  name            NVARCHAR(200)     NN
  plan_type       NVARCHAR(100)    -- EPO, HMO, PPO ... per category
  plan_type_ref   NVARCHAR(50)    -- "Plan Type ID"
  carrier         NVARCHAR(200)
  start_date      DATE              NN
  end_date        DATE              NN
  description     NVARCHAR(MAX)
  status          NVARCHAR(30)      NN    -- active, inactive
  UNIQUE (company_id, name)
```

```
ben.plan_year_plan    -- the plans offered in a year (many to many)
  plan_year_id      BIGINT            NN  PK  FK → ben.plan_year
  benefit_plan_id   BIGINT            NN  PK  FK → ben.benefit_plan
```

```
ben.enrollment_window    -- "New Open Enrollment Window" (also Qualifying Life Event, New Hire)
  id               BIGINT IDENTITY   NN  PK
  company_id       BIGINT            NN      FK → org.company
  plan_year_id     BIGINT            NN      FK → ben.plan_year
  kind             NVARCHAR(30)      NN    -- open_enrollment, life_event, new_hire
  name             NVARCHAR(200)     NN
  effective_date   DATE              NN    -- inside the plan year
  closes_on        DATE              NN    -- the last day to enrol; open until then
  description      NVARCHAR(MAX)
```

```
ben.enrollment_window_plan
  enrollment_window_id   BIGINT            NN  PK  FK → ben.enrollment_window
  benefit_plan_id        BIGINT            NN  PK  FK → ben.benefit_plan
```

```
ben.enrollment_window_employee    -- none listed = everyone
  enrollment_window_id   BIGINT            NN  PK  FK → ben.enrollment_window
  employee_id            BIGINT            NN  PK  FK → hr.employee
```

```
ben.election    -- an employee's elections for a plan year ("Employee Elections")
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  employee_id            BIGINT            NN      FK → hr.employee
  plan_year_id           BIGINT            NN      FK → ben.plan_year
  enrollment_window_id   BIGINT                    FK → ben.enrollment_window
  status                 NVARCHAR(30)      NN    -- incomplete, pending, approved, rejected, waived
  submitted_at           DATETIME2(0)
  decided_by_user_id     BIGINT                    FK → auth.user_account
  decided_at             DATETIME2(0)
  remarks                NVARCHAR(MAX)
  UNIQUE (employee_id, plan_year_id)
```

```
ben.election_plan
  election_id       BIGINT            NN  PK  FK → ben.election
  benefit_plan_id   BIGINT            NN  PK  FK → ben.benefit_plan
```

```
ben.health_benefit    -- "Health Benefits": the insurance an employee holds
  id                  BIGINT IDENTITY   NN  PK
  company_id          BIGINT            NN      FK → org.company
  employee_id         BIGINT            NN      FK → hr.employee
  insurer             NVARCHAR(200)
  policy_no           NVARCHAR(50)
  coverage_amount     DECIMAL(18,2)    -- the cover
  life_cover_amount   DECIMAL(18,2)    -- "Life Cover"
  annual_payment      DECIMAL(18,2)    -- "Annual Payment"
  start_date          DATE
  end_date            DATE
  status              NVARCHAR(30)      NN    -- availed, not_availed
  remarks             NVARCHAR(MAX)
  document_file_id    BIGINT                    FK → core.stored_file    -- the policy document or insurance card (an upload)
```

```
ben.perk    -- "Perks": occasion gifts
  id            BIGINT IDENTITY   NN  PK
  company_id    BIGINT            NN      FK → org.company
  employee_id   BIGINT            NN      FK → hr.employee
  occasion      NVARCHAR(30)      NN    -- eid_ul_adha, eid_ul_fitr, birthday, ramadan, new_year
  perk_date     DATE              NN
  description   NVARCHAR(MAX)
  amount        DECIMAL(18,2)
  status        NVARCHAR(30)      NN    -- availed, not_availed
  UNIQUE (employee_id, occasion, perk_date)
```

Relationships:
```
plan_year 1──* plan_year_plan *──1 benefit_plan
plan_year 1──* enrollment_window 1──* enrollment_window_plan / enrollment_window_employee
plan_year 1──* election 1──* election_plan *──1 benefit_plan
employee 1──* election / health_benefit / perk
```

---

## 18. Performance  (`perf`)

```
perf.rating_scale    -- Performance settings -> Rating Scales (1 Unsatisfactory ... 5 Outstanding)
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  is_default   BIT               NN    -- the scale a new appraisal form starts with
  is_active    BIT               NN
  UNIQUE (company_id, name)
```

```
perf.rating_scale_level    -- one step on a scale; ratings may fall between steps
  id                BIGINT IDENTITY   NN  PK
  rating_scale_id   BIGINT            NN      FK → perf.rating_scale
  score             DECIMAL(5,2)      NN
  label             NVARCHAR(100)     NN
  description       NVARCHAR(MAX)
  UNIQUE (rating_scale_id, score)
```

```
perf.kpi    -- Performance -> KPIs: the KPI library, grouped by key result area
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  name              NVARCHAR(200)     NN
  key_result_area   NVARCHAR(200)    -- the KRA the KPI belongs to (Sales, Quality, People ...)
  description       NVARCHAR(MAX)
  measure_type      NVARCHAR(30)    -- percentage, number, amount, rating, yes_no
  target_value      DECIMAL(18,2)
  unit              NVARCHAR(30)
  default_weight    DECIMAL(5,2)
  department_id     BIGINT                    FK → org.department    -- optional; suggested for this department
  job_title_id      BIGINT                    FK → org.job_title    -- optional; suggested for this job title
  is_active         BIT               NN
  UNIQUE (company_id, name)
```

```
perf.appraisal_form    -- Performance settings -> Appraisal Forms: what a cycle rates and the weights
  id                BIGINT IDENTITY   NN  PK
  company_id        BIGINT            NN      FK → org.company
  name              NVARCHAR(200)     NN
  description       NVARCHAR(MAX)
  rating_scale_id   BIGINT            NN      FK → perf.rating_scale
  goals_weight      DECIMAL(5,2)      NN
  has_self_review   BIT               NN    -- employees rate themselves before their manager does
  is_active         BIT               NN
  UNIQUE (company_id, name)
```

```
perf.appraisal_criterion    -- a line on a form: a KPI from the library or a competency written on the form
  id                  BIGINT IDENTITY   NN  PK
  appraisal_form_id   BIGINT            NN      FK → perf.appraisal_form
  kpi_id              BIGINT                    FK → perf.kpi    -- optional
  name                NVARCHAR(200)     NN
  description         NVARCHAR(MAX)
  weight              DECIMAL(5,2)      NN
  sort_order          INT
```

```
perf.appraisal_cycle    -- Performance -> Appraisals: one review round ("Annual 2026")
  id                        BIGINT IDENTITY   NN  PK
  company_id                BIGINT            NN      FK → org.company
  name                      NVARCHAR(200)     NN
  appraisal_form_id         BIGINT            NN      FK → perf.appraisal_form    -- fixed once the cycle is launched
  start_date                DATE              NN    -- the period under review
  end_date                  DATE              NN
  self_review_due_date      DATE
  manager_review_due_date   DATE
  status                    NVARCHAR(30)      NN    -- draft, active, closed
  launched_at               DATETIME2(0)
  closed_at                 DATETIME2(0)
  UNIQUE (company_id, name)
```

```
perf.appraisal    -- one employee in one cycle: self review, manager review, final rating, outcome
  id                     BIGINT IDENTITY   NN  PK
  company_id             BIGINT            NN      FK → org.company
  appraisal_cycle_id     BIGINT            NN      FK → perf.appraisal_cycle
  employee_id            BIGINT            NN      FK → hr.employee
  reviewer_employee_id   BIGINT                    FK → hr.employee    -- the line manager when the person joined the cycle
  status                 NVARCHAR(30)      NN    -- draft, self_review, manager_review, reviewed, finalised
  goals_score            DECIMAL(5,2)
  self_score             DECIMAL(5,2)
  manager_score          DECIMAL(5,2)
  final_score            DECIMAL(5,2)
  final_rating_label     NVARCHAR(100)    -- the scale level nearest the final score
  self_comments          NVARCHAR(MAX)
  manager_comments       NVARCHAR(MAX)
  final_comments         NVARCHAR(MAX)
  development_needs      NVARCHAR(MAX)    -- training the manager recommends (read by Training)
  outcome                NVARCHAR(30)    -- no_change, increment, promotion, improvement_plan
  self_submitted_at      DATETIME2(0)
  manager_submitted_at   DATETIME2(0)
  finalised_at           DATETIME2(0)
  finalised_by_user_id   BIGINT                    FK → auth.user_account
  letter_file_id         BIGINT                    FK → core.stored_file    -- the appraisal letter (Documents: "Appraisal Letter")
  UNIQUE (appraisal_cycle_id, employee_id)
```

```
perf.appraisal_rating    -- one criterion rated on one appraisal, by the employee and by the manager
  id                       BIGINT IDENTITY   NN  PK
  appraisal_id             BIGINT            NN      FK → perf.appraisal
  appraisal_criterion_id   BIGINT            NN      FK → perf.appraisal_criterion
  self_rating              DECIMAL(5,2)
  manager_rating           DECIMAL(5,2)
  self_comment             NVARCHAR(MAX)
  manager_comment          NVARCHAR(MAX)
  UNIQUE (appraisal_id, appraisal_criterion_id)
```

```
perf.goal    -- My Performance -> Goals (Goal Name, Due Date, Completed); project tasks link to goals
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  employee_id          BIGINT            NN      FK → hr.employee
  appraisal_cycle_id   BIGINT                    FK → perf.appraisal_cycle    -- optional; the cycle it counts in (otherwise the cycle its due date falls in)
  kpi_id               BIGINT                    FK → perf.kpi    -- optional
  title                NVARCHAR(200)     NN    -- Goal Name
  description          NVARCHAR(MAX)
  start_date           DATE
  due_date             DATE              NN
  weight               DECIMAL(5,2)      NN
  target_value         DECIMAL(18,2)
  actual_value         DECIMAL(18,2)
  progress             DECIMAL(5,2)      NN
  status               NVARCHAR(30)      NN    -- not_started, in_progress, completed, cancelled
  completed_at         DATETIME2(0)
  set_by_user_id       BIGINT                    FK → auth.user_account
```

```
perf.goal_check_in    -- a progress update on a goal (its history)
  id             BIGINT IDENTITY   NN  PK
  goal_id        BIGINT            NN      FK → perf.goal
  progress       DECIMAL(5,2)      NN
  actual_value   DECIMAL(18,2)
  status         NVARCHAR(30)      NN
  comments       NVARCHAR(MAX)
```

```
perf.increment_proposal    -- an increment a finalised appraisal proposes; applied as payroll's salary revision
  id                   BIGINT IDENTITY   NN  PK
  company_id           BIGINT            NN      FK → org.company
  appraisal_id         BIGINT            NN      FK → perf.appraisal
  employee_id          BIGINT            NN      FK → hr.employee
  change_type          NVARCHAR(30)      NN    -- flat, percent (as pay.usp_salary_revision_save)
  change_value         DECIMAL(18,2)     NN
  effective_date       DATE              NN
  current_salary       DECIMAL(18,2)    -- the salary in force on the effective date when proposed
  proposed_salary      DECIMAL(18,2)
  status               NVARCHAR(30)      NN    -- proposed, applied, rejected
  employee_salary_id   BIGINT                    FK → hr.employee_salary    -- the salary revision written when applied
  decided_at           DATETIME2(0)
  decided_by_user_id   BIGINT                    FK → auth.user_account
  remarks              NVARCHAR(MAX)
  UNIQUE (appraisal_id)
```

Relationships:
```
rating_scale 1──* rating_scale_level
rating_scale 1──* appraisal_form 1──* appraisal_criterion *──0..1 kpi
appraisal_form 1──* appraisal_cycle 1──* appraisal *──1 employee
appraisal 1──* appraisal_rating *──1 appraisal_criterion
employee 1──* goal *──0..1 appraisal_cycle / kpi
goal 1──* goal_check_in
appraisal 1──0..1 increment_proposal ──> employee_salary   (payroll's salary revision)
```

---

## 19. Training  (`trn`)

```
trn.training_category    -- Training settings -> Categories (Technical, Soft skills, Compliance, HSE)
  id           BIGINT IDENTITY   NN  PK
  company_id   BIGINT            NN      FK → org.company
  name         NVARCHAR(200)     NN
  is_active    BIT               NN
  UNIQUE (company_id, name)
```

```
trn.training_program    -- Training -> Programs: a course the company runs or buys
  id                            BIGINT IDENTITY   NN  PK
  company_id                    BIGINT            NN      FK → org.company
  title                         NVARCHAR(200)     NN
  training_category_id          BIGINT                    FK → trn.training_category    -- optional
  description                   NVARCHAR(MAX)
  delivery_mode                 NVARCHAR(30)    -- classroom, online, blended, on_the_job
  provider_type                 NVARCHAR(30)    -- internal, external
  provider_name                 NVARCHAR(200)
  duration_hours                DECIMAL(6,2)
  cost_per_head                 DECIMAL(18,2)
  issues_certificate            BIT               NN
  certificate_validity_months   INT    -- a certificate expires after this many months; empty = never
  is_mandatory                  BIT               NN
  is_active                     BIT               NN
  UNIQUE (company_id, title)
```

```
trn.training_session    -- Training -> Sessions: one scheduled run of a program
  id                    BIGINT IDENTITY   NN  PK
  company_id            BIGINT            NN      FK → org.company
  training_program_id   BIGINT            NN      FK → trn.training_program
  title                 NVARCHAR(200)     NN    -- the program's title unless given
  start_date            DATE              NN
  end_date              DATE              NN
  start_time            TIME(0)
  end_time              TIME(0)
  delivery_mode         NVARCHAR(30)    -- classroom, online
  venue                 NVARCHAR(300)
  online_link           NVARCHAR(500)
  trainer_type          NVARCHAR(30)    -- internal, external
  trainer_employee_id   BIGINT                    FK → hr.employee    -- an internal trainer
  trainer_name          NVARCHAR(200)    -- an external trainer
  capacity              INT    -- seats; empty = no limit
  nomination_deadline   DATE
  status                NVARCHAR(30)      NN    -- scheduled, completed, cancelled
  cost                  DECIMAL(18,2)
  cancel_reason         NVARCHAR(MAX)
  completed_at          DATETIME2(0)
  cancelled_at          DATETIME2(0)
```

```
trn.training_enrolment    -- a nomination or a seat on a session, and its result
  id                        BIGINT IDENTITY   NN  PK
  company_id                BIGINT            NN      FK → org.company
  training_session_id       BIGINT            NN      FK → trn.training_session
  employee_id               BIGINT            NN      FK → hr.employee
  status                    NVARCHAR(30)      NN    -- requested, enrolled, rejected, withdrawn, cancelled, completed, not_completed
  nomination_source         NVARCHAR(30)    -- self, manager, hr
  nominated_by_user_id      BIGINT                    FK → auth.user_account
  decided_by_user_id        BIGINT                    FK → auth.user_account
  decided_at                DATETIME2(0)
  decision_remarks          NVARCHAR(MAX)
  attendance_percent        DECIMAL(5,2)
  score                     DECIMAL(5,2)
  result_remarks            NVARCHAR(MAX)
  completed_at              DATETIME2(0)
  certificate_file_id       BIGINT                    FK → core.stored_file
  certificate_no            NVARCHAR(100)
  certificate_issued_date   DATE
  certificate_expiry_date   DATE
  UNIQUE (training_session_id, employee_id)
```

```
trn.training_attendance    -- attendance per day of a session
  id                      BIGINT IDENTITY   NN  PK
  training_enrolment_id   BIGINT            NN      FK → trn.training_enrolment
  attendance_date         DATE              NN
  status                  NVARCHAR(30)      NN
  remarks                 NVARCHAR(MAX)
  UNIQUE (training_enrolment_id, attendance_date)
```

```
trn.training_feedback    -- the participant's evaluation of a session (1-5)
  id                      BIGINT IDENTITY   NN  PK
  training_enrolment_id   BIGINT            NN      FK → trn.training_enrolment
  overall_rating          INT               NN
  trainer_rating          INT
  content_rating          INT
  comments                NVARCHAR(MAX)
  UNIQUE (training_enrolment_id)
```

Relationships:
```
training_category 1──* training_program 1──* training_session 1──* training_enrolment *──1 employee
training_enrolment 1──* training_attendance
training_enrolment 1──0..1 training_feedback
training_program 1──* attachment   (materials)
```

---

## Not in the first build

Left out until someone defines them. Nothing above depends on them. Each module's own gaps are in `comparison/`.

| Item | Why |
|---|---|
| Recruitment (`rec` tables) | Placeholder in the designs; no screens built; tables kept for later |
| Requisition and Expense requests | Only menu items; no fields defined |
| Performance (KPIs, appraisals), Training, Custom Forms, Configuration | Menu items only |
| Employee contract, education, dependents, skills, documents | Profile tabs; need file storage, most have no design |
| Engagement newsfeed and surveys (`eng` tables except announcements) | No screens in the frontend yet |
| Project sprints, docs, notes | Marked skipped in the design |
| Customer control database, subscriptions, invoices | Comes when a second customer database is added |
| Finance dashboard (FDO) | Display only, one client |
