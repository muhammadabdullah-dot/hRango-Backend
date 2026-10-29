# 15 Custom Form: forms, My Forms, responses — documents vs ERD vs backend

Status: gray structure built 29 Oct 2026 (backend `/api/forms`, schema `frm`). Every endpoint the frontend
calls exists with its shapes, permission codes, validation, rowVersion checks and tests; the business rules
marked TODO below are not built yet.

Sources:

- **Frontend contract**: `frontend/docs/backend-dependencies.md`, "Custom Form" (CF1 forms, CF2 filling,
  CF3 responses); shapes in `frontend/src/features/custom-forms/api/custom-forms.dto.ts`; editing rules in
  `frontend/README.md`, "Custom Form". Built from these: no Figma frame and no requirement document defines
  the module (the comparison README listed "Custom Forms: menu items only").
- **Mini SRS**: no requirement. NFR-3 (changes recorded with user and time) applies: `core.audit_log` rows on
  create, update, publish, close, delete, duplicate.
- Closest existing pattern: engagement surveys (`comparison/13-engagement.md`).

## Screens and features

| Screen / feature | ERD tables | Endpoints | Decision |
|---|---|---|---|
| Forms list (status chips, search) | form | `GET /forms?q&status&page&pageSize` | Build: newest change first; q matches title, category, description; status is the effective status |
| Builder: details, audience, one response per person, anonymous, sections, ten question types | form, form_section, form_field, form_field_option, form_audience | `POST /forms`, `GET /forms/{id}`, `PUT /forms/{id}` | Build: the whole form in one call; ids keep sections, questions and options (and their answers) |
| Publish / Reopen, Close | form.status | `POST /forms/{id}/publish`, `POST /forms/{id}/close` | Build |
| Duplicate | all of the above | `POST /forms/{id}/duplicate` | Build: draft "Copy of …", new ids, no responses, a past closing date dropped |
| Delete | all, responses too | `DELETE /forms/{id}?rowVersion=` | Build: drafts, forms without responses, closed forms (with their responses) |
| My Forms: Assigned to me, Fill in | form_audience, form_response | `GET /forms/assigned`, `GET /forms/assigned/{id}`, `POST /forms/{id}/responses` | Build |
| My Forms: My submissions, View | form_response, form_answer | `GET /forms/my-responses`, `GET /forms/responses/{id}` | Build |
| Responses: answers table, counts as bars, View one | form_response, form_answer, form_answer_option | `GET /forms/{id}/responses`, `GET /forms/{id}/responses/summary`, `GET /forms/responses/{id}` | Build |
| Export CSV | — | (the UI pages through `GET /forms/{id}/responses`) | Client-side; `forms.responses.export` gates the button |
| File upload question | form_answer.file_id → core.stored_file | `POST /api/files` (module `forms`) then the id as the answer | Build |

15 endpoints: forms 8, filling 4, responses 3. Tests: 7 (`tests/test_forms.py`).

## ERD (erd/source/20-frm.md, new)

