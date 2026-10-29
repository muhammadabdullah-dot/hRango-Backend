"""Permission codes and events for Custom Form.

Forms and Responses are HR screens. My Forms is self-service: forms.my_forms.* opens it, and each form's
audience (everyone, departments, branches, people) decides which forms a person sees and may answer, not
scopes. Responses of named forms are shown for the respondents the forms.responses.view scope reaches;
anonymous forms never show the respondent. Export is a button only (the CSV is built in the browser from
GET /forms/{id}/responses).
"""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("forms.forms", "Custom forms (builder, publishing, closing)", ("view", "create", "edit", "publish", "delete"), False),
    ("forms.responses", "Custom form responses (answers, counts, export)", ("view", "export"), False),
    ("forms.my_forms", "My Forms (forms sent to me, my submissions)", ("view", "submit"), False),
]

EVENTS: list[tuple[str, str]] = [
    ("forms.form_published", "A custom form was published or reopened (title, closing date, audience size)."),
    ("forms.form_closed", "A custom form was closed (number of responses)."),
    ("forms.response_submitted",
     "Someone answered a custom form (the employee only for named forms; never the answers)."),
]
