## 19. Training [trn]

Source: the old product sold "training management" in its Premium plan; no design or written requirement exists, so
everything here is designed in comparison/11-performance-training.md. Added 2026-10-26. Owner: training.
Program materials are core.attachment rows (entity_type trn.training_program); certificates are uploaded files.

```
training_category                     Training settings -> Categories (Technical, Soft skills, Compliance, HSE)
  id PK, company_id FK company, name, is_active
  UNIQUE (company_id, name)

training_program                      Training -> Programs: a course the company runs or buys
  id                PK
  company_id        FK company
  title
  training_category_id  FK training_category  optional
  description
  delivery_mode                       classroom, online, blended, on_the_job
  provider_type                       internal, external
  provider_name
  duration_hours {DECIMAL(6,2)}
  cost_per_head
  issues_certificate {BIT}
  certificate_validity_months         a certificate expires after this many months; empty = never
  is_mandatory
  is_active
  UNIQUE (company_id, title)

training_session                      Training -> Sessions: one scheduled run of a program
  id                PK
  company_id        FK company
  training_program_id  FK training_program
  title                               the program's title unless given
  start_date {NN}, end_date {NN}
  start_time, end_time
  delivery_mode                       classroom, online
  venue {NVARCHAR(300)}
  online_link {NVARCHAR(500)}
  trainer_type                        internal, external
  trainer_employee_id  FK employee  an internal trainer
  trainer_name                        an external trainer
  capacity {INT}                      seats; empty = no limit
  nomination_deadline {DATE}
  status                              scheduled, completed, cancelled
  cost
  cancel_reason
  completed_at, cancelled_at

training_enrolment                    a nomination or a seat on a session, and its result
  id                PK
  company_id        FK company
  training_session_id  FK training_session
  employee_id {NN}  FK employee
  status                              requested, enrolled, rejected, withdrawn, cancelled, completed, not_completed
  nomination_source {NVARCHAR(30)}    self, manager, hr
  nominated_by_user_id  FK user_account
  decided_by_user_id  FK user_account
  decided_at
  decision_remarks {NVARCHAR(MAX)}
  attendance_percent {DECIMAL(5,2)}   days present / session days, set on completion
  score {DECIMAL(5,2)}                assessment score, if any
  result_remarks {NVARCHAR(MAX)}
  completed_at
  certificate_file_id FK stored_file
  certificate_no {NVARCHAR(100)}
  certificate_issued_date, certificate_expiry_date
  UNIQUE (training_session_id, employee_id)

training_attendance                   attendance per day of a session
  id PK, training_enrolment_id FK training_enrolment, attendance_date {NN}, status, remarks
  UNIQUE (training_enrolment_id, attendance_date)

training_feedback                     the participant's evaluation of a session (1-5)
  id PK, training_enrolment_id FK training_enrolment, overall_rating {INT} {NN}, trainer_rating {INT}, content_rating {INT}, comments
  UNIQUE (training_enrolment_id)
```

```
training_category 1──* training_program 1──* training_session 1──* training_enrolment *──1 employee
training_enrolment 1──* training_attendance
training_enrolment 1──0..1 training_feedback
training_program 1──* attachment   (materials)
```