`form` (title, description, category, status, closes_on, audience_kind, is_one_per_person, is_anonymous,
published / closed by and at), `form_section`, `form_field` (field_type, label, help_text, is_required,
min_value, max_value, optional section), `form_field_option`, `form_audience` (department / branch / employee
rows; none when everyone), `form_response` (employee kept even when anonymous), `form_answer` (answer_text,
answer_number, answer_date, answer_bool, file_id by type; one per question per response),
`form_answer_option` (chosen options of choice answers).

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | A form can be edited in any status. Once a question has answers it keeps its type (422 `fields.{i}.type`) and its options (422 `fields.{i}.options`) and cannot be left out (409 `FORM_HAS_RESPONSES`); once the form has responses, anonymity is fixed (422 `anonymous`). Rewording, reordering, new questions and options, Required, settings and audience stay free. | The frontend's editing rules. |
| 2 | A published form past its closing date reads as closed everywhere (`status`, list filter, answering). Reopen = publish again, which needs a closing date that has not passed. | No scheduler needed. |
| 3 | Delete is refused (409 `FORM_HAS_RESPONSES`) only while the form is open and has responses; drafts, forms without responses and closed forms are deleted with their responses. | Frontend rule. |
| 4 | Audience: everyone, departments (with sub-departments), branches or people; evaluated live, people who left or were switched off excluded. Only employees answer (a user without an employee record sees no forms). | Same as surveys. |
| 5 | Anonymous forms keep the respondent (for one response per person and My submissions) but never show it to HR: `respondent` is null in lists, the summary and one response; searching responses by respondent is ignored; the event carries no employee. | Frontend: "the server still keeps it". Weaker than surveys' anonymity (see Gaps). |
| 6 | Responses of named forms are shown for the respondents the caller's `forms.responses.view` scope reaches (`auth.fn_visible_employees`); anonymous forms show all to holders. `GET /forms/responses/{id}`: HR as above, or the response's author. | README RBAC rule. |
| 7 | Answer checks: the value's JSON type by question type; options must belong to the question; text length (min / max, default max 500 short, 5000 long); number range; multiple-choice picks (min / max); rating 1…scale (scale 3–10, default 5); files must be this company's uploads; dates `yyyy-MM-dd`; a required checkbox must be ticked; `null`, `""` and `[]` are "no answer". Errors are 422 `answers.<fieldId>` (the first one only). | Spec; basic checks. |
| 8 | One response per person is checked under a lock at submit (409 `ALREADY_RESPONDED`); responses are final (no edit). | Frontend: editing a submitted response not built. |
| 9 | Stale rowVersion answers 409 `STALE_ROW_VERSION` with fieldErrors `rowVersion`. | Spec code. |
| 10 | Summary counts: every option of choice and dropdown questions (zeros included), checkbox `true` / `false`, rating `1`…scale; other types `counts: []` with `answered`. | Spec. |

## Permissions (app/catalogue/forms.py)

| Code | Actions | Used for |
|---|---|---|
| `forms.forms` | view, create, edit, publish, delete | Forms list and builder; create also duplicates; publish also closes and reopens |
| `forms.responses` | view, export | the Responses screen (scope = whose named answers); export gates the CSV button |
| `forms.my_forms` | view, submit | My Forms: assigned list, fill, my submissions, view own response |

Proposed default-role grants (`app/core/default_roles.py`, owned elsewhere): add
`("forms.my_forms.*", "own")` to `SELF_SERVICE` (Employee, Line Manager, Department Head). HR Manager and
Company Administrator get everything through `*`; HR Officer gets everything except `forms.forms.delete`;
Executive gets the `.view` codes (including `forms.responses.view` company-wide; exclude it if executives
should not read answers). Until then the tests grant `forms.my_forms.*` per user (`tests/factories_forms.py`).

## Events (EVENTS in app/catalogue/forms.py)

`forms.form_published`, `forms.form_closed`, `forms.response_submitted` (no employee for anonymous forms,
never the answers).

## Left as TODO

- Notify the audience on publish (inbox, `core.usp_notification_add_employee @quiet = 1`); the frontend lists
  "notifying the audience on publish" as not built either.
- Min / max for date questions; per-question file type limits; multiple-choice max picks checked against the
  number of options when saving.
- Reordering options is saved as sent (the frontend does not offer it yet); conditional logic not built.
- Editing a submitted response; reminders to people who have not answered.
- Answer validation reports only the first wrong answer, not all of them at once.
- Anonymity is "hidden from HR", not real anonymity: the respondent and the exact time stay in
  `form_response` (needed for one response per person and My submissions).
- History screen: audit rows are written per action, not per changed field.

## Cross-module needs

- `app/core/default_roles.py`: `("forms.my_forms.*", "own")` in `SELF_SERVICE`.
- Files: uploads for answers use module `forms` (already accepted).
- Frontend: switch file uploads from module `core` to `forms`; remove the "pending" wrappers.
