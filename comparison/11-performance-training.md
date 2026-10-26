# 11 Performance, Training & Development: frontend vs documents vs ERD

Sources: "Functional Requirements for HRango.pdf" (FRD, text extracted with pdftotext; line refs are to the payroll
settings chapter), "HRango - Mini SRS.pdf" (SRS), "HRango - Scope and Open Questions.pdf" (SOQ), "HRango - Open
Questions.pdf" (OQ), "HRango - Overview.pdf" (OV), `requirements/HRango - Existing Product (web research)/README.md`
(EP), `requirements/HRango - UI design/Design/02-Payroll/README.md` (D-PAY), `.../App/README.md` (APP),
`.../All Dashboards/*` (AD), `.../Design/08-Website-and-Menus/README.md` (D-WEB), `requirements/HRango - Project
Management BRD/README.md` (BRD), the lead's read of Figma "HRango Dashboard App Version" (App UI: My Performance,
Create New Task). Frontend: `frontend/src/routes/_app/performance.tsx` (a placeholder), Payroll Settings menu entry
"Appraisal" linking to `/performance` (`features/payroll/components/settings/settings-menu.tsx`).

## What the documents show

The documents name the modules and almost nothing else:

- **Performance is a menu item only.** Sidebar "Performance" on every dashboard and design page (AD 01, 02, 07, D-WEB);
  SOQ "Performance: Appraisals, KPIs — None, menu item only"; OV "Performance — Menu entry only"; SRS section 8 puts
  "Performance, Configuration and Custom Form, which have no design or requirements" out of the first release unless
  decided otherwise; OQ B4 asks for requirement documents for Performance (unanswered).
- **What it should cover**, from marketing: EP "Performance and evaluation (appraisals, 360-degree feedback, custom
  KPIs)"; D-WEB module name "Performance Evaluation", brochure "Staff Performance Evaluation"; AD 09 "Performance
  appraisal, evaluation, and forms", feature icon "Performance Management", empty state "No Performance"; APP: the
  live apps' store text mentions "KPI management"; employee Documents include an "Appraisal Letter".
- **Appraisal is tied to pay.** D-PAY: the older Payroll sub-menu has "Appraisal" (Pay Runs, Payroll Settings, Payroll
  History, Compensation \ Deductions, Benefits, Appraisal, Loans) and the frontend's Payroll Settings menu links it to
  `/performance`. FRD (payroll settings 5-6, "Apply Salary Revision on Fixed Days" / "Based on Shift Days"): without
  the setting "salary revisions might be applied based on ... performance reviews"; with it "all salary revisions"
  are applied on the fixed date. So an appraisal leads to a salary revision that payroll applies on its own terms;
  nothing says the appraisal changes salary directly. FRD pay items "eligibility ... based on department or
  performance" (no detail).
- **My Performance** (Figma App Version, read by the lead): goals listed with Goal Name, Due Date and Completed, and a
  Performance Overview; the Create New Task form has a Goal field (project tasks link to goals).
- **Project tasks score performance.** BRD: story points are reduced when a task is finished late without an approved
  extension, "a performance score for timely delivery"; OQ F2 / SOQ "does the score feed appraisal or pay?"
  (unanswered); the Activity KPI chart "would naturally surface ... in the Performance module".
- **Training** is not designed or written anywhere. EP: "training management" is in the old product's Premium plan;
  SRS section 8 lists "Internal chat and training management, which the old product advertised" as out of the first
  release unless decided otherwise. (The FDO finance file's "Farmer Training" lines are a client's programme costs,
  not HR training.)

Everything below is therefore **designed here** for a Pakistani HR SaaS in the style of the built modules, and each
choice is listed under Decisions.

## Screens designed

