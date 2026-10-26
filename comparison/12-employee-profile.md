# 12 Employee profile: documents vs ERD vs build

Status: built. Backend: `/api/employees/{id}/photo`, `/{id}/emergency-contacts`, `/dependents`, `/skills`,
`/education`, `/experience`, `/contracts`, `/documents`, `/{id}/update-requests`, `/update-requests` (35 new
endpoints), plus home address, photo, tenure and emergency contact on the employee card. Tests:
`tests/test_employees_profile.py` (6 tests) next to `tests/test_employees.py`.

This completes the Employees module of `01-organisation.md`, whose "Not in this build" listed documents,
experience, agreement and contract tabs (no file storage then) and self-service edits.

## Sources

- **Figma "HRango Dashboard App Version"** (read by the lead; summarised in the brief): profile tabs Personal
  (Full Name, Date of Birth, Hire Date, CNIC, Reg #, Tenure, Emergency Contact #, Phone, Marital Status),
  Dependents (First Name, Last Name, Relation, Occupation), Skills (Skill Title, Skill Level), Documents / Add
  Academic (Academic Title, Institute, From / To, In Process, document upload), Add Contract (Employee, Contract
  Type e.g. Temporary, Contract Duration in Months with Custom, From / To, attachment), Add Professional
  Experience (Company Name, Job Title, From / To), Work tab (attendance, goals, loan summary, payroll history),
  Benefits tab, Leaves overview.
- **EMPD** `requirements/HRango - UI design/All Dashboards/03-Employee-and-Profile-Dashboard/README.md`: Profile
  Dashboard with profile card (avatar, name, role), Experience timeline ("2020 - Present, HData Systems, Senior
  App Developer"), Personal Information (Reg #, Job Title, Hire Date), Employee Details tabs Attendance, Leave,
  Loan, Benefits, Salary, Contract.
- **APP** `requirements/HRango - UI design/App/README.md`: Profile menu Personal Information, Documents, Bank
  Details; Personal Info (First Name, Last Name, Parent Name, CNIC, Email, Contact 1, Contact 2); Documents
  (Job Offer Letter, Experience Letter, Promotion Letter, Appraisal Letter, CNIC Front & Back, "Add Document").
- **SRS** `HRango - Mini SRS.pdf`: M2 "Employee records: Profile, documents, bank details, salary, benefits";
  EMP-1 (record incl. "employment and contract type, CNIC, contacts"), EMP-3 "Keep documents per employee (offer
  letter, CNIC copy, letters) with upload", MOB-3 "Mobile: profile, documents, bank account, loan summary",
  section 6 Employee "Identity, placement, contract, salary, bank, documents", ACC-9 sensitive fields.
- **Working screens** `.../08-Working-Screens-Slides-12-20/README.md`: employee agreement viewer with "I Agree".
- **Existing product** `requirements/HRango - Existing Product (web research)/README.md`: "Employee self-service
  (profile, leave requests, company news)", "Employee management and document management" (vendor text).
- **Other modules**: `09-manpower-benefits.md` (Benefits Employees tab needs Home Address and the "Update
  Information" edit for date of birth / marital status / address); `08-projects.md` (people picker wants a photo URL).
- Grep of `requirements/` for Dependent, Emergency, Education, Skill: no further screens. "Dependent fields" in
  `FRD 01-Requests` and `Design/05-Leaves` are form fields that depend on other fields, not family dependents;
  leave rules have no dependent-based conditions (their pre-conditions are the employee's gender and marital
  status).

## Tabs and forms

| Tab / form | Documents | Table | Endpoints | Decision |
|---|---|---|---|---|
| Personal | Figma Personal; APP Personal Info; EMPD Personal Information | `hr.employee` | card `GET /employees/{id}`; edit `PUT /employees/{id}` | Full Name = first + last; Reg # = `code`; Hire Date = current period's joining date; **Tenure** = `tenureMonths` (whole months of the current period); **Emergency Contact #** = the primary emergency contact (`emergencyContactName/Phone`); Phone = `phone1/phone2`; Marital Status as before. **Home address** added (`homeAddress`, `homeCityId` -> `org.city`, `homeCityName`) for Benefits |
| Profile photo | EMPD avatar, APP, Figma; PM picker | `hr.employee.photo_file_id` | `PUT /employees/{id}/photo {fileId, rowVersion}` | Image uploads only (`PHOTO_NOT_IMAGE`); own code `employees.photo.edit` so staff can change their own. `photoUrl` (signed, expiring) on card, directory and `/employees/lookup` |
| Emergency contacts | Figma "Emergency Contact #" | `hr.employee_emergency_contact` | list / add / edit / delete | Name, relation, phone required; alt phone, address; one primary (first added; deleting it promotes the next) |
| Dependents | Figma Dependents | `hr.employee_dependent` | list / add / edit / delete | Figma fields plus optional date of birth (benefit and insurance plans need ages). Relation list: spouse, son, daughter, father, mother, brother, sister, other |
| Skills | Figma Skills | `hr.employee_skill` | list / add / edit / delete | Levels beginner, intermediate, advanced, expert (Figma shows a level, no list); one row per title (`SKILL_DUPLICATE`) |
| Education / Add Academic | Figma Add Academic | `hr.employee_education` (`file_id`) | list / add / edit / delete | In Process means no To date; the degree file is optional on the row (a degree can also be a Document) |
| Professional experience | Figma Add Professional Experience; EMPD Experience timeline | `hr.employee_experience` (existing table) | list / add / edit / delete | Empty To = current ("Present"); `isCurrent`, `months` returned. API `jobTitle` is stored in the existing `role_title` column (kept, not renamed) |
| Contracts / Add Contract | Figma Add Contract; EMPD Contract tab; SRS EMP-1 contract type | `hr.employee_contract` (`file_id`) | list / add / edit / delete | Types permanent, temporary, contractual, probation, internship, consultant. Duration in months fills an empty To date (From + months - 1 day); "Custom" = no duration, To given. No overlapping contracts (`CONTRACT_OVERLAP`). `status` upcoming / active / expired. **Sensitive** |
| Documents | SRS EMP-3; APP Documents; Figma Documents | `hr.employee_document` (existing table, extended) | list / add / edit / delete | Type, title, number, issue / expiry dates, file (required), remarks. Identity types need the CNIC permission, pay letters the salary permission (see decisions). Expired flag; expiry notices |
| Update Information | Benefits Employees tab (09); existing product "self-service (profile)" | `hr.employee_change_request` | `POST /employees/{id}/update-requests`, `GET /employees/update-requests[/{id}]`, `PATCH .../{id}/approve | reject | cancel` | Employee asks, HR approves; approval writes the record |
| Work tab (attendance, goals, loan summary, payroll history), Benefits tab, Leaves overview | Figma; EMPD tabs | other modules | none here | Links only: attendance `/api/attendance`, leave `/api/leaves`, loans `/api/loans`, payroll `/api/payroll` (payslips), benefits `/api/benefits` (elections), performance (goals) when built. Each reads with its own codes and scope |
| Salary, Bank details | EMPD Salary tab; APP Bank Details | existing | existing | Unchanged (sensitive) |
| Employee agreement ("I Agree") | Working screens | `hr.employee_agreement` | none | Not built (see below) |

## ERD (`erd/source/02-hr.md`)

- `employee`: + `home_address {NVARCHAR(500)}`, `home_city_id FK city` (optional); `photo_file_id` documented as
  the profile photo. No column renamed or dropped (others read `photo_file_id`, `phone_1`, `date_of_birth`, ...).
- `employee_document`: + `title`, `document_number`, `issue_date`, `expiry_date`, `remarks`, `expiry_notified_at`;
  `document_type` and `file_id` NN.
- `employee_experience`: `company_name`, `role_title`, `from_date` NN (no other module uses the table).
- New: `employee_emergency_contact`, `employee_dependent`, `employee_skill` (UNIQUE employee + title),
  `employee_education`, `employee_contract`, `employee_change_request` (company, employee, status, `changes` and
  `previous_values` JSON, remarks, decided by / at, decision remarks).
- Tab rows have no `company_id`, like `employee_bank_account`: the employee row carries the company and every
  procedure reaches the employee first.

## Permissions (`app/catalogue/employees.py`)

New screens (existing codes unchanged): `employees.photo` (edit), `employees.emergency_contacts`,
`employees.dependents`, `employees.skills`, `employees.education`, `employees.experience`, `employees.documents`
(view, edit), `employees.contracts` (view, edit; **sensitive**), `employees.update_requests` (view, create,
cancel, approve, reject). Edit covers add, change and remove on a tab (as bank details do), so HR Officers, who
do not get `*.delete`, keep the tabs. Every tab procedure filters with `auth.fn_visible_employees` and the
endpoint's code; out of scope is "not found".

## Events

`employees.created` (add), `employees.updated` (main form, CNIC change, photo, approved Update Information,
promotion / demotion / transfer applied or cancelled; `change` says which), `employees.deactivated`,
`employees.reactivated`, `employees.profile_changed` (tab, action, row, `bySelf`), `employees.update_requested`,
`employees.update_decided`, `employees.document_expiring`. Payloads carry ids, code, name, status and placement,
never the CNIC, document numbers, salary or bank details.

## Decisions on unclear points

1. **Self-service.** The documents show the employee's own profile (APP Profile, Personal Info, Documents with
   "Add Document"; MOB-3; existing product "Employee self-service (profile)") but no approval rule. Decided:
   - Personal details that other modules rely on (date of birth: leave and benefits eligibility; marital status:
     leave pre-conditions; phones; home address) change through an **Update Information request** that HR
     approves. One pending request per employee (`UPDATE_REQUEST_PENDING`); only the fields sent are asked for
     (null asks for a clear); a request that changes nothing is refused; nobody decides their own request, HR
     included; the approver is notified on submission (every user who holds `employees.update_requests.approve`
     for that employee), the employee on approval or rejection. Approval writes the fields and one History row
     each (`action update_request`).
   - The list tabs (emergency contacts, dependents, skills, education, experience, documents) and the photo are
     edited directly by whoever holds the tab's edit code for the employee; with own scope that is the employee.
     These are not approved; every change is in the History popup and published as `employees.profile_changed`
     with `bySelf`, so HR (or a webhook) can follow self-service changes without an inbox message per edit.
   - Name, CNIC, placement, contracts, salary and bank stay HR-only (unchanged).
2. **Sensitive documents.** A document's type decides its guard: identity (cnic, passport, driving_licence)
   needs `employees.identity.view` for that employee, pay (offer_letter, promotion_letter, appraisal_letter,
   salary_certificate) needs `employees.salary.view`, the rest (experience_letter, degree, certificate, medical,
   other) only `employees.documents.*`. The same guard applies to reading, adding, editing (old and new type)
   and deleting; a hidden document is "not found", adding one is 403. Staff hold identity and salary view for
   themselves, so they see and upload their own CNIC copy, as APP Documents shows. `employees.documents` itself
   is not sensitive, so managers can be given degrees and letters without CNICs.
3. **Contracts are sensitive** as a whole: an employment contract states pay. Managers and executives do not get
   them (ACC-9, E6).
4. **Emergency Contact #** on the Personal tab is not a column; it is the primary emergency contact, so there is
   one source.
5. **Tenure** is months in the current employment period (rehire restarts it); it is computed, not stored.
6. **Document expiry.** `hr.usp_employee_document_expiry_notify @company_id, @days_ahead = 30` notifies the
   employee once per expiry date (a changed expiry date is warned about again), publishes
   `employees.document_expiring`, and stamps the row. Nothing schedules it yet (see needs).
7. **Uploads** for this module use `module = "employees"` in `POST /api/files`. Every file id is checked with
   `core.fn_file_usable` (another company's file is a 422 on `fileId`); responses give `{id, name, url}`.
8. **Experience** keeps the existing `role_title` column; the API names it `jobTitle` as the Figma form does.
9. **Address** is one free-text line plus an optional city from `org.city` (Benefits asks for "Home Address" only;
   no country / postal fields drawn).
10. **`GET /employees/lookup`** is paged: `?q=` (code or name), `page`, `pageSize` (max 100), answering
    `{data, meta}`. A caller that sends no `pageSize` gets the first page `limit` long (default 50), as before.
    Rows: `id, code, name, designationName, jobTitleName, departmentId, departmentName, branchId, branchName,
    status, photoUrl`.

## Proposed default-role grants (for `app/core/default_roles.py`, owner of shared files)

- `SELF_SERVICE` (Employee and the managers' own records): `employees.photo.edit`,
  `employees.{emergency_contacts,dependents,skills,education,experience,documents}.view` and `.edit`,
  `employees.contracts.view`, `employees.update_requests.view`, `.create`, `.cancel` — all own scope.
- `_managing(scope)` (Line Manager team, Department Head department):
  `employees.{emergency_contacts,dependents,skills,education,experience,documents}.view` at that scope (identity
  documents and pay letters stay hidden through the sensitive codes they lack).
- HR Manager / Company Administrator already get everything; HR Officer gets the tabs, contracts and
  `update_requests.*` (approve and reject included) through `*`; Executive gets the non-sensitive views through
  `*.view`. Until these are added, the new tabs are reachable only by those roles and by personal grants (the
  tests grant per user).

## Cross-module needs (recorded, not done here)

- **Shared `default_roles.py`**: the grants above.
- **Nightly job (`scripts/`)**: call `hr.usp_employee_document_expiry_notify` for every company once a day
  (`app.services.employees_service.document_expiry_notify(db, company_id)`).
- **Separation (sep)**: `usp_end_of_employment` sets status `left` / back to `active` without an event; publish
  `employees.updated` (change `left` / `rehired`) through `EXEC hr.usp_employee_event_publish @company_id,
  @employee_id, N'employees.updated', N'left', @actor_user_id` in its transaction.
- **Projects (pm)**: `pm.usp_people_list` returns `photo_file_id`; turn it into a link with
  `app.core.files.file_url(photo_file_id, ctx.company_id)` in its controller, or use `/api/employees/lookup`
  (now returns `photoUrl`).
- **Benefits**: the Employees tab can read `homeAddress` / `homeCityName` from the employee card and send
  "Update Information" to `POST /api/employees/{id}/update-requests` (or HR edits directly with `PUT
  /api/employees/{id}`).
- **01-organisation.md** "Not in this build" still lists documents / experience / contract tabs and
  self-service edits; it can point here.

## Not in this build

- **Employee agreement / eSignature "I Agree"** (`hr.employee_agreement`): an onboarding flow (who issues which
  agreement, versions, when it must be accepted) that no document defines; the table is kept.
- **Verification of self-uploaded documents** (verified by / at): no document asks for it; the History popup and
  the `profile_changed` event show who uploaded what.
- **Several files per education or contract row** (`core.attachment`): the Figma forms have one upload each.
- **Work, Benefits and Leaves tabs**: read from their modules; nothing to store here.
- **Printable ID card** (assets page "employee ID card with photo, QR code"): needs a template design; the photo
  link is available for it.
