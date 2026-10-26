from datetime import datetime

from app.schemas.common import ApiModel


class NotificationOut(ApiModel):
    id: str
    notification_type: str | None
    title: str
    body: str | None
    # Where the frontend should go when the notification is clicked (e.g. /requests/leave/123).
    link: str | None
    entity_type: str | None
    entity_id: str | None
    read: bool
    read_at: datetime | None
    created_at: datetime


class InboxSummary(ApiModel):
    unread: int
    latest: list[NotificationOut]


class ChangedOut(ApiModel):
    changed: int
