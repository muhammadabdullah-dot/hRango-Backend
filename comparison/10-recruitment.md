# 10 Recruitment

Compared on 2026-10-26: documents, the ERD sketch and the frontend. The frontend has Recruitment only as a
placeholder route (`frontend/src/routes/_app/recruitment.tsx`), so nothing there is a specification. The
documents are thin: no written requirement exists beyond one line, so most of the module is designed here in
the style of the other modules, for a Pakistani HR SaaS. Every such choice is listed under Decisions.

## What the documents show

| Source | What it says |
|---|---|
| `requirements/HRango - UI design/All Dashboards/04-Recruitment-Dashboard/README.md`, "Current layout" | KPI tiles Total Openings, Interviews, Hired, Rejected; Job Statistics (Applications, Shortlisted, Rejected by month, year / month filters); Overview pie (Applications, Interviews, Accepted, Rejected); Recent Activity; Job Applications table (candidate, location, interviewer, schedule, mail / phone); Notice Board; "+ Add New" |
| same, "Early dark concept" | status filter chips on applications (Approved, Interview, Hired, Rejected), delete an application, interview calendar |
| same, "Frames on the page" / `09-Assets-Website-and-Marketing/README.md` | pipeline icon set: applied, qualified, short listed, interview, re-interview, non qualified, rejected, offered, offer accepted; total jobs, in process, on hold, completed jobs |
| `08-Working-Screens-Slides-12-20/README.md`, "New Job Position (Slide 15)" | Job Title, Designation, Work Mode, Employment Type, Experience From / To, No. of Vacancies, Posted Date, Last Date to Apply, Close Date, Salary From / To, City, State; rich-text Job Description (AI-drafted) |
| same, "Applicant Tracking (Slide 16)" | Name, Applied Date, Status chip, one-click approve / reject; "Issues": no job shown, only Pending / Rejected |
| same, "Agreement (Slide 18)" | employee agreement viewer with "I Agree" (filed under Recruitment) |
| `All Dashboards/README.md`, "Recruitment" | job posting with rich text; applicant pipeline with stages, approve / reject, interview scheduling with interviewer and slot |
| `HRango - Existing Product (web research)/README.md`, "What it claims to do", "Pricing" | job posts, applications, AI-assisted screening; recruitment in Advanced, applicant tracking in Premium |
| "HRango - Mini SRS.pdf" M13, REC-1, DSH-1, EMP-3 | "Job positions and applicant tracking"; a Recruitment dashboard; offer letter kept as an employee document |
| "HRango - Overview.pdf", "Scope and Open Questions.pdf", "Open Questions.pdf" B4 / B7 | recruitment has older-style designs only and no written requirements; B7 asks whether designs will be supplied |
| `09-Assets-Website-and-Marketing/README.md`, "What this tells you about scope" | website integration for job postings (careers site) promised, no screen |
| `erd/source/11-rec.md` (sketch) and `12-mp.md` | job_position / applicant / application / interview; `open_position 1──* job_position` (Manpower feeds recruitment) |

## Screens designed

| Screen | Endpoints (`/api/recruitment`) | Codes | Tables |
|---|---|---|---|
| Recruitment Dashboard: tiles, Job Statistics, Overview, Job Applications (next interviews), Recent Activity | `GET /dashboard?year&month` | `recruitment.dashboard.view` | all rec tables |
| Job Openings list (search, status, department, station, job title, open position filters) | `GET /openings` | `recruitment.openings.view` | job_opening |
| New / Edit Job Position (Slide 15 fields + department, station, hiring manager, open position, requirements, salary visibility) | `POST /openings`, `PUT /openings/{id}`, `GET /openings/{id}` | `.create` / `.edit` | job_opening |
| Publish / Hold / Close / Reopen, Delete | `POST /openings/{id}/publish|hold|close|reopen`, `DELETE` | `.publish`, `.edit`, `.close`, `.reopen`, `.delete` | job_opening |
| Applicants (talent pool) list and card with their applications; add / edit with CV | `GET/POST /applicants`, `GET/PUT/DELETE /applicants/{id}` | `recruitment.applicants.*` | applicant |
| Applicant Tracking list (stage chips, active only, opening, dates) and application card (timeline, interviews, offers) | `GET /applications`, `GET /applications/{id}` | `recruitment.applications.view` | application, application_stage_history |
| "+ Add New" candidate: apply an existing applicant or a new one in one call | `POST /applications` | `.create` | applicant, application |
| Move stage (approve = move on), Reject (with reason), Withdraw, Delete | `PATCH /applications/{id}/stage`, `POST .../reject`, `POST .../withdraw`, `DELETE` | `.edit`, `.reject`, `.edit`, `.delete` | application, history |
| Hire | `POST /applications/{id}/hire` | `recruitment.applications.hire` | application, hr.employee (+ period, history, salary, document) |
| Interviews list (mine, opening, application, interviewer, status, dates), interview card with panel and evaluations | `GET /interviews`, `GET /interviews/{id}` | `recruitment.interviews.view` | interview, interview_interviewer, interview_evaluation |
| Schedule / Reschedule (panel), Cancel, Complete (result / no show) | `POST /interviews`, `PUT /interviews/{id}`, `POST .../cancel`, `POST .../complete` | `.create`, `.edit`, `.cancel`, `.complete` | interview, interview_interviewer |
| Evaluation form (rating 1-5, recommendation, strengths, concerns, comments) | `POST /interviews/{id}/evaluations` | `recruitment.interviews.evaluate` | interview_evaluation |
| Offers list / card, make (draft) / edit / delete, Send, record answer, Withdraw | `GET/POST /offers`, `GET/PUT/DELETE /offers/{id}`, `POST .../send`, `.../respond`, `.../withdraw` | `recruitment.offers.*` (`submit`, `respond`, `cancel`) | offer |
| Settings -> Rejection reasons | `GET/POST /settings/rejection-reasons`, `PUT/DELETE /{id}` | `recruitment.settings.rejection_reasons.*` | rejection_reason |