| Screen / feature | Documents | ERD tables | API (`/api/...`) | Code |
|---|---|---|---|---|
| My Performance overview (goal counts, weighted progress, next goals due, appraisal history) | Figma "Performance Overview" | perf.goal, perf.appraisal | `GET /performance/overview?employeeId=` | performance.overview.view |
| Goals (My / Team / All; Goal Name, Due Date, Completed; check-ins) | Figma My Performance | perf.goal, goal_check_in | `GET/POST /performance/goals`, `GET/PUT/DELETE /performance/goals/{id}`, `POST /performance/goals/{id}/check-ins` | performance.goals.* |
| KPI library by key result area | EP "custom KPIs", APP "KPI management", SOQ "KPIs" | perf.kpi | `GET/POST /performance/kpis`, `GET/PUT/DELETE /performance/kpis/{id}` | performance.kpis.* |
| Appraisal cycles (draft → active → closed), participants, launch, close | EP "appraisals", D-PAY "Appraisal" | perf.appraisal_cycle, appraisal | `GET/POST /performance/cycles`, `GET/PUT/DELETE /performance/cycles/{id}`, `POST .../{id}/participants`, `.../launch`, `.../close` | performance.appraisals.* (process = launch) |
| Appraisals (HR list and detail, finalise, remove a participant) | AD 09 "appraisal, evaluation, and forms" | perf.appraisal, appraisal_rating, increment_proposal | `GET /performance/appraisals`, `GET/DELETE /performance/appraisals/{id}`, `POST .../{id}/finalise` | appraisals.view / approve / delete |
| Reviews (My / Team / All; self review, manager review) | EP "evaluation" | perf.appraisal, appraisal_rating | `GET /performance/reviews`, `GET /performance/reviews/{id}`, `PUT .../{id}/self`, `PUT .../{id}/manager` | reviews.view / submit / evaluate |
| Increments proposed by appraisals (apply as salary revision, reject) | FRD salary revision settings; D-PAY "Appraisal" | perf.increment_proposal → hr.employee_salary | `GET /performance/increments`, `GET .../{id}`, `POST .../{id}/apply`, `POST .../{id}/reject` | performance.increments.* (sensitive) |
| Settings: Rating scales | — | perf.rating_scale, rating_scale_level | `GET/POST /performance/rating-scales`, `GET/PUT/DELETE .../{id}` | performance.settings.rating_scales.* |
| Settings: Appraisal forms (criteria, weights, goals weight, self review on/off) | AD 09 "forms" | perf.appraisal_form, appraisal_criterion | `GET/POST /performance/forms`, `GET/PUT/DELETE .../{id}` | performance.settings.forms.* |
| Training programs and materials | EP "training management" | trn.training_program, core.attachment | `GET/POST /training/programs`, `GET/PUT/DELETE .../{id}`, `POST .../{id}/materials`, `DELETE .../{id}/materials/{attachmentId}` | training.programs.* |
| Training sessions (schedule, reschedule, cancel, complete) | — | trn.training_session | `GET/POST /training/sessions`, `GET/PUT/DELETE .../{id}`, `POST .../{id}/cancel`, `POST .../{id}/complete` | training.sessions.* |
| Attendance per session day | — | trn.training_attendance | `GET/PUT /training/sessions/{id}/attendance` | training.attendance.view / edit |
| Nominations and enrolments (My / Team / All; nominate, approve, reject, withdraw, complete, certificate) | — | trn.training_enrolment | `GET/POST /training/enrolments`, `GET .../{id}`, `POST .../{id}/approve`, `/reject`, `/withdraw`, `/complete`, `PUT .../{id}/certificate` | training.enrolments.* |
| Feedback | — | trn.training_feedback | `PUT /training/enrolments/{id}/feedback`, `GET /training/feedback` | training.feedback.create / view |
| Settings: General (minimum attendance, self-nomination) and Categories | — | core.company_setting (module `training`), trn.training_category | `GET/PUT /training/settings`, `GET/POST /training/categories`, `PUT/DELETE .../{id}` | training.settings.general / categories |

Endpoint count: Performance 42, Training 32.

## ERD (erd/source/18-perf.md, 19-trn.md)

- **perf** (11 tables): `rating_scale` + `rating_scale_level` (score DECIMAL(5,2), label); `kpi` (key result area,
  measure type, target, unit, default weight, optional department / job title); `appraisal_form` (scale, goals
  weight, has_self_review) + `appraisal_criterion` (optional KPI, name, weight); `appraisal_cycle` (form, period,
  self / manager due dates, status draft/active/closed); `appraisal` (one per employee per cycle: reviewer, status,
  goals / self / manager / final score, final rating label, comments per stage, development needs, outcome, stamps,
  letter_file_id); `appraisal_rating` (self and manager rating and comment per criterion); `goal` (employee, optional
  cycle and KPI, Goal Name, dates, weight, target / actual, progress, status, completed_at, set_by); `goal_check_in`
  (progress history); `increment_proposal` (appraisal, change type flat/percent, value, effective date, current and
  proposed salary, status proposed/applied/rejected, employee_salary_id).
- **trn** (6 tables): `training_category`; `training_program` (category, delivery mode, provider, hours, cost per head,
  certificate and validity months, mandatory, active); `training_session` (program, dates and times, mode, venue /
  online link, internal trainer employee or external trainer name, capacity, nomination deadline, status, cost,
  cancel reason); `training_enrolment` (session, employee, status requested/enrolled/rejected/withdrawn/cancelled/
  completed/not_completed, nomination source self/manager/hr, decision, attendance %, score, result, certificate file,
  number, issued and expiry dates); `training_attendance` (per enrolment per day: present/absent/excused);
  `training_feedback` (overall / trainer / content rating 1-5, comments).
