from datetime import datetime

from app.schemas.common import ApiModel


class FileOut(ApiModel):
    """An uploaded file. `url` is a signed download link that expires (settings.file_link_minutes)."""

    id: str
    name: str
    extension: str
    mime_type: str
    size_bytes: int
    module: str
    url: str
    created_at: datetime


class FileRef(ApiModel):
    """How a module shows a file on its own record: id, name and a signed link."""

    id: str
    name: str | None = None
    url: str
