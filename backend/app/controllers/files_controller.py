from typing import Any, BinaryIO

from fastapi.responses import FileResponse

from app.core import files
from app.core.db import Db
from app.middlewares.auth import RequestContext
from app.schemas.files import FileOut
from app.services import files_service


def _out(row: dict[str, Any]) -> FileOut:
    return FileOut(**row, url=files.file_url(row["id"], row["company_id"]))


def upload(db: Db, ctx: RequestContext, stream: BinaryIO, name: str | None, module: str) -> dict:
    return {"data": _out(files_service.upload(db, ctx, stream, name, module))}


def get(db: Db, ctx: RequestContext, file_id: int) -> dict:
    return {"data": _out(files_service.get_own(db, ctx, file_id))}


def download(db: Db, file_id: int, token: str, inline: bool) -> FileResponse:
    row, path = files_service.for_download(db, file_id, token)
    show_inline = inline and row["mime_type"] in files.INLINE
    return FileResponse(path, media_type=row["mime_type"], filename=row["name"],
                        content_disposition_type="inline" if show_inline else "attachment",
                        headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "private, max-age=300"})


def delete(db: Db, ctx: RequestContext, file_id: int) -> None:
    files_service.delete(db, ctx, file_id)