- Files: appraisal letter (`appraisal.letter_file_id`), certificates (`training_enrolment.certificate_file_id`), program
  materials (`core.attachment`, entity_type `trn.training_program`). All checked with `core.fn_file_usable`; responses
  carry `{id, name, url}` with a signed link.

## Decisions

1. **Built although out of the first release.** SRS section 8 lists Performance and training management as out
   unless decided otherwise; the lead asked for both. Everything is designed; the documents only fix the names.
2. **Scoring.** A form's criteria weights plus its goals weight make 100 (422 otherwise). Goal achievement = the
   person's goals that count in the cycle (named for it, or with no cycle and due inside its period; cancelled goals
   left out), weighted by goal weight: Σ(weight × progress) / Σ weight; it is placed on the rating scale linearly
   (min + (max − min) × achievement). Self and manager score = (Σ criterion weight × rating + goals weight × goal
   score) / (weights of what is rated). Example in the tests: criteria 50 / 30 rated 4 / 3, goals 20 at 75% on 1-5 →
   (200 + 90 + 80) / 100 = 3.70.
3. **Final rating** = the manager score unless HR gives another on finalising (within the scale); the label is the
   nearest scale level (ties go up). Ratings may fall between levels (e.g. 3.5).
4. **Stages.** draft (cycle not launched) → self_review (only when the form has a self review) → manager_review →
   reviewed → finalised. Drafts can be saved at each stage; submitting needs every criterion rated. Only the employee
   writes the self review; nobody manager-reviews or finalises their own appraisal (403). The reviewer is the line
   manager when the person joins the cycle, but anyone whose `performance.reviews.evaluate` scope reaches the
   employee may fill the manager review (HR covers for an absent manager).
5. **Visibility while under way.** The employee does not see the manager's ratings, comments or scores until the
   appraisal is finalised; others do not see the self ratings until the self review is submitted.
6. **Locks.** A form or scale used by a launched cycle keeps its scale, weights, criteria and levels (409
   FORM_IN_USE / SCALE_IN_USE); names and wording may change. A launched cycle keeps its form and period
   (CYCLE_LAUNCHED). A cycle closes only when every appraisal is finalised (APPRAISALS_OPEN); only drafts are deleted.
   A goal that counted in a finalised appraisal is locked (GOAL_LOCKED). An appraisal with a submitted review cannot
   be removed from its cycle.
7. **Goal progress.** With a target, progress = actual / target (0-100); 100% completes the goal and a completed goal
   is at 100%; a cancelled goal keeps its progress. Each change of progress, actual or status adds a check-in row
   (the goal's history). `performance.goal_completed` is published on the move into completed.
8. **Increment hand-off: a proposal, applied through payroll.** The FRD makes salary revision payroll's (fixed-day
   or shift-day timing, the month lock), so finalising with outcome `increment` writes `perf.increment_proposal`
   (status proposed, with the salary in force on the effective date and the figure it would become). "Apply" (
   `performance.increments.process`) calls payroll's own `pay.usp_salary_revision_save` (source `revision`, same
   flat / percent rule) in the same transaction and records the `employee_salary_id` it wrote, so payroll's rules
   (newest salary only, no closed month, effective date after the current salary) hold. Reject keeps the record.
   Payroll may also list proposed rows itself (see Cross-module needs).
9. **Increments are sensitive** (salary figures): the catalogue screen is marked sensitive; the appraisal detail
   shows only the change type, value, effective date and status.
10. **Tabs.** `tab=my` (own), `team` (direct and indirect reports), `all` (whatever the permission's scope reaches),
    on goals, reviews, appraisals and enrolments, always inside `auth.fn_visible_employees` for the endpoint's code.
11. **Promotion and improvement plan** are recorded outcomes only; nothing is started in the employee or requests
    modules (a promotion goes through the promotion request).
12. **Training needs from appraisals** are the manager's free-text `development_needs` on the appraisal (returned in
    the appraisal detail); no needs register or automatic nomination (the documents do not ask for one).
13. **Nominations.** HR whose `training.enrolments.create` reaches the whole company enrols at once (source `hr`); a
    person nominating only themselves makes a `self` request; anyone else (a manager for their team) makes a
    `manager` request. Requests wait for `approve` (anyone whose approve scope reaches the person; managers by
    default). Self-nomination can be switched off (training settings; 403). Nominations close at the session's
    nomination deadline, except for HR. Someone rejected / withdrawn / cancelled can be nominated again (same row).
14. **Capacity.** Seats taken = enrolled + completed + not completed. HR enrolment and approval beyond capacity are
    refused (409 SESSION_FULL, all or nothing); capacity cannot drop below seats taken. No waiting list.
15. **Attendance and completion.** Session days are calendar days from start to end. Marks are present / absent /
    excused, for enrolled seats on a scheduled session, for days that have come. Completion needs days present /
    session days ≥ the minimum attendance (default 80%, settings; 409 ATTENDANCE_SHORT). Completing a session settles
    every enrolled seat by that rule (completed / not_completed) and cancels waiting nominations.
