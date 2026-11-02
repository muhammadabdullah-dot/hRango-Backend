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

## Still to build

2. **Customer above company**: one customer can own several companies. The Account Owner already exists per company
   (below) and moves up to the customer here.
3. **Executive templates**: CEO / MD, CFO, CTO / COO that a customer copies and adjusts. Job title is not a permission.
4. **Platform portal** on the separate staff address: the sign-in screen, customers, plans, module switches, and
   support access.

**Support access rule:** platform staff see no customer HR data by default. Entering a customer needs a reason,
expires, hides salary and CNIC, and shows in that customer's audit log. Nothing in step 1 can reach a company.
