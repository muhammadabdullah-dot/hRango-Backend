"""External file sources (Backend Dependencies T9): Google Drive, Dropbox, Box and OneDrive, connected per
person, to attach files to tasks as links."""
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel

Provider = Literal["google_drive", "dropbox", "box", "onedrive"]
PROVIDERS: tuple[str, ...] = ("google_drive", "dropbox", "box", "onedrive")


class StorageConnectionOut(ApiModel):
    provider: str
    connected: bool
    account_email: str | None
    connected_at: datetime | None


class StorageConnectIn(ApiModel):
    # The app path to return to after the provider's sign-in, e.g. /project-management/workspaces/12.
    redirect_path: str = Field("/", max_length=500, pattern=r"^/")


class StorageConnectOut(ApiModel):
    auth_url: str


class StorageFileOut(ApiModel):
    id: str
    name: str
    mime_type: str | None
    size: int | None
    web_url: str | None
    is_folder: bool


class StorageFilesOut(ApiModel):
    data: list[StorageFileOut]
    next_page_token: str | None
