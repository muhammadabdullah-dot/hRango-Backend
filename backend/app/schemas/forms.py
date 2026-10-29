"""Custom Form: forms (builder), filling (My Forms) and responses. Shapes as the frontend's
src/features/custom-forms/api/custom-forms.dto.ts."""
from datetime import date, datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

FieldType = Literal["short_text", "long_text", "number", "date", "single_choice", "multiple_choice", "dropdown",
                    "checkbox", "file", "rating"]
AudienceKind = Literal["everyone", "departments", "branches", "people"]
FormStatus = Literal["draft", "published", "closed"]
Limit = float | None


# --------------------------------------------------------------------------- requests

class AudienceIn(ApiModel):
    kind: AudienceKind = "everyone"
    ids: list[int] = Field(default_factory=list, max_length=1000)


class SectionIn(ApiModel):
    """`key` is unique in the request: the id when the section has one, else any text."""
    key: str = Field(min_length=1, max_length=100)
    id: int | None = None
    title: str = Field("", max_length=200)
    description: str | None = Field(None, max_length=4000)


class OptionIn(ApiModel):
    id: int | None = None
    label: str = Field("", max_length=500)


class FieldIn(ApiModel):
    """A question. With an id it is kept (and keeps its answers); without, it is new."""
    id: int | None = None
    section_key: str | None = Field(None, max_length=100)
    type: FieldType
    label: str = Field("", max_length=500)
    help_text: str | None = Field(None, max_length=1000)
    required: bool = False
    options: list[OptionIn] = Field(default_factory=list, max_length=100)
    min: Limit = Field(None, ge=-1e12, le=1e12)
    max: Limit = Field(None, ge=-1e12, le=1e12)


class FormIn(ApiModel):
    """POST /forms and PUT /forms/{id} (with rowVersion). Sections and fields in order."""
    title: str = Field(max_length=200)
    description: str | None = Field(None, max_length=4000)
    category: str | None = Field(None, max_length=100)
    closes_on: date | None = None
    audience: AudienceIn = Field(default_factory=AudienceIn)
    one_response_per_person: bool = False
    anonymous: bool = False
    sections: list[SectionIn] = Field(default_factory=list, max_length=50)
    fields: list[FieldIn] = Field(default_factory=list, max_length=200)
    row_version: str | None = None


class RowVersionIn(ApiModel):
    row_version: str | None = None


class AnswerIn(ApiModel):
    """value by the field's type: text / date a string (yyyy-MM-dd); number / rating a number; single choice /
    dropdown an option id; multiple choice option ids; checkbox a boolean; file an upload id."""
    field_id: int
    value: bool | int | float | str | list[int] | None = None


class ResponseIn(ApiModel):
    answers: list[AnswerIn] = Field(default_factory=list, max_length=500)


# --------------------------------------------------------------------------- forms

class NamedRef(ApiModel):
    id: str
    name: str


class AudienceOut(ApiModel):
    kind: str
    targets: list[NamedRef]


class SectionOut(ApiModel):
    id: str
    title: str
    description: str | None
    position: int


class OptionOut(ApiModel):
    id: str
    label: str


class FieldOut(ApiModel):
    id: str
    section_id: str | None
    position: int
    type: str
    label: str
    help_text: str | None
    required: bool
    options: list[OptionOut]
    min: int | float | None
    max: int | float | None


class FormSummaryOut(ApiModel):
    id: str
    title: str
    description: str | None
    category: str | None
    status: str
    closes_on: date | None
    audience: AudienceOut
    field_count: int
    response_count: int
    anonymous: bool
    updated_at: datetime
    published_at: datetime | None
    row_version: str


class FormOut(FormSummaryOut):
    one_response_per_person: bool
    created_by: NamedRef | None
    created_at: datetime
    closed_at: datetime | None
    sections: list[SectionOut]
    fields: list[FieldOut]


# --------------------------------------------------------------------------- filling

class AssignedFormOut(ApiModel):
    id: str
    title: str
    description: str | None
    category: str | None
    status: str
    closes_on: date | None
    field_count: int
    one_response_per_person: bool
    anonymous: bool
    my_response_count: int
    last_response_id: str | None
    last_submitted_at: datetime | None
    can_respond: bool


class AssignedFormDetailOut(AssignedFormOut):
    sections: list[SectionOut]
    fields: list[FieldOut]


class MyResponseOut(ApiModel):
    id: str
    form_id: str
    form_title: str
    category: str | None
    anonymous: bool
    submitted_at: datetime


# --------------------------------------------------------------------------- responses

class RespondentOut(ApiModel):
    id: str
    name: str
    code: str | None
    department_name: str | None


class AnswerOut(ApiModel):
    field_id: str
    value: bool | int | float | str | list[str] | None
    file: FileRef | None


class ResponseOut(ApiModel):
    id: str
    form_id: str
    respondent: RespondentOut | None
    submitted_at: datetime
    answers: list[AnswerOut]


class ResponseFormOut(ApiModel):
    id: str
    title: str
    description: str | None
    anonymous: bool
    sections: list[SectionOut]
    fields: list[FieldOut]


class ResponseDetailOut(ResponseOut):
    form: ResponseFormOut


class SummaryCount(ApiModel):
    value: str
    count: int


class SummaryField(ApiModel):
    field_id: str
    answered: int
    counts: list[SummaryCount]


class ResponseSummaryOut(ApiModel):
    total: int
    fields: list[SummaryField]
