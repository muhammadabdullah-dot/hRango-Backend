# Platform staff and customers

Decided 2 Nov 2026. hRango has two layers of people, and nothing crosses between them by accident.

| Layer | Who | Where they sign in | Access |
|---|---|---|---|
| **Platform** | hRango's own staff: Super Admin, Admin, Support, Billing | A separate address for SaaS staff (same app, `/api/platform`) | By role, on platform screens only |
| **Organisation** | A customer's people: Company Administrator, executives, the document's 16 roles, custom roles | The normal app (`/api/auth`) | By role and scope, inside their company |

## Step 1: separate the staff (built 2 Nov 2026)

- `auth.user_account.is_system_admin` is gone. It gave one customer account every permission in every company, and
  the installer handed it to each company's first administrator. Nothing replaces it inside a customer: a Company
  Administrator holds everything in their own company and nothing outside it.
- New schema `plat` (`erd/source/21-plat.md`): `staff_account`, `staff_session`, `staff_audit`. Separate from
  `auth`, so a staff account is not a customer account and holds no company.
- Staff tokens carry `aud: platform`. A customer token is refused on `/api/platform/*` and a staff token on every
  customer route. Tests: `tests/test_platform.py`.
- Staff sign-ins last 8 hours. Staff passwords need 12 characters with letters and digits. Failed sign-ins and every
  staff change go to `plat.staff_audit`.

| Route | Who |
|---|---|
| `POST /platform/auth/login`, `GET /platform/auth/me`, `POST /platform/auth/logout` | Staff |
| `GET /platform/staff`, `GET /platform/staff/{id}`, `GET /platform/audit` | Super Admin, Admin |
| `POST /platform/staff`, `PUT /platform/staff/{id}`, `PUT /platform/staff/{id}/password` | Super Admin |

The platform cannot be locked out: nobody changes their own role or switches themselves off, and the last active
Super Admin stays one.

First Super Admin: `scripts.seed --platform-admin <email>` (password from `HRANGO_PLATFORM_PASSWORD` or asked).

Executives see salaries (open question E6): the Executive role holds pay views with company scope
(`EXECUTIVE_PAY` in `app/core/default_roles.py`). CNIC, bank, personal and health details stay private.

## Account Owner (built 2 Nov 2026)

`auth.user_account.is_account_owner`: the first administrator of a company, set by the installer. Nobody else changes
their account, and other administrators answer to them, so two administrators cannot reset each other
(`auth.fn_access_outranks`). `PATCH /access/users/{id}/account-owner` hands the role to another active Company
Administrator; only the owner can, and there is always one.

## Staff portal (built 2 Nov 2026)

Same frontend and the organisation app's shell, under `/platform` (sign-in at `/platform/login`). Schema `plat`
(`erd/source/21-plat.md`). Sample data: `python -m scripts.demo_platform`, on a `*_dev` database only.

| Module | Screen | Who |
|---|---|---|
| Dashboard | Organisations registered, subscriptions, revenue, overdue, leads, tickets, renewals due | Everyone; money only for Super Admin, Admin, Billing, and the pipeline value for Sales |
| Organisations | List, detail, register, edit, suspend, cancel, reactivate | Everyone reads; Super Admin, Admin, Sales register and edit; Super Admin, Admin change status |
| Subscriptions | One live subscription per organisation | Super Admin, Admin, Billing |
| Plans | Basic, Advanced, Premium (open question B6) | Everyone reads; Super Admin, Admin change |
| Invoices | Issue, mark paid, void; overdue from the due date | Super Admin, Admin, Billing |
| Sales | Leads by stage; a lead registers as an organisation and closes as won | Super Admin, Admin, Sales |
| Support | Tickets per organisation | Super Admin, Admin, Support |
| Staff, Activity Log | Staff accounts and everything they do | Super Admin, Admin read; Super Admin changes staff |

Rules worth knowing:

- Registering (`POST /platform/organisations`) creates the company, default roles, Account Owner and customer record
  in one transaction. It refuses a known company name or sign-in email first, because the provisioning procedures
  would otherwise reuse the company and reset that account.
- A suspended or cancelled organisation is stopped in `auth.usp_login_get` and `auth.usp_session_context`, so open
  sessions end at once. Nothing is deleted.
- Staff see head counts only. Nothing here reads a customer's HR data.
- Amounts are PKR, one currency for now. Invoices are recorded by hand: no payment gateway.

Prices in the sample data are placeholders.

## Still to build

2. **Customer above company**: the table exists (`plat.customer_company`) and an organisation can hold several
   companies, but there is no screen to add a second one. The Account Owner is still per company and moves up here.
3. **Executive templates**: CEO / MD, CFO, CTO / COO that a customer copies and adjusts. Job title is not a permission.
4. **Rest of the portal**: module switches (which modules a plan opens), trials that end on their own, renewals that
   raise invoices, a payment gateway, support access, and the separate staff address.

## Built 18 Nov 2026 (SaaS readiness, phases 0 and 1)

Operators: the API now refuses to start without `JWT_SECRET` and `FILE_LINK_SECRET` (two different random values,
32+ characters) and, with `APP_ENV=production` (the default), with `CORS_ORIGINS=*`. Every dev server's `.env`
needs `APP_ENV=development` and the two secrets. See `backend/README.md` and `.env.example`.

- **Suspension everywhere**: besides sign-in and sessions, a suspended or cancelled organisation's companies are
  refused on a company switch (`X-Company-Id`), and get no webhook deliveries, nightly jobs, project reminders or
  e-mail (they wait), and their public share links answer 404 (`plat.fn_company_blocked`).
- **Companies a customer adds join it** (`plat.customer_company` row in `org.usp_company_save`), so plan, billing
  and suspension cover them; migration 0005 links the earlier ones. HR Manager no longer creates companies;
  editing another company needs `organisation.companies.edit` there; company names are unique per organisation,
  not platform-wide. `org.usp_company_provision` no longer reuses a company by name (only the installer, `@reuse = 1`).
- **Employee limit enforced** (`plat.usp_plan_employee_check` from new employee, switch back on, rehire and the CSV
  import) over every company of the organisation; `GET /api/organisation/plan` shows plan and usage.
- **Self-service sign-up**: `GET /api/public/plans`, `POST /api/public/signup` (14-day trial; the owner finishes
  from an e-mail link). Same answer for an address that already signs in.
- **E-mail** (`core.mail_message`, `app/core/mail.py`): SMTP (any provider) or `.eml` files in development, sent and
  retried by the worker, bodies cleared once sent. Password reset by e-mail and invitations
  (`auth.user_token`, hashed tokens; `/api/auth/password/forgot`, `/password/reset`, `/links/inspect`,
  `/invite/accept`, `/api/access/users/{id}/invite`, `sendInvite` on a new user).
- **Bulk employee import**: `GET /api/employees/import/template`, `POST /api/employees/import?dryRun=` (checked first,
  all or nothing).
- **Hardening**: sign-in limits (`auth.login_attempt`), webhooks only to public addresses with no redirects and no
  kept replies, request body limit, security headers, docs off in production, account changes only by the user's
  home company and never on accounts holding more access than the actor.

**Support access rule:** platform staff see no customer HR data by default. Entering a customer needs a reason,
expires, hides salary and CNIC, and shows in that customer's audit log. Nothing in step 1 can reach a company.
