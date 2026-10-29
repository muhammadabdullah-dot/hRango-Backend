"""Project management Docs (Backend Dependencies T1): rich text pages in a workspace, their comments and
the tasks they are linked to."""
from datetime import datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

DocVisibility = Literal["private", "workspace", "public"]


class DocIn(ApiModel):
    """content: the editor's JSON document; contentHtml: the same as HTML (counts, search, export).
    settings: {fontFamily, fontSize, header: {cover, title, subtitle, owner, contributors, updatedAt, toc}}."""
    title: str = Field(min_length=1, max_length=50)
    content: dict[str, Any] = Field(default_factory=dict)
    content_html: str = Field("", max_length=4_000_000)
    visibility: DocVisibility = "workspace"
    folder_id: int | None = None
    list_id: int | None = None
    cover_file_id: int | None = None
    settings: dict[str, Any] | None = None
    row_version: str | None = None


class DocArchiveIn(ApiModel):
    row_version: str | None = None
    # false restores an archived doc.
    archived: bool = True


class DocDuplicateIn(ApiModel):
    # Blank: "Copy of <title>".
    title: str | None = Field(None, max_length=50)


class DocTasksIn(ApiModel):
    task_ids: list[int] = Field(default_factory=list, max_length=500)


class DocCommentIn(ApiModel):
    body: str = Field(min_length=1, max_length=2000)
    parent_id: int | None = None


class PersonRefOut(ApiModel):
    id: str
    name: str | None


class DocOut(ApiModel):
    id: str
    workspace_id: str
    title: str
    content: dict[str, Any] | None
    content_html: str | None
    visibility: str
    folder_id: str | None
    list_id: str | None
    cover_file_id: str | None
    # The cover image: id, name and a signed link (expires).
    cover: FileRef | None = None
    settings: dict[str, Any] | None
    owner_id: str
    owner_name: str | None
    contributors: list[PersonRefOut]
    word_count: int
    character_count: int
    reading_minutes: int
    linked_task_ids: list[str]
    archived: bool
    archived_at: datetime | None
    created_at: datetime
    updated_at: datetime
    row_version: str


class DocCommentOut(ApiModel):
    id: str
    doc_id: str
    parent_id: str | None
    author_id: str
    author_name: str | None
    body: str
    edited_at: datetime | None
    created_at: datetime
    reply_count: int
    row_version: str
