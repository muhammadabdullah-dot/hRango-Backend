## 18. Performance [perf]

Source: the documents name the module only (sidebar "Performance", Payroll's older sub-menu "Appraisal", the old
product's "appraisals, 360-degree feedback, custom KPIs", the app's "KPI management"); Figma "HRango Dashboard App
Version" designs My Performance (goals with Goal Name, Due Date, Completed, and a Performance Overview). Everything
else is designed in comparison/11-performance-training.md. Added 2026-10-26. Owner: performance.

```
rating_scale                          Performance settings -> Rating Scales (1 Unsatisfactory ... 5 Outstanding)
  id                PK
  company_id        FK company
  name
  is_default                          the scale a new appraisal form starts with
  is_active
  UNIQUE (company_id, name)

rating_scale_level                    one step on a scale; ratings may fall between steps
  id PK, rating_scale_id FK rating_scale, score {DECIMAL(5,2)} {NN}, label {NVARCHAR(100)} {NN}, description
  UNIQUE (rating_scale_id, score)

kpi                                   Performance -> KPIs: the KPI library, grouped by key result area
  id                PK
  company_id        FK company
  name
  key_result_area                     the KRA the KPI belongs to (Sales, Quality, People ...)
  description
  measure_type                        percentage, number, amount, rating, yes_no
  target_value {DECIMAL(18,2)}
  unit {NVARCHAR(30)}
  default_weight {DECIMAL(5,2)}
  department_id     FK department     optional; suggested for this department
  job_title_id      FK job_title      optional; suggested for this job title
  is_active
  UNIQUE (company_id, name)

appraisal_form                        Performance settings -> Appraisal Forms: what a cycle rates and the weights
  id                PK
  company_id        FK company
  name
  description
  rating_scale_id {NN}  FK rating_scale
  goals_weight {DECIMAL(5,2)} {NN}    share of the score from goal achievement (0-100); criteria weights make up the rest
  has_self_review                     employees rate themselves before their manager does
  is_active
  UNIQUE (company_id, name)

appraisal_criterion                   a line on a form: a KPI from the library or a competency written on the form
  id                PK
  appraisal_form_id FK appraisal_form
  kpi_id            FK kpi            optional
  name
  description
  weight {DECIMAL(5,2)} {NN}
  sort_order

appraisal_cycle                       Performance -> Appraisals: one review round ("Annual 2026")
  id                PK
  company_id        FK company
  name
  appraisal_form_id {NN}  FK appraisal_form   fixed once the cycle is launched
  start_date {NN}                     the period under review
  end_date {NN}
  self_review_due_date
  manager_review_due_date
  status                              draft, active, closed
  launched_at, closed_at
  UNIQUE (company_id, name)

appraisal                             one employee in one cycle: self review, manager review, final rating, outcome
  id                PK
  company_id        FK company
  appraisal_cycle_id FK appraisal_cycle
  employee_id {NN}  FK employee
  reviewer_employee_id  FK employee  the line manager when the person joined the cycle
  status                              draft, self_review, manager_review, reviewed, finalised
  goals_score {DECIMAL(5,2)}          goal achievement placed on the rating scale
  self_score {DECIMAL(5,2)}           weighted: self ratings and goal achievement
  manager_score {DECIMAL(5,2)}        weighted: manager ratings and goal achievement
  final_score {DECIMAL(5,2)}          the manager score unless HR sets another when finalising
  final_rating_label {NVARCHAR(100)}  the scale level nearest the final score
  self_comments {NVARCHAR(MAX)}, manager_comments {NVARCHAR(MAX)}, final_comments {NVARCHAR(MAX)}
  development_needs {NVARCHAR(MAX)}   training the manager recommends (read by Training)
  outcome {NVARCHAR(30)}              no_change, increment, promotion, improvement_plan
  self_submitted_at, manager_submitted_at, finalised_at
  finalised_by_user_id  FK user_account
  letter_file_id    FK stored_file    the appraisal letter (Documents: "Appraisal Letter")
  UNIQUE (appraisal_cycle_id, employee_id)

appraisal_rating                      one criterion rated on one appraisal, by the employee and by the manager
  id                PK
  appraisal_id      FK appraisal
  appraisal_criterion_id {NN}  FK appraisal_criterion
  self_rating {DECIMAL(5,2)}, manager_rating {DECIMAL(5,2)}
  self_comment {NVARCHAR(MAX)}, manager_comment {NVARCHAR(MAX)}
  UNIQUE (appraisal_id, appraisal_criterion_id)

goal                                  My Performance -> Goals (Goal Name, Due Date, Completed); project tasks link to goals
  id                PK
  company_id        FK company
  employee_id {NN}  FK employee
  appraisal_cycle_id  FK appraisal_cycle  optional; the cycle it counts in (otherwise the cycle its due date falls in)
  kpi_id            FK kpi            optional
  title                               Goal Name
  description
  start_date
  due_date {NN}
  weight {DECIMAL(5,2)} {NN}          relative weight among the person's goals
  target_value {DECIMAL(18,2)}, actual_value {DECIMAL(18,2)}
  progress {DECIMAL(5,2)} {NN}        0-100; from actual / target when a target is set
  status                              not_started, in_progress, completed, cancelled
  completed_at
  set_by_user_id    FK user_account

goal_check_in                         a progress update on a goal (its history)
  id PK, goal_id FK goal, progress {DECIMAL(5,2)} {NN}, actual_value {DECIMAL(18,2)}, status, comments

increment_proposal                    an increment a finalised appraisal proposes; applied as payroll's salary revision
  id                PK
  company_id        FK company
  appraisal_id      FK appraisal
  employee_id {NN}  FK employee
  change_type {NN}                    flat, percent (as pay.usp_salary_revision_save)
  change_value {NN}
  effective_date {NN}
  current_salary                      the salary in force on the effective date when proposed
  proposed_salary
  status                              proposed, applied, rejected
  employee_salary_id  FK employee_salary  the salary revision written when applied
  decided_at
  decided_by_user_id  FK user_account
  remarks
  UNIQUE (appraisal_id)
```

```
rating_scale 1──* rating_scale_level
rating_scale 1──* appraisal_form 1──* appraisal_criterion *──0..1 kpi
appraisal_form 1──* appraisal_cycle 1──* appraisal *──1 employee
appraisal 1──* appraisal_rating *──1 appraisal_criterion
employee 1──* goal *──0..1 appraisal_cycle / kpi
goal 1──* goal_check_in
appraisal 1──0..1 increment_proposal ──> employee_salary   (payroll's salary revision)
```
