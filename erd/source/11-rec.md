## 11. Recruitment [rec]

Source: the Recruitment Dashboard (requirements/HRango - UI design/All Dashboards/04-Recruitment-Dashboard),
New Job Position and Applicant Tracking (08-Working-Screens-Slides-12-20), the pipeline icon set
(09-Assets-Website-and-Marketing), Mini SRS REC-1 / DSH-1 / EMP-3. Designed for the backend build on
2026-10-26; comparison/10-recruitment.md records each decision.
Stages, modes, statuses and sources are fixed codes checked in the rec procedures (no reference tables).

```
job_opening                           "New Job Position": a vacancy advertised and recruited for
  id                PK
  company_id        FK company
  code                                given, or the next JOB-0001 number
  title                               "Marketing Executive"
  open_position_id  FK open_position  optional: the Manpower seat it fills (vacancies cannot exceed its open seats)
  job_title_id      FK job_title      optional: org.job_title, given to the employee on hire
  designation_id    FK designation    optional
  department_id     FK department     optional: scope and the hired employee's department
  branch_id         FK branch         optional: "Station"; scope and the hired employee's branch
  employment_type_id FK employment_type {NULL}  optional
  hiring_manager_id FK employee       optional: told when an offer is accepted and a candidate hired
  city_id           FK city           optional: "Enter City" (its state is "Enter State")
  work_mode                           on_site, remote, hybrid
  experience_from_years               "Experience From"
  experience_to_years                 "Experience To"
  vacancies         {NN}              "No. of Vacancies"
  posted_on                           "Posted Date"; set on publish when blank
  apply_by                            "Last Date to Apply"
  close_on                            "Close Date"
  salary_from                         "Salary From"
  salary_to                           "Salary To"
  is_salary_visible                   show the range on the careers page
  description                         rich text (HTML) "Job Description" editor
  requirements      {NVARCHAR(MAX)}   skills and qualifications
  status                              draft, open, on_hold, closed
  published_at
  closed_at

applicant                             a candidate in the talent pool; one per e-mail address per company
  id                PK
  company_id        FK company
  first_name, last_name
  email             {NN}
  phone
  gender
  date_of_birth
  city_id           FK city           optional
  address
  current_employer
  current_job_title
  experience_years  {DECIMAL(4,1)}    total years of experience
  current_salary
  expected_salary
  notice_period_days
  highest_education
  linkedin_url      {NVARCHAR(500)}
  source                              career_site, referral, job_board, linkedin, walk_in, agency, other
  referred_by_employee_id FK employee {NULL}  optional: the employee who referred them
  cv_file_id        FK stored_file    the CV, uploaded first through /api/files
  notes
  UNIQUE (company_id, email)

application                           one applicant for one opening, moving through the pipeline
  id                PK
  company_id        FK company
  job_opening_id    FK job_opening
  applicant_id      FK applicant      {NN}
  applied_on        {NN}
  source                              how this application came; defaults to the applicant's source
  cover_letter      {NVARCHAR(MAX)}
  stage             {NN}              applied, screening, shortlisted, interview, offer, hired, rejected, withdrawn
  stage_changed_at
  rejection_reason_id FK rejection_reason
  rejected_stage    {NVARCHAR(30)}    the stage it was rejected or withdrawn at ("non qualified" = rejected at screening)
  remarks
  employee_id       FK employee       set on hire: the employee created from this application
  hired_at
  UNIQUE (job_opening_id, applicant_id)

application_stage_history             every stage change, for the pipeline timeline and the dashboard
  id                PK
  application_id    FK application
  from_stage        {NVARCHAR(30)}
  to_stage          {NVARCHAR(30) NN}
  changed_at        {NN}
  changed_by_user_id FK user_account
  remarks

interview                             one round with one candidate ("re-interview" is a further round)
  id                PK
  company_id        FK company
  application_id    FK application
  round_no          {INT NN}          1, 2, 3 ... per application
  title                               "HR interview", "Technical"
  mode                                in_person, phone, video
  scheduled_at      {NN}              local wall-clock time, like attendance times
  duration_minutes  {NN}
  venue             {NVARCHAR(500)}   address or meeting link
  status                              scheduled, completed, cancelled, no_show
  result            {NVARCHAR(30)}    passed, failed, on_hold (set when completed)
  remarks

interview_interviewer                 the panel of an interview
  interview_id      FK interview
  employee_id       FK employee

interview_evaluation                  one interviewer's feedback on one interview
  id                PK
  interview_id      FK interview
  employee_id       FK employee       {NN} the interviewer
  rating            {INT NN}          1 to 5
  recommendation    {NVARCHAR(30) NN} strong_hire, hire, no_hire, strong_no_hire
  strengths         {NVARCHAR(MAX)}
  concerns          {NVARCHAR(MAX)}
  comments
  evaluated_at      {NN}
  evaluated_by_user_id FK user_account  who recorded it (the interviewer, or HR on their behalf)
  UNIQUE (interview_id, employee_id)

offer                                 the offer made to a candidate; a revised offer is a new row
  id                PK
  company_id        FK company
  application_id    FK application
  job_title_id      FK job_title
  designation_id    FK designation
  department_id     FK department
  branch_id         FK branch
  employment_type_id FK employment_type
  offered_salary    {NN}              gross a month (or a day / an hour by salary_frequency)
  salary_frequency  {NVARCHAR(30)}    monthly, daily, hourly
  joining_date      {NN}
  probation_months                    0 = no probation
  expires_on        {DATE}
  offer_letter_file_id FK stored_file
  status                              draft, sent, accepted, declined, withdrawn
  sent_at
  responded_at
  response_remarks  {NVARCHAR(MAX)}   the candidate's answer, the reason for declining
  remarks

rejection_reason                      Settings -> Rejection reasons
  id                PK
  company_id        FK company
  name
  is_active
  sort_order
  UNIQUE (company_id, name)
```

```
open_position 1──* job_opening 1──* application *──1 applicant
application 1──* application_stage_history
application 1──* interview 1──* interview_interviewer *──1 employee
interview 1──* interview_evaluation
application 1──* offer
rejection_reason 1──* application
application ──> employee (hired)
```
