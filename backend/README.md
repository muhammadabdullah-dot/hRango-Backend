# HRango backend

FastAPI on SQL Server. Layered, and procedural: every read and write is a stored procedure. There
are no ORM models.

## Folders

```
app/
  routers/<module>.py        URLs and verbs; which permission each endpoint needs (require(...))
  controllers/<module>_controller.py   HTTP shape: envelopes, rowVersion text <-> bytes, rows -> response models
  services/<module>_service.py         business rules; anything spanning several procedures (db.transaction())
  repos/<module>_repo.py     the only place that knows procedure names and parameters
  schemas/<module>.py        request/response bodies (camelCase JSON, snake_case Python, ids as strings)
  catalogue/<module>.py      the module's permission codes (one per view or button)
  middlewares/               auth (who is calling + require), errors, request log
  core/                      config, db (procedure caller), errors, paging, rowversion, security,
                             permissions (catalogue loader), default_roles, logging
db/
  migrations/                DDL, applied once each in name order; 0001_baseline.sql is generated from the ERD
  procedures/<schema>/       fn_*.sql then usp_*.sql, CREATE OR ALTER, re-applied on every seed
  seeds/                     reference data, idempotent, re-applied on every seed
scripts/seed.py              installs or updates a whole database
scripts/nightly.py           the nightly jobs: attendance processing, document expiry reminders, project tasks due
                             tomorrow or overdue, unused uploads
scripts/process_attendance.py  re-processes attendance time sheets for any date range
scripts/webhooks.py          delivers webhooks as its own service (instead of the API's worker)
uploads/                     uploaded files (UPLOAD_DIR); back it up with the database
tests/                       pytest against a real *_dev database; factories.py makes test records
```

A request runs router -> controller -> service -> repo -> `EXEC schema.usp_...`.
`organisation` / Departments (`/api/organisation/departments`) is the worked example of every layer,
and `tests/test_departments.py` its test.

## API contract

- Everything is under `/api`. JSON is camelCase. Ids are strings (BIGINT in the database).
- One item: `{"data": {...}}`. A list: `{"data": [...], "meta": {"page", "pageSize", "total", "totalPages"}}`
  (`schemas/common.py`: `Item`, `Paginated`, `paginated()`). Paging is `?page=1&pageSize=10`, max 100
  (`core/paging.py`). Search is `?q=`.
- Errors: `{"message": "...", "code": "UPPER_SNAKE", "fieldErrors": {"fieldName": "..."}}` with
  401 / 403 / 404 / 409 / 422. Raise `AppError` (`core/errors.py`) in Python, or THROW in a procedure.
- Create `POST` 201, edit `PUT` (or `PATCH` for a partial action), delete `DELETE` 204. Edits and
  deletes send the `rowVersion` last read (body, or `?rowVersion=` on delete).
- Sign-in: `POST /api/auth/login {email, password}` -> `{data: {token, user}}`; `GET /api/auth/me`;
  `POST /api/auth/logout`. Send `Authorization: Bearer <token>`. `X-Company-Id` switches the active
  company to another one the user belongs to.
- Employee status filters on the Attendance lists (`employeeStatus`: overview, time sheet and their exports) and the
  Payroll lists (`employmentStatus`: payslips, final settlements; "Add Matching" of a payroll): `active` is everyone
  employed (active, probation, notice), `inactive` everyone switched off or gone (inactive, left), any other value
  one status. Scheduling and the employee directory filter one status. (Test Run rows S1.76 / S1.77: "Active Staff"
  had left out everyone on probation.)
- "Today" on a dashboard is the company's today (its time zone, `att.fn_company_now`), as on the time sheet and the
  clock, not UTC's. The attendance figures (`present`, `clockedIn`, `notStarted`, `dayOff`, `rowCount`) count every
  time sheet row of the day; `rows` lists them earliest arrival first, up to 1000.

## Permissions (RBAC)

