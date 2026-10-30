# Frontend permission codes that the backend does not have

**Fixed 30 Oct 2026** on the frontend branch `rbac-and-photos`: the screens now check the codes below, `can()` reads
`code@team` and `code@all` for scopes, and `src/app/route-access.ts` is the one list of which screens a page needs
(the sidebar and a page guard share it). Kept as the record of what changed.

Checked 29 Oct 2026: the frontend on `main` (after PR #2) against the backend's catalogue
(`backend/app/core/permissions.py`, `app/catalogue/*.py`) and the codes each route requires. Thirty-seven
codes the screens check do not exist, so with a real sign-in those buttons stay hidden for everyone. The
backend is the authority here: the screens should check the code the route requires (right column).

Screen prefixes the frontend builds codes from (`payroll.settings.general`, `requests.settings.flows`,
`attendance.settings.geo_fencing`, `scheduling.settings.holidays`, …) are fine: those screens exist.

## Team and company views are scopes, not codes

`GET /api/auth/me` returns `permissions: [{code, scope}]`, `scope` being `own`, `team`, `department`,
`branch`, `selected_units` or `company`. "My / Team / All" tabs read the scope of the one view code:

| Frontend checks                         | Use instead                                                              |
| --------------------------------------- | ------------------------------------------------------------------------ |
| `performance.goals.view_team`           | `performance.goals.view` with a scope other than `own`                   |
| `performance.goals.view_all`            | `performance.goals.view` with scope `company` (or `branch` / `department` / `selected_units` for "everyone I can see") |
| `performance.appraisals.view_team`      | `performance.appraisals.view`, scope other than `own`                    |
| `performance.appraisals.view_all`       | `performance.appraisals.view`, wider than `team`                         |
| `performance.reviews.view_all`          | `performance.reviews.view`, wider than `team`                            |
| `performance.overview.view_team`        | `performance.overview.view`, scope other than `own`                      |

The server applies the scope to every list anyway; the scope only decides which tabs to show.

## Renamed or folded into another action

| Frontend checks                            | Route                                                    | Backend requires                        |
| ------------------------------------------ | -------------------------------------------------------- | --------------------------------------- |
| `access.users.disable`                     | `PATCH /access/users/{id}/disable` · `/enable`           | `access.users.delete`                   |
| `access.users.password`                    | `PUT /access/users/{id}/password`                        | `access.users.edit`                     |
| `access.users.roles`                       | `PUT /access/users/{id}/roles`                           | `access.roles.assign`                   |
| `access.users.overrides`                   | `GET` / `PUT` / `DELETE /access/users/{id}/overrides…`   | `access.overrides.view` / `.edit`       |
| `access.users.sessions`                    | `PATCH /access/users/{id}/sessions/end`, `/access/sessions…` | `access.sessions.view` / `.end_session` |
| `access.roles.permissions`                 | `PUT /access/roles/{id}/permissions`                     | `access.roles.edit`                     |
| `attendance.settings.devices.enrol`        | `PUT /attendance/settings/devices/{id}/enrolments`       | `attendance.settings.devices.enroll`    |
| `attendance.settings.devices.import`       | `POST /attendance/settings/devices/{id}/punches`         | `attendance.logs.import`                |
| `employees.directory.deactivate`           | `PATCH /employees/{id}/deactivate` · `/reactivate`       | `employees.directory.delete`            |
| `recruitment.openings.hold`                | `POST /recruitment/openings/{id}/hold`                   | `recruitment.openings.edit`             |
| `recruitment.applications.move`            | `PATCH /recruitment/applications/{id}/stage`             | `recruitment.applications.edit`         |
| `recruitment.applications.withdraw`        | `POST /recruitment/applications/{id}/withdraw`           | `recruitment.applications.edit`         |
| `recruitment.offers.send`                  | `POST /recruitment/offers/{id}/send`                     | `recruitment.offers.submit`             |
| `recruitment.offers.withdraw`              | `POST /recruitment/offers/{id}/withdraw`                 | `recruitment.offers.cancel`             |
| `performance.cycles.create`                | `POST /performance/cycles`                               | `performance.appraisals.create`         |
| `performance.cycles.edit`                  | `PUT /performance/cycles/{id}`                           | `performance.appraisals.edit`           |
| `performance.cycles.participants`          | `POST /performance/cycles/{id}/participants`             | `performance.appraisals.edit`           |
| `performance.cycles.delete`                | `DELETE /performance/cycles/{id}`                        | `performance.appraisals.delete`         |
| `performance.cycles.launch`                | `POST /performance/cycles/{id}/launch`                   | `performance.appraisals.process`        |
| `performance.cycles.close`                 | `POST /performance/cycles/{id}/close`                    | `performance.appraisals.close`          |
| `performance.appraisals.finalise`          | `POST /performance/appraisals/{id}/finalise`             | `performance.appraisals.approve`        |
| `performance.goals.check_in`               | `POST /performance/goals/{id}/check-ins`                 | `performance.goals.edit`                |
| `performance.reviews.self`                 | `PUT /performance/reviews/{id}/self`                     | `performance.reviews.submit`            |
| `performance.reviews.manager`              | `PUT /performance/reviews/{id}/manager`                  | `performance.reviews.evaluate`          |

(Reading cycles needs `performance.appraisals.view`.)

## Custom Form

The `forms.*` codes the frontend proposed (`forms.forms.view|create|edit|publish|delete`,
`forms.responses.view|export`, `forms.my_forms.view|submit`) are being added to the backend as proposed.

## Checking

`GET /api/access/permissions` lists every code. This list came from grepping the quoted
`module.screen.action` strings outside `src/mocks` and tests and comparing them with
`app.core.permissions.CODES`. Worth adding as a frontend test that reads a checked-in copy of the catalogue.
