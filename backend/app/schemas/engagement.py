"""Engagement: newsfeed posts, reactions, comments, moderation, settings and surveys."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel

Visibility = Literal["public", "department", "branch"]
ReactionKind = Literal["like", "love", "celebrate", "support", "insightful", "funny"]
QuestionType = Literal["single", "dropdown", "multiple", "text", "paragraph", "rating"]
SurveyStatus = Literal["draft", "published", "closed"]


# --------------------------------------------------------------------------- posts

class PostIn(ApiModel):
    """Create Post / Edit Post. Photos and videos are uploaded first (POST /api/files, module engagement)."""
    body: str | None = Field(None, max_length=5000)
    visibility: Visibility = "public"
    department_id: int | None = None
    branch_id: int | None = None
    media_file_ids: list[int] = Field(default_factory=list, max_length=20)
    mention_ids: list[int] = Field(default_factory=list, max_length=50)
    row_version: str | None = None


class MediaOut(ApiModel):
    file_id: str
    media_type: str
    name: str | None = None
    mime_type: str | None = None
    url: str | None = None


class ReactionCount(ApiModel):
    kind: str
    count: int


class MentionOut(ApiModel):
    employee_id: str
    name: str | None = None


class PostOut(ApiModel):
    id: str
    author_id: str
    author_name: str | None
    author_photo_url: str | None = None
    body: str | None
    visibility: str
    department_id: str | None
    department_name: str | None
    branch_id: str | None
    branch_name: str | None
    posted_at: datetime
    edited_at: datetime | None
    is_pinned: bool
    pinned_at: datetime | None
    is_hidden: bool
    hidden_at: datetime | None
    hidden_reason: str | None
    is_mine: bool
    can_moderate: bool
    reaction_count: int
    reactions: list[ReactionCount]
    my_reaction: str | None
    comment_count: int
    view_count: int
    media: list[MediaOut]
    mentions: list[MentionOut]
    link: str
    row_version: str


class PinIn(ApiModel):
    pinned: bool


class HideIn(ApiModel):
    hidden: bool
    reason: str | None = Field(None, max_length=500)


class ViewOut(ApiModel):
    id: str
    view_count: int
    counted: bool


class ReactionIn(ApiModel):
    """The caller's reaction; null takes it off."""
    kind: ReactionKind | None = None


class ReactorOut(ApiModel):
    employee_id: str
    employee_name: str | None
    photo_url: str | None = None
    department_name: str | None
    kind: str
    reacted_at: datetime


# --------------------------------------------------------------------------- comments

class CommentIn(ApiModel):
    body: str = Field(min_length=1, max_length=2000)
    parent_id: int | None = None
    mention_ids: list[int] = Field(default_factory=list, max_length=50)


class CommentEditIn(ApiModel):
    body: str = Field(min_length=1, max_length=2000)
    mention_ids: list[int] = Field(default_factory=list, max_length=50)
    row_version: str | None = None


class LikeIn(ApiModel):
    liked: bool


class CommentOut(ApiModel):
    id: str
    post_id: str
    parent_id: str | None
    author_id: str
    author_name: str | None
    author_photo_url: str | None = None
    body: str
    commented_at: datetime
    edited_at: datetime | None
    is_mine: bool
    like_count: int
    liked_by_me: bool
    reply_count: int
    mentions: list[MentionOut]
    replies: list["CommentOut"] = Field(default_factory=list)
    row_version: str


# --------------------------------------------------------------------------- settings

class SettingsIn(ApiModel):
    who_may_post: Literal["everyone", "moderators"]
    allow_comments: bool
    max_media_per_post: int = Field(ge=1, le=20)
    row_version: str | None = None


class SettingsOut(ApiModel):
    who_may_post: str
    allow_comments: bool
    max_media_per_post: int
    row_version: str | None


# --------------------------------------------------------------------------- surveys