- Every endpoint depends on `require("module.screen.action")` (`middlewares/auth.py`). Codes are listed
  in `app/catalogue/<module>.py` as screens with actions; `require` refuses at start-up a code that is
  not in the catalogue. Settings screens are `module.settings.<tab>`. Approving is `approve` /
  `reject`. Action names are in `app/catalogue/_actions.py`.
- A permission is held with scopes: own, team (direct and indirect reports), department (and
  sub-departments), branch, selected_units, company. `require` returns the context with `ctx.scopes`.
- For employee-owned records, procedures filter with
  `JOIN auth.fn_visible_employees(@company_id, @actor_user_id, N'<code>') v ON v.employee_id = x.employee_id`.
  Pass the same code the endpoint required. A "My / Subordinates / All" tab is a filter on top of that.
- Default roles (`core/default_roles.py`): Company Administrator, HR Manager, HR Officer, Payroll Manager,
  Finance, Department Head, Line Manager, Recruiter, Executive, Employee. They are patterns over the
  codes, so a module's codes reach the right roles by following the naming above. Sensitive codes
  (salary, bank, CNIC, loans, payslips) are held back from managers except for their own records.
  Executives see pay (`EXECUTIVE_PAY`), not CNIC, bank or health details.
- hRango's own staff are not customers: `/api/platform` with their own accounts (`plat`), tokens and roles
  (Super Admin, Admin, Support, Billing); see `../comparison/17-platform.md`. There is no account that reaches
  every company: a customer's administrator stays inside their company. Every staff action in the Activity Log
  (`plat.staff_audit`) has a `detail` naming the record it changed: the organisation suspended or reactivated, the
  invoice number and organisation of an invoice issued, paid or voided, whose subscription on which plan, the lead's
  company, the ticket's organisation and subject, the staff member's name and role.
- Users get extra grants or denials per company; a denial wins.
- The directory (`employees.directory.view`) shows a colleague's work details. Personal details (phones, home
  address, date of birth, family) need `employees.personal.view`: everyone holds it for themselves, HR for the
  company. The API blanks those fields and sends `canSeePersonal: false`; an edit by someone without it keeps them.
- `/auth/me` `role` names the person's real role: Employee, which everyone also holds, only when it is all they hold.
- Who may decide a request comes from its flow (ACC-13), so every role holds the approval actions. The approver a
  flow names sees and decides the request through `/requests/approvals...` whatever their role's permissions for
  the type (a Department Head on a promotion); `GET /requests/approvals/summary` lists the types they have
  approvals of (total, waiting), which the web app's menus show.
