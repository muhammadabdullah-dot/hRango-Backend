from datetime import datetime

from pydantic import Field

from app.schemas.common import ApiModel


class EventTypeOut(ApiModel):
    type: str
    module: str
    description: str


class WebhookIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=8, max_length=1000)
    events: list[str] = Field(min_length=1)
    is_active: bool = True
    row_version: str | None = None


class RotateIn(ApiModel):
    row_version: str


class WebhookOut(ApiModel):
    id: str
    name: str
    url: str
    events: list[str]
    is_active: bool
    secret_hint: str
    failure_count: int
    last_delivery_at: datetime | None
    last_status_code: int | None
    pending_count: int
    failed_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class WebhookWithSecretOut(WebhookOut):
    """Returned once, when a webhook is created or its secret rotated: keep the secret, it is not shown again."""

    secret: str


class DeliveryOut(ApiModel):
    id: str
    status: str
    attempts: int
    next_attempt_at: datetime | None
    last_attempt_at: datetime | None
    response_code: int | None
    response_body: str | None
    error: str | None
    event_id: str
    event_type: str
    entity_type: str | None
    entity_id: str | None
    occurred_at: datetime
    created_at: datetime


class PingOut(ApiModel):
    delivery_id: str
    event_id: str