class QuestionIn(ApiModel):
    question_type: QuestionType
    question_text: str = Field(min_length=1, max_length=1000)
    is_required: bool = False
    options: list[str] = Field(default_factory=list, max_length=50)
    scale_min: int | None = None
    scale_max: int | None = None
    scale_min_label: str | None = Field(None, max_length=100)
    scale_max_label: str | None = Field(None, max_length=100)


class AudienceIn(ApiModel):
    unit_type: Literal["department", "branch", "employee"]
    unit_id: int


class SurveyIn(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(None, max_length=4000)
    is_anonymous: bool = False
    opens_on: date | None = None
    closes_on: date | None = None
    questions: list[QuestionIn] = Field(default_factory=list, max_length=100)
    audience: list[AudienceIn] = Field(default_factory=list)
    row_version: str | None = None


class RowVersionIn(ApiModel):
    row_version: str | None = None


class ClosingDateIn(ApiModel):
    closes_on: date | None = None
    row_version: str | None = None


class OptionOut(ApiModel):
    id: str
    sort_order: int | None
    option_text: str


class QuestionOut(ApiModel):
    id: str
    sort_order: int | None
    question_type: str
    question_text: str
    is_required: bool
    scale_min: int | None = None
    scale_max: int | None = None
    scale_min_label: str | None = None
    scale_max_label: str | None = None
    options: list[OptionOut] = Field(default_factory=list)


class AudienceOut(ApiModel):
    unit_type: str
    unit_id: str
    name: str | None = None


class SurveyListOut(ApiModel):
    id: str
    title: str
    description: str | None
    is_anonymous: bool
    status: str
    opens_on: date | None
    closes_on: date | None
    is_open: bool
    published_at: datetime | None
    closed_at: datetime | None
    question_count: int
    audience_count: int
    response_count: int
    skipped_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class SurveyOut(SurveyListOut):
    questions: list[QuestionOut]
    audience: list[AudienceOut]


class MySurveyOut(ApiModel):
    """A survey as the person asked sees it. myStatus: pending, answered, skipped, missed."""
    id: str
    title: str
    description: str | None
    is_anonymous: bool
    status: str
    opens_on: date | None
    closes_on: date | None
    is_open: bool
    question_count: int
    my_status: str
    responded_at: datetime | None
    skipped_at: datetime | None
    questions: list[QuestionOut] | None = None


class AnswerIn(ApiModel):
    """One answer: optionIds for single / dropdown / multiple, text for text / paragraph, rating for rating."""
    question_id: int
    option_ids: list[int] = Field(default_factory=list, max_length=50)
    text: str | None = Field(None, max_length=5000)
    rating: int | None = None


class ResponseIn(ApiModel):
    answers: list[AnswerIn] = Field(default_factory=list, max_length=100)


class OptionResult(ApiModel):
    option_id: str
    option_text: str
    count: int
    percent: Decimal


class RatingResult(ApiModel):
    value: int
    count: int


class QuestionResult(ApiModel):
    question_id: str
    sort_order: int | None
    question_type: str
    question_text: str
    is_required: bool
    answer_count: int
    scale_min: int | None = None
    scale_max: int | None = None
    scale_min_label: str | None = None
    scale_max_label: str | None = None
    average_rating: Decimal | None = None
    options: list[OptionResult] = Field(default_factory=list)
    ratings: list[RatingResult] = Field(default_factory=list)
    text_answers: list[str] = Field(default_factory=list)


class SurveyResultsOut(ApiModel):
    survey_id: str
    title: str
    is_anonymous: bool
    status: str
    opens_on: date | None
    closes_on: date | None
    audience_count: int
    response_count: int
    skipped_count: int
    response_rate: Decimal
    questions: list[QuestionResult]


class AnswerOut(ApiModel):
    question_id: str
    option_id: str | None = None
    option_text: str | None = None
    answer_text: str | None = None
    rating_value: int | None = None


class ResponseOut(ApiModel):
    response_id: str
    employee_id: str | None
    employee_code: str | None
    employee_name: str | None
    department_name: str | None
    submitted_at: datetime
    answers: list[AnswerOut]