- Reading and deciding can be scoped apart. Manpower budgets: Finance reads every department's (`budget_approvals
  .view`, company) while a department head decides their own (`.approve` / `.reject`, department); each budget row
  carries `canApprove` / `canReject` for the caller, and deciding one the caller reads but may not decide is 403 with
  the department named (one they cannot read is 404).

## Files

- Upload first: `POST /api/files` (multipart: `file`, `module`) -> `{data: {id, name, mimeType, sizeBytes, url}}`.
  Any signed-in user may upload. Types are whitelisted and checked by their first bytes; size up to
  `MAX_UPLOAD_MB`. Bytes go to `<UPLOAD_DIR>/<company>/<module>/<yyyy>/<mm>/<uuid>.<ext>` (`app/core/files.py`);
  the database keeps `core.stored_file`.
- Forms then send the file id. Procedures check it belongs to the company:
  `IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.fn_file_usable(@company_id, @file_id)) THROW 50400, N'fileId|...', 1;`
- One file on a record: a `<thing>_file_id FK stored_file` column. Several: `core.attachment` rows
  (`company_id`, `entity_type` = `'<schema>.<table>'`, `entity_id`, `file_id`, `label`).
- Responses never expose paths. Give the id, the name and a signed link for records the caller may read:
  `app.core.files.file_url(file_id, ctx.company_id)` (or `schemas.files.FileRef`). Links expire
  (`FILE_LINK_MINUTES`) and work without the Authorization header. Set `PUBLIC_BASE_URL` to this API's address when
  the frontend is served from another one, or links are relative to the frontend and images do not load.
- A file a record still uses cannot be deleted (its foreign keys and attachments refuse).

## Events, notifications and webhooks

- Tell people in the inbox with `core.usp_notification_add` (a user) or `core.usp_notification_add_employee`
  (an employee's accounts); from inside another procedure pass `@quiet = 1` (no result set, so never
  `INSERT ... EXEC`). Every notification is also published as the `notification.created` event.
- A notification's `@link` is a page of the web app, with the record in a search parameter the page reads:
  requests `req.fn_request_link` (`/requests/<type>?tab=approvals&request=<id>` for an approver, `?request=<id>`
  for the requester), `/talent-management/update-requests?request=<id>`, `/my-profile?tab=documents`,
  `/performance/reviews?review=<id>`, `/recruitment/offers?view=<id>` ... `tests/test_notification_links.py` lists
  every link shape the procedures write and fails on one the web app has no page for; keep it in line with the
  frontend's `src/features/inbox/notification-links.test.ts`. Engagement and Training links name records the web
  app has no pages for yet (its inbox does not offer to open them). Migration 0009 rewrote the links sent before.
- Publish what happened, in the same transaction as the change:
  `EXEC core.usp_event_publish @company_id, @event_type, @entity_type, @entity_id, @payload` (JSON, camelCase,
  ids as strings). Event types start with the module key: `requests.approved`, `recruitment.candidate_hired`.
  List them in `EVENTS = [(type, description)]` in `app/catalogue/<module>.py`.
- Webhooks (Settings -> Integrations, `/api/integrations/webhooks`) subscribe to types, `module.*` or `*`.
  Deliveries are signed (`X-HRango-Signature: sha256=HMAC(secret, "<timestamp>.<body>")`) and retried with
  back-off; see `app/core/events.py`. The API delivers them in a background thread (`WEBHOOK_WORKER`), or run
  `scripts/webhooks.py` as a service. The same loop sends due project reminders to the inbox once a minute.
- Mail (`app/core/mail.py`): callers `queue` a message in `core.mail_message` and the same worker loop sends what
  is due (SMTP, or `.eml` files with `MAIL_BACKEND=file`), retrying failures. With `MAIL_ENABLED=false` a message is
  recorded `disabled` and never sent. Payroll's close e-mail and salary revision letter go through it: each person
  gets their own message, `pay.mail_outbox` keeps one row per person linked to it (`mail_message_id`), and
  `mail.RESULT_OWNERS` copies each send's result back (`pay.usp_mail_outbox_result`: queued -> sent / failed, and
  the run's close e-mail state). A mail gateway can also subscribe to `notification.created`.

## AI and routes without sign-in

- AI routes (request applications, project docs and suggestions) call `app.core.ai.ensure_available()` first.
  No provider is connected (`AI_PROVIDER` blank), so they answer 503 `AI_UNAVAILABLE` and the screens keep
  their manual editors.
- `/api/public/...` works without a token (`routers/public.py`: shared project links). Each route checks its
  own token and limits; nothing else goes there.
- Shared project links (the web app's `/shared/{token}` page): `GET /api/public/shares/{token}` answers the page's
  tasks and, for a shared task, the task's own details (`task`) in the same access; `.../tasks/{taskId}` opens one
  when the link allows it (403 `SHARE_TASKS_CLOSED`). Only the properties the link shows are filled; subtasks only
  with "subtasks" (`pm.fn_share_tasks`); a link saved without properties shows everything. A refused link is 404
  `SHARE_NOT_FOUND` or 410 `SHARE_EXPIRED` / `SHARE_NOT_STARTED` / `SHARE_EXHAUSTED`; every page or task opened
  counts one access.

## Project management rules worth knowing

- Workspace roles: `POST /projects/workspaces/{id}/members` adds people with a `memberRole` (and sets the role of
  ones already there); `PATCH .../members/{employeeId}` changes a member's role and is 404 for someone who is not a
  member. Workspace admins and HR manage members; only a workspace admin gives or takes the workspace admin role;
  the owner stays a workspace admin (409).
- Mentions: a task comment mentions only people who can see the task (`pm.fn_task_viewers`, the per-employee twin
  of `pm.fn_task_access`: keep the two in step); anyone else is 422 `MENTION_NOT_ALLOWED`. `GET /projects/people
  ?taskId=` lists who can be mentioned.
- A task's checklist changes (add, tick, untick, rename, delete) are in its History (`checklist_*` actions).

## HR rules worth knowing

- Benefit elections keep the employee's note (`remarks`) and HR's remarks on the decision (`decisionRemarks`,
  migration 0041) apart; rejecting needs a reason (422 on `remarks`).
- Switching an employee off keeps the status they had (`hr.employee.status_before_inactive`, migration 0040);
  Reactivate gives it back (probation, notice), and for a record switched off before that, probation while its
  probation has not ended and nobody confirmed them, else active.
- A required Yes/No (tick box) field of the off-boarding checklist holds up the end of employment until it is ticked
  (`sep.fn_end_of_employment_waiting`): an unticked box is saved as `false`, which is not an answer.

## Procedure conventions

- Name `<schema>.usp_<table or screen>_<verb>`: `_list`, `_get`, `_save` (add when `@id` is NULL, else
  edit), `_delete`, and real verbs for actions (`_approve`, `_process`, `_close`). One procedure per
  file, or a few closely related ones in one file separated by `GO`.
- A write a double press could repeat takes an application lock on what it guards, inside its transaction, around
  the check and the insert (`sp_getapplock N'att.punch.<employee id>'`): two presses at once cannot both insert.
  Clock In / Out pressed again while the person's last punch is the same type and under five minutes old returns
  that punch (no second one); a manual punch identical to one in the log is refused (409 `PUNCH_DUPLICATE`).
- First parameters `@company_id`, then `@actor_user_id` on anything that writes or needs scope. Every
  query filters on `company_id`; another company's row is "not found".
- `SET NOCOUNT ON; SET XACT_ABORT ON;` Validate first, then `BEGIN TRAN ... COMMIT` around the writes.
- User errors are `THROW` with these numbers: `50400` -> 422, `50403` -> 403, `50404` -> 404,
  `50409` -> 409. Name the form field, and optionally a code, before a pipe:
  `THROW 50409, N'name|DEPARTMENT_DUPLICATE|A department with this name already exists.', 1;`
  gives `{"message", "code": "DEPARTMENT_DUPLICATE", "fieldErrors": {"name": ...}}`.
- Edits and deletes take `@row_version BINARY(8)` and THROW 50409 when it no longer matches.
- Lists return two result sets: the total, then the page (`OFFSET/FETCH`, `OPTION (RECOMPILE)`), read
  with `db.call_sets`. Search patterns escape `[`, `%`, `_`.
- A page that reads wide rows (a row function with long text or `FOR JSON` columns: `pm.fn_task_rows`,
  `req.fn_request_rows` with its details) also takes `MAX_GRANT_PERCENT = 1`. Those plans ask for hundreds of MB of
  sort memory for one page, and on a server short of memory a query waits for its grant until it times out: in the
  Test Run a 41-row task list took 222 s, 0.2 s of it work. Capped, it takes the few MB it needs. To find others,
  read `sys.query_store_plan` (Query Store is on by default from SQL Server 2022) for a large `SerialDesiredMemory`.
- Writes add rows to `core.audit_log` (one per changed field) where the screen has a History view.
- Child rows (lines, slabs, rules) are saved with their parent in one procedure: pass them as JSON
  (`@lines NVARCHAR(MAX)`, read with `OPENJSON`).
- Business rules that do not need the data stay in Python services; set-based work (time sheets,
  payroll runs) belongs in procedures.

## Tables

The ERD is the source of the tables: `../erd/source/NN-<module>.md`, one file per module. After an
edit run `python ../erd/build.py`; it rewrites `0001_baseline.sql`, `HRango - ERD.md` and the draw.io
file. Column types are inferred from names; override inline with `{DECIMAL(18,4)}`, `{NN}`, `{NULL}`
(no spaces inside a type), and add `UNIQUE (a, b)` or `INDEX (a, b)` as a line in the table. Until a database outside
development exists, change the ERD and `--reset` the dev database; after that, freeze the baseline
and add numbered migrations.

## The seeder

`DB_URL` (environment variable first, then `.env`) is an ODBC connection string (see `.env.example`).

```
.venv\Scripts\python.exe -m scripts.seed --create      create if missing, then bring up to date
.venv\Scripts\python.exe -m scripts.seed               bring up to date (safe any time)
.venv\Scripts\python.exe -m scripts.seed --reset       drop and recreate; only *_dev databases
.venv\Scripts\python.exe -m scripts.seed --bootstrap --company "Name" --admin-email a@b.c
                                                       first install: company, default roles, administrator
                                                       (password from HRANGO_ADMIN_PASSWORD or asked)
.venv\Scripts\python.exe -m scripts.seed --platform-admin a@b.c
                                                       the first platform Super Admin (hRango's own staff;
                                                       password from HRANGO_PLATFORM_PASSWORD or asked)
.venv\Scripts\python.exe -m scripts.seed --export hrango_install.sql
                                                       everything as one script for sqlcmd / SSMS
.venv\Scripts\python.exe -m scripts.seed --enable-row-versioning
                                                       switch READ_COMMITTED_SNAPSHOT on for an existing database
                                                       (briefly ends every connection: run it in a quiet moment)
```

Row versioning (READ_COMMITTED_SNAPSHOT) lets pages read the last committed rows instead of waiting behind a
long write such as a payroll run or an attendance process. `--create` and `--reset` switch it on for the new
database; on an existing one every seeder run warns until `--enable-row-versioning` has been run. Production
databases need it: without it the Test Run of 18 Nov 2026 saw 80-second page loads and deadlocks under load.

Each run: migrations, procedures, seeds, the permission catalogue, then default roles for every company.

Demo data (Top Edge Technologies: 2 offices, 8 departments with their heads, 26 people with line managers
and a sign-in each) on a freshly bootstrapped `*_dev` or `*_demo` database, through the API itself:

```
$env:HRANGO_ADMIN_PASSWORD = "..."; $env:HRANGO_DEMO_PASSWORD = "..."
.venv\Scripts\python.exe -m scripts.demo --admin-email <the bootstrap admin> --accounts-out ..\demo-accounts.md
.venv\Scripts\python.exe -m scripts.demo_data --admin-email <the bootstrap admin> --accounts-out ..\demo-accounts.md
```

`scripts.demo_data` adds two months of activity in every module (attendance from device punches, leaves and
requests through their approval flows, three closed payrolls, assets, a leaver, projects, newsfeed, surveys, forms,
hiring, appraisals, training), each done as the person who would do it. `--only time,leave_requests` runs some
parts; `scripts/demo_data/__init__.py` lists them in their order.

## Tests

```
$env:DB_URL = "...;Database=hrango_<something>_dev;..."
.venv\Scripts\python.exe -m scripts.seed --reset
.venv\Scripts\python.exe -m pytest
```

Tests refuse any database not named `*_dev` / `*_test`. `tests/factories.py` makes companies, branches,
departments, employees and signed-in users with given roles; module tests make their own records
(module-specific helpers go in `tests/factories_<module>.py`).

## Running

`run.bat`, or `.venv\Scripts\python.exe -m app.main` (`HOST` and `PORT` from `.env`; `HOST=0.0.0.0` opens it to the LAN). Docs at `/docs` when `APP_ENV=development` (or `API_DOCS=true`).

The API refuses to start, with a message naming each problem, when:
- `JWT_SECRET` or `FILE_LINK_SECRET` is missing, an example value such as `change-me`, or shorter than 32 characters;
- the two secrets are the same;
- `APP_ENV` is `production` (the default) and `CORS_ORIGINS` contains `*`.

Every server that ever ran with `change-me` must get two new random secrets: anyone could forge sign-ins and
download links on it.

Sign-in limits: failed passwords in the last 15 minutes pause sign-in (429 `TOO_MANY_ATTEMPTS` with
`Retry-After`) after 5 for one email from one address, 20 for one email from anywhere, or 50 from one address
against any email; the pause ends 15 minutes after the last failure. An unknown email costs the same password
check as a wrong password. Platform staff sign-in has the same limits. Behind a proxy set `FORWARDED_ALLOW_IPS`
so the limits see each caller's address, not the proxy's.

Webhooks call public addresses only: private, loopback, link-local (cloud metadata) and other internal ranges
are refused when the webhook is saved and again on every delivery; redirects are not followed; production
requires https; the receiver's reply body is not kept. `WEBHOOK_ALLOW_PRIVATE=true` (development only) lets
you test with a receiver on your own machine.

Suspending or cancelling an organisation (Platform) stops, for each of its companies: sign-in and open
sessions, switching into the company with `X-Company-Id`, webhook deliveries (they wait), nightly jobs,
project reminders and public share links (they answer 404). A company a customer creates joins that
customer, so its plan and suspension cover it.

Built-in protection: request bodies over `MAX_UPLOAD_MB` (plus 1 MB for form framing) are refused with 413
before they are read; every response carries `nosniff`, `no-referrer`, `no-store` (downloads keep their
own private caching), `X-Frame-Options: DENY` and a deny-all CSP, plus HSTS in production; a caller's
`X-Request-Id` is kept only when it is a plain token of up to 64 characters.

## Parallel work (several people or agents at once)

Each module is owned by one person at a time: its ERD file(s), `db/procedures/<schema>/`, and
`app/*/<module>*` files. Shared files (`app/core`, `app/middlewares`, `app/main.py`, `scripts/seed.py`,
`erd/build.py`, `tests/conftest.py`, `tests/factories.py`) change only by agreement.

Work in your own database and your own generated baseline, so nobody resets anyone else's:

```
$env:DB_URL = "...;Database=hrango_<you>_dev;..."
$env:HRANGO_ROUTERS = "auth,<your routers>"
.venv\Scripts\python.exe ..\erd\build.py --sql-out .work\<you>\0001_baseline.sql
.venv\Scripts\python.exe -m scripts.seed --reset --migrations-dir .work\<you> --keep-going
.venv\Scripts\python.exe -m pytest tests\test_<your module>*.py
```

`--keep-going` reports another module's half-written procedure instead of stopping.

## How modules hand work to each other

- Requests: on final approval the engine runs `<schema>.usp_request_apply_<kind> @company_id,
  @actor_user_id, @request_id` in the approval's transaction; when an approved request's cancellation is
  approved it runs `usp_request_revert_<kind>`; `usp_request_validate_<kind>` runs on submit and edit.
  leave -> lv, punch / time_window / overtime / work_from_home -> att, rest_day / shift_swap -> sch,
  promotion / transfer -> hr, resignation -> sep, loan -> loan. A THROW blocks the approval.
- Attendance: effects that change past days call `att.usp_request_reprocess` (refused on days payroll
  has frozen). Run `scripts/process_attendance.py` nightly for everything else.
- Payroll reads attendance, leave, loans and warnings, marks what it paid (`payslip_id`), freezes the
  time-sheet days it used, and on closing a final settlement calls
  `sep.usp_end_of_employment_try_complete`.
- Each module's comparison file (`../comparison/`) lists what it provides and needs.