42 operations. Files (CV, offer letter) are uploaded first through `POST /api/files` (module `recruitment`), sent as ids,
checked with `core.fn_file_usable`, and returned as `{id, name, url}` with a signed link.

## ERD (`erd/source/11-rec.md`)

Redesigned from the sketch: `job_opening` (was job_position; the name avoids confusion with mp.position),
`applicant`, `application` (+ `rejection_reason_id`, `rejected_stage`, `employee_id`, `hired_at`, `UNIQUE (job_opening_id,
applicant_id)`), `application_stage_history`, `interview` (round, mode, slot, duration, venue, status, result),
`interview_interviewer` (link table: the panel), `interview_evaluation` (`UNIQUE (interview_id, employee_id)`), `offer`,
`rejection_reason` (`UNIQUE (company_id, name)`). `applicant` is `UNIQUE (company_id, email)`.

## Decisions

- **Pipeline**: stages `applied, screening, shortlisted, interview, offer, hired` plus the closed outcomes `rejected,
  withdrawn`. The design's icons map onto them: qualified = screening passed (shortlisted), non qualified = rejected at
  screening (`rejected_stage`), re-interview = another interview round, offered = offer stage, offer accepted = the
  offer's status. Fixed codes in the procedures, no reference table (the logic depends on them).
- **Moves**: any active stage can be set by hand (forward or back) except hired; hired only through Hire; rejected /
  withdrawn through their steps, which cancel scheduled interviews and withdraw draft / sent offers. A rejected or
  withdrawn application can be brought back to an active stage. Scheduling an interview moves an earlier application
  to `interview`; sending an offer moves it to `offer`. Every move writes a history row and `recruitment.stage_changed`.
- **"Approve" on Applicant Tracking** is "move to the next stage" (`PATCH .../stage`), not an approval flow.
- **Openings from Manpower**: an opening may name an active `mp.open_position`; blanks take its title, job title,
  department, station and open seats. The unfilled vacancies of all non-closed openings of one open position may not
  exceed its open seats (409 `OPEN_POSITION_SEATS`). Openings can also be made without Manpower.
- **Opening status**: draft -> open (publish; posted date defaults to today) -> on_hold <-> open -> closed; reopen from
  on_hold / closed. Applications are taken only while open. A closed opening is read-only until reopened. Delete only
  without applications.
- **Hiring** (one transaction in the service): `rec.usp_application_hire_prepare` (accepted offer required, opening not
  closed or filled) -> Employees' own `hr.usp_employee_save` (reused, so the code number, placement checks, job-title
  head-count limit, first employment period, joining history and audit stay Employees' rules) -> `rec.usp_application_hire_complete`.
  The employee takes the applicant's name, e-mail, phone, gender, date of birth; the offer's (else the opening's)
  station, department, designation, job title, employment type; the opening's hiring manager as line manager; status
  probation when the offer has probation months (probation end = joining + months - 1 day), else active. Any field can be
  overridden in the Hire body (also code and CNIC). A refusal anywhere undoes everything.
- **What hiring writes outside rec** (no hr / mp table definitions changed): `hr.employee_salary` (the offered salary from
  the joining date, source `joining`), `hr.employee_document` rows `cv` and `offer_letter` (SRS EMP-3), and on
  `mp.open_position` one seat fewer (`total_positions - 1`, status `closed` at 0, audit row `mp.open_position`). When the
  opening's last vacancy is filled the opening closes (`recruitment.opening_closed`, reason `filled`).
- **Offers**: draft -> sent -> accepted / declined; withdraw from draft, sent or accepted (not after the hire). One live
  offer (draft, sent, accepted) per application; a revised offer is a new row. Only drafts are edited or deleted.
  Accepting after `expiresOn` is refused. The candidate's answer is recorded by HR (`respond`); there is no candidate
  portal. Offers are a sensitive screen (salary).
- **Interviews**: a panel of one or more current employees; no interviewer in two scheduled interviews at once
  (409 `INTERVIEWER_BUSY`); times are local wall-clock (like attendance). The panel is notified in the inbox
  (`core.usp_notification_add_employee`) when scheduled, rescheduled (everyone when the time / place moved, else only
  those added) and cancelled. An interviewer who has evaluated cannot be removed. Complete sets completed (result
  passed / failed / on hold) or no show.
- **Evaluations**: one per interviewer per interview (saving again replaces it): rating 1-5 and recommendation
  strong_hire / hire / no_hire / strong_no_hire with strengths, concerns, comments. An interviewer evaluates for
  themselves; recording for another panel member needs the permission over the opening (HR).
- **Scope**: openings are reached through their department / station like Manpower's records (company, department and
  sub-departments, branch, selected_units); own reaches the openings one is hiring manager for, team also those of one's
  reports. Applications, offers and interviews follow their opening; interviewers also reach the interviews they sit on
  (`rec.fn_visible_interviews`), so a line manager with `interviews.view/evaluate` at own scope sees only their
  interviews. Applicants: company scope sees all, others those who applied to openings they reach or whom they added.
  Saving an opening outside one's reach is refused (403).
