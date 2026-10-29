## 20. Custom Form [frm]

Source: the frontend's Custom Form module (Forms builder, My Forms, Responses; built 2026-10-28, no Figma frame)
and its contract in frontend/docs/backend-dependencies.md, "Custom Form" (CF1-CF3). Added 2026-10-29. Owner: forms.
Decisions: comparison/15-custom-forms.md.

HR builds a form (sections, questions of ten types, options), sends it to an audience (everyone, departments with
their sub-departments, branches or people) and collects the answers. A published form past its closing date reads as
closed. Anonymous forms keep the respondent (for one response per person and the author's own My submissions) but
never show it to HR. A question that has answers keeps its type and its options and cannot be removed.

```
form                                  Forms list and the builder ("New Form", "Edit")
  id                PK
  company_id        FK company
  title
  description
  category          {NVARCHAR(100)}   free text: Onboarding, IT, Feedback ...
  status                              draft, published, closed (a published form past closes_on reads as closed)
  closes_on                           the last day to answer; blank: open until closed
  audience_kind     {NN}              everyone, departments, branches, people (the targets are form_audience rows)
  is_one_per_person                   "One response per person"
  is_anonymous                        HR sees the answers without the respondent; fixed once there are responses
  published_at
  published_by_user_id FK user_account
  closed_at
  closed_by_user_id FK user_account
  INDEX (company_id, status)

form_section                          a titled group of questions, in order
  id                PK
  form_id           FK form
  sort_order
  title
  description

form_field                            a question
  id                PK
  form_id           FK form
  form_section_id   FK form_section   optional: blank = before the first section
  sort_order                          order in the whole form (position in its section is derived)
  field_type        {NN}              short_text, long_text, number, date, single_choice, multiple_choice, dropdown, checkbox, file, rating
  label             {NVARCHAR(500) NN}
  help_text         {NVARCHAR(1000)}
  is_required
  min_value         {DECIMAL(18,4)}   text: length; number: value; multiple_choice: picks
  max_value         {DECIMAL(18,4)}   as min_value; rating: the scale (3 to 10)

form_field_option                     the options of single_choice, multiple_choice and dropdown questions
  id                PK
  form_field_id     FK form_field
  sort_order
  label             {NVARCHAR(500) NN}

form_audience                         who the form is for when audience_kind is not everyone
  id                PK
  form_id           FK form
  unit_type         {NN}              department (with sub-departments), branch, employee
  unit_id           {NN}
  UNIQUE (form_id, unit_type, unit_id)

form_response                         one submission
  id                PK
  company_id        FK company
  form_id           FK form
  employee_id       FK employee {NN}  kept for anonymous forms too; never shown to HR then
  submitted_at      {NN}
  INDEX (form_id, submitted_at)
  INDEX (employee_id, form_id)

form_answer                           one answered question of a response; the column used depends on the type
  id                PK
  form_response_id  FK form_response
  form_field_id     FK form_field {NN}
  answer_text                         short_text, long_text
  answer_number     {DECIMAL(18,4)}   number, rating
  answer_date                         date
  answer_bool       {BIT NULL}        checkbox
  file_id           FK stored_file    file
  UNIQUE (form_response_id, form_field_id)

form_answer_option                    the chosen option(s) of a single_choice, dropdown or multiple_choice answer
  form_answer_id FK form_answer, form_field_option_id FK form_field_option
```

```
form 1──* form_section / form_field / form_audience / form_response
form_section 1──* form_field
form_field 1──* form_field_option / form_answer
form_response 1──* form_answer
form_answer 1──* form_answer_option
form_field_option 1──* form_answer_option
```
