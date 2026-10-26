"""Uploading files. Upload first, then send the returned id with the form that uses it.

Any signed-in user may upload; a record decides who reads its files: modules return signed links
(`url`), which work without the Authorization header and expire.
"""
from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile, status

from app.controllers import files_controller
from app.core.db import Db, get_db
from app.middlewares.auth import RequestContext, get_context
from app.schemas.common import Item
from app.schemas.files import FileOut

router = APIRouter(prefix="/files", tags=["files"])


@router.post("", response_model=Item[FileOut], status_code=status.HTTP_201_CREATED)
def upload(file: UploadFile = File(...), module: str = Form("core"), db: Db = Depends(get_db),
           ctx: RequestContext = Depends(get_context)) -> dict:
    return files_controller.upload(db, ctx, file.file, file.filename, module)


@router.get("/{file_id}", response_model=Item[FileOut])
def get_file(file_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> dict:
    """Details of a file you uploaded, with a fresh download link."""
    return files_controller.get(db, ctx, file_id)


@router.get("/{file_id}/download")
def download(file_id: int, token: str = Query(...), inline: bool = Query(False), db: Db = Depends(get_db)):
    """The file itself. `token` comes in the signed link; `inline=true` opens PDFs and images in the browser."""
    return files_controller.download(db, file_id, token, inline)


@router.delete("/{file_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_file(file_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> Response:
    """Deletes a file you uploaded that no record uses (409 FILE_IN_USE otherwise)."""
    files_controller.delete(db, ctx, file_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
