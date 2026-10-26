## 4. Shifts and scheduling [sch]

```
time_slot                             a shift template (Attendance settings, Time Slots)
  id                PK
  company_id        FK company
  code                                TS-00004, from core.number_sequence prefix TS-
  name, color
  UNIQUE (company_id, name)
  start_time        {NN}              local time; for a flexible slot the window the hours may fall in
  end_time          {NN}              an end at or before the start ends the next day
  duration_minutes  {NN}              end minus start, overnight counted into the next day
  workable_minutes  {NN}              flexible: hours to work per day; fixed: duration minus breaks that are not inclusive
  is_flexible, is_overnight
  full_overtime, short_overtime

break_type                            Lunch, Prayer, Tea ...; identifiers are what a device or log sends
  id PK, company_id FK company, name, start_identifier {NN}, end_identifier {NN}
  UNIQUE (company_id, name)

time_slot_break                       the slot's planned breaks
  id PK, time_slot_id FK time_slot, break_type_id FK break_type {NN}, start_time {NN}, end_time {NN}, is_inclusive

roster_group                          a named weekly pattern employees are enrolled in for a period
  id                PK
  company_id        FK company
  title
  UNIQUE (company_id, title)
  from_date         {NN}
  to_date                             open-ended when blank
  description
  is_active

roster_group_day                      one row per weekday of the pattern
  id                PK
  roster_group_id   FK roster_group
  weekday           {TINYINT NN}      1 = Monday ... 7 = Sunday
  is_day_off
  time_slot_id      FK time_slot      optional: blank on a day off
  UNIQUE (roster_group_id, weekday)

roster_group_member                   an enrolment; one roster per employee at a time
  id                PK
  roster_group_id   FK roster_group
  employee_id       FK employee {NN}
  start_date        {NN}
  end_date                            open-ended when blank; set when discontinued

schedule_batch                        one "Create Scheduling" or "Apply Default Shift" action
  id                PK
  company_id        FK company
  batch_kind        {NN}              create, default_shift, import
  start_date        {NN}
  end_date          {NN}
  time_slot_id      FK time_slot      optional: one slot for every day
  roster_group_id   FK roster_group   optional: each weekday's slot from the roster pattern
  weekdays                            1..7 comma separated; blank = every day
  repeat_every_weeks {NN}             0 = never, 1..8
  step              {NN}              weeks on in each repeat cycle
  geo_fence_id      FK geo_fence      optional
  is_wfh

schedule                              planned shift: one employee, one shift
  id                PK
  company_id        FK company
  employee_id       FK employee
  work_date                           the business date the shift belongs to (its start)
  start_at, end_at                    local wall-clock date-time (company time zone), so overnight works
  time_slot_id      FK time_slot {NN}
  schedule_batch_id  FK schedule_batch  optional
  geo_fence_id      FK geo_fence      optional
  is_wfh
  planned_minutes   {NN}              flexible: workable minutes; fixed: shift minus breaks that are not inclusive

schedule_break
  id PK, schedule_id FK schedule, break_type_id FK break_type {NN}, start_at {NN}, end_at {NN}, is_inclusive

rest_day_rule                         "Create New Rest Day": employees, dates, repeat, step, weekdays, payable
  id                PK
  company_id        FK company
  from_date         {NN}
  to_date           {NN}
  weekdays          {NN}              1..7 comma separated (1 = Monday)
  repeat_every_weeks {NN}             0 = every week in the range, 1..8 = every n weeks
  step              {NN}              weeks on in each repeat cycle
  is_payable

rest_day_rule_employee
  rest_day_rule_id FK rest_day_rule, employee_id FK employee                 *──*

rest_day                              each resulting rest day; wins over a shift on the same date
  id                PK
  company_id        FK company
  employee_id       FK employee
  rest_date         {NN}
  is_payable
  rest_day_rule_id  FK rest_day_rule  optional: from a rule
  request_id        FK request        optional: from an approved rest-day request

holiday
  id                PK
  company_id        FK company
  name
  holiday_type      {NN}              public, local
  start_date        {NN}
  end_date          {NN}
  UNIQUE (company_id, name, start_date)
  description
  attendance_exempt                   on: the day is a holiday in the time sheet; off: listed, still worked

holiday_rule                          who the holiday applies to; no rules = everyone
  id                PK
  holiday_id        FK holiday
  rule_type         {NN}              employee, org_structure, geo_location, religion
  employee_id       FK employee       optional: rule_type employee
  location_id       FK location       optional: rule_type org_structure
  branch_id         FK branch         optional: rule_type org_structure
  country_id        FK country        optional: rule_type geo_location (employee's branch)
  state_id          FK state          optional: rule_type geo_location
  city_id           FK city           optional: rule_type geo_location
  religion          {NVARCHAR(50)}    rule_type religion
```

```
time_slot 1──* time_slot_break *──1 break_type
roster_group 1──* roster_group_day *──1 time_slot
roster_group 1──* roster_group_member *──1 employee
schedule_batch 1──* schedule 1──* schedule_break
employee 1──* schedule / rest_day
rest_day_rule 1──* rest_day
holiday 1──* holiday_rule
```