- **Notifications**: interviewers (scheduled / updated / cancelled); the hiring manager when an offer is accepted and
  when the candidate is hired. Nothing is sent by mail (shared gap); mail gateways can subscribe to `notification.created`.
- **Dashboard**: Total Openings tile = openings open now (`openOpenings`; `totalOpenings` = non-draft openings live in the
  period; `openVacancies` too); Interviews = interviews in the period (not cancelled); Hired / Rejected = applications
  moved there in the period; Overview = applications, interviews, offers accepted, rejected; Job Statistics = per month
  applications, shortlisted, rejected, hired; Job Applications table = next scheduled interviews with candidate, city,
  first interviewer and their title, slot, e-mail, phone; Recent Activity = latest stage changes. Period = year, or a
  month of it. "Upcoming" compares with the server's UTC clock (interview times are local), so it is off by the UTC offset.
- **Rejection reasons** are a settings list (Settings -> Rejection reasons); a used reason is switched off, not deleted.
- **No seed data**: stages, modes, sources and statuses are fixed lists; rejection reasons are entered per company.

## Gaps

- Documents have, not built: AI job-description drafting and AI screening (AI module, no backend for it yet); the
  careers site / website job board (public endpoints need a shared decision on anonymous uploads, spam protection and
  company identification; `is_salary_visible` and `published_at` are ready for it); Notice Board (engagement module);
  interview calendar view (frontend over `GET /interviews?fromDate&toDate`); the Agreement "I Agree" screen
  (`hr.employee_agreement`, Employees module).
- Designed here, not in the documents: rejection reasons, evaluations form, offer statuses and expiry, hiring manager,
  interviewer clash check, applicant de-duplication by e-mail.
- Not built: evaluation criteria / scorecards per opening, offer approval chain, onboarding checklist after hire,
  candidate portal or e-mail to candidates, CV parsing, duplicate-candidate merge, export files (export codes exist; lists
  are exported by the frontend as elsewhere).

## Cross-module needs

- **Default roles** (`app/core/default_roles.py`, shared): the Recruiter role has no recruitment codes yet. Proposed:
  Recruiter `recruitment.*` company (offers included; they are sensitive, so only roles meant to see salaries get them);
  HR Manager and Company Administrator already get everything; HR Officer gets everything but settings and deletes
  (existing excludes); Executive gets the `*.view` codes except `recruitment.offers.view` (no_sensitive) and
  `recruitment.dashboard.view`; Line Manager and Department Head: `recruitment.interviews.view` and
  `recruitment.interviews.evaluate` with own scope (their own interviews), and Department Head
  `recruitment.openings.view`, `recruitment.applications.view`, `recruitment.dashboard.view` with department scope.
  `recruitment.applications.hire` creates employees: keep it to Recruiter / HR roles.
- **Employees (hr)**: hiring calls `hr.usp_employee_save` with the permission `recruitment.applications.hire` (its scope
  check uses that code) and writes `hr.employee_salary` and `hr.employee_document` rows directly (`document_type` `cv` /
  `offer_letter`); please keep those procedures' parameters and columns stable, or tell Recruitment. When the documents
  tab is built, these rows should show there.
- **Manpower (mp)**: Recruitment reads `mp.open_position` and, on hire, lowers `total_positions` by one and closes it at
  zero (audit row `mp.open_position`). Manpower's own edit refuses fewer than 1 seat, so a filled position stays closed.
  If Manpower prefers to own that write, it can expose a procedure (e.g. `mp.usp_open_position_fill`) and Recruitment will call it.
- **Dashboard module**: the HR dashboard's "Job overview (applications, shortlisted)" (01-organisation) can read
  `rec.usp_dashboard` set 2.
- **Files**: `core.fn_file_usable` checks the company; uploads use module `recruitment`.