16. **Certificates** are uploaded files attached to a completed enrolment, with number and issue date; expiry = issue
    date + the program's validity months. Feedback is the participant's own, once their training is over (completed
    or not completed), 1-5 ratings; the session shows the average.
17. **Cancelling a session** cancels requested and enrolled seats and tells those people; moving its dates, times,
    venue or link tells them too (`training.session_rescheduled`).
18. **Notifications** (`core.usp_notification_add_employee`, wrapped by `perf.usp_notify_employee` /
    `trn.usp_notify_employee` so the count it returns does not become the caller's first result set): participants
    when a cycle launches (or they join an active one); the reviewer when a self review is submitted; the employee when
    the appraisal is finalised; employees when enrolled (by HR or on approval), when a nomination is rejected or
    withdrawn by someone else, when a session moves or is cancelled, on completion and when a certificate is issued.
19. **Events**: performance.goal_completed, cycle_launched, review_submitted (data.stage self / manager),
    appraisal_finalised, increment_proposed, increment_applied, increment_rejected, cycle_closed; training.
    session_scheduled, session_rescheduled, session_cancelled, session_completed, nominated, enrolled,
    nomination_rejected, withdrawn, completed, certificate_issued, feedback_submitted. Published in the same
    transaction as the change.
20. **Aggregates over NULLs avoided** in these procedures: SQL Server's warning 8153 ("Null value is eliminated")
    arrives ahead of a later THROW and `core/db.py` then reads the warning's number instead of 5040x (found in testing;
    a note for `core/db.py`'s owner: `_translate` could search for the 5040x number rather than the first one).

## Gaps

Documents have, this build lacks:
- 360-degree feedback (EP marketing line): only self and manager reviews. Peer reviewers would be extra rows of
  reviewers per appraisal; left out until the documents describe them.
- Story-point score from project tasks feeding appraisal (BRD, OQ F2 unanswered): not read.
- Appraisal letter generation from a template: the letter is an uploaded file.

Designed here, nothing in the documents to check against: all screens above. The frontend has only a placeholder;
it should be built from these routes and shapes.

Not built: training budgets per department, trainer master list (internal trainers are employees, external ones a
name), training calendar view (the session list filters by dates), e-learning content tracking, mandatory-training
compliance report (programs carry `is_mandatory`; the report can be built on enrolments), certificate expiry
reminders (no scheduler for notifications), goal approval by the manager, goal cascading (company → team → person).

## Cross-module needs

- **Default roles** (`app/core/default_roles.py`, owner of shared files):
  - Employee and the self-service part of Line Manager / Department Head (`own`): `performance.overview.view`,
    `performance.goals.view|create|edit`, `performance.kpis.view`, `performance.reviews.view|submit`,
    `training.programs.view`, `training.sessions.view`, `training.enrolments.view|create|cancel`,
    `training.attendance.view`, `training.feedback.create`.
  - Line Manager (`team`) / Department Head (`department`), in `_managing(scope)`: `performance.overview.view`,
    `performance.goals.*`, `performance.reviews.view|evaluate|export`, `performance.appraisals.view`,
    `training.enrolments.view|create|approve|reject|cancel|export`, `training.attendance.view`,
    `training.feedback.view`. (`performance.increments.*` stays out: sensitive.)
  - Payroll Manager: `performance.increments.*` (company), `performance.appraisals.view` (company).
  - HR Officer: add `performance.increments.*` to its exclusions (salary figures), like `employees.salary.*`.
  - Executive gets `*.view` already; increments are held back by `no_sensitive`.
- **Payroll**: the Salary Revision screen may show `perf.increment_proposal` rows with status `proposed`
  (`perf.usp_increment_list @status = N'proposed'`) and apply them through `POST /api/performance/increments/{id}/apply`;
  if payroll wants revisions from appraisals told apart, add source code `appraisal` to `hr.employee_salary.source`
  (and to its edit rule, which allows only `revision` / `import`), then this module passes it.
- **Projects** (pm): the Create New Task form's Goal field needs `pm.task.goal_id FK perf.goal` (optional); the goal
  screen could then show linked tasks, and task completion could add a goal check-in.
- **Employees**: the Documents tab ("Appraisal Letter") can list `perf.appraisal.letter_file_id` and training
  certificates (`trn.training_enrolment.certificate_file_id`) for the person.
- **ERD build** (`erd/build.py`): `BACKEND_MODULE` has no entry for `perf` and `trn` (add `"perf": "performance",
  "trn": "training"`), otherwise a full build (without `--sql-out`) stops in `write_md`.
- **Frontend**: replace the Performance placeholder; Payroll Settings "Appraisal" can open `/performance/cycles`.
