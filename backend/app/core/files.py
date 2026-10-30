"""File storage on this server's disk, and signed download links.

Layout: <upload root>/<company id>/<module>/<yyyy>/<mm>/<uuid>.<ext>. The client's file name is kept
in core.stored_file for downloads only and never touches the path. Only known file types are
accepted, and their first bytes must match the type.

Modules never serve files themselves: when a record a user may read has files, the module returns
`file_url(file_id, company_id)` next to the id. The link carries a signed, short-lived token, so it
works in a plain <a href> or <img src> without the Authorization header.
"""
import hashlib
import os
import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import BinaryIO

import jwt

from app.core.config import settings
from app.core.errors import AppError

CHUNK = 1024 * 1024

# extension -> (mime type, check of the first bytes)
_TEXT = "text"
TYPES: dict[str, tuple[str, object]] = {
    "pdf": ("application/pdf", [b"%PDF"]),
    "png": ("image/png", [b"\x89PNG\r\n\x1a\n"]),
    "jpg": ("image/jpeg", [b"\xff\xd8\xff"]),
    "jpeg": ("image/jpeg", [b"\xff\xd8\xff"]),
    "gif": ("image/gif", [b"GIF87a", b"GIF89a"]),
    "webp": ("image/webp", "webp"),
    "doc": ("application/msword", [b"\xd0\xcf\x11\xe0"]),
    "xls": ("application/vnd.ms-excel", [b"\xd0\xcf\x11\xe0"]),
    "ppt": ("application/vnd.ms-powerpoint", [b"\xd0\xcf\x11\xe0"]),
    "docx": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", [b"PK\x03\x04"]),
    "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", [b"PK\x03\x04"]),
    "pptx": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", [b"PK\x03\x04"]),
    "odt": ("application/vnd.oasis.opendocument.text", [b"PK\x03\x04"]),
    "ods": ("application/vnd.oasis.opendocument.spreadsheet", [b"PK\x03\x04"]),
    "zip": ("application/zip", [b"PK\x03\x04"]),
    "csv": ("text/csv", _TEXT),
    "txt": ("text/plain", _TEXT),
    "rtf": ("application/rtf", [b"{\\rtf"]),
    "mp4": ("video/mp4", "ftyp"),
    "mov": ("video/quicktime", "ftyp"),
    "webm": ("video/webm", [b"\x1a\x45\xdf\xa3"]),
}
INLINE = {"application/pdf", "image/png", "image/jpeg", "image/gif", "image/webp", "video/mp4", "video/quicktime",
          "video/webm", "text/plain"}
_MODULE = re.compile(r"^[a-z][a-z_]{1,29}$")


@dataclass(frozen=True)
class Stored:
    name: str
    extension: str
    mime_type: str
    size_bytes: int
    sha256: str
    storage_path: str


def upload_root() -> Path:
    root = Path(settings.upload_dir) if settings.upload_dir else Path(__file__).resolve().parents[2] / "uploads"
    root.mkdir(parents=True, exist_ok=True)
    return root.resolve()


def _clean_name(name: str | None) -> str:
    base = os.path.basename((name or "").replace("\\", "/")).strip()
    base = re.sub(r"[\x00-\x1f]", "", base)
    return (base or "file")[:255]


def _looks_right(head: bytes, check: object) -> bool:
    if check == _TEXT:
        return b"\x00" not in head
    if check == "webp":
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    if check == "ftyp":
        return head[4:8] == b"ftyp"
    return any(head.startswith(sig) for sig in check)  # type: ignore[union-attr]


def save(stream: BinaryIO, original_name: str | None, company_id: int, module: str) -> Stored:
    """Writes the upload under the company's folder and returns what to record. Raises 422 for an
    unknown or disguised type and 413 when it is too large."""
    if not _MODULE.match(module or ""):
        raise AppError(422, "VALIDATION_FAILED", "module is not valid.", {"module": "Not a module name."})
    name = _clean_name(original_name)
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext not in TYPES:
        raise AppError(422, "FILE_TYPE_NOT_ALLOWED", f"Files of type .{ext or '?'} cannot be uploaded.",
                       {"file": "This file type is not allowed."})
    mime, check = TYPES[ext]
    limit = settings.max_upload_mb * 1024 * 1024
    now = datetime.now(UTC)
    rel = Path(str(company_id), module, f"{now:%Y}", f"{now:%m}", f"{uuid.uuid4().hex}.{ext}")
    final = upload_root() / rel
    final.parent.mkdir(parents=True, exist_ok=True)
    temp = final.with_suffix(final.suffix + ".part")
    digest, size, head = hashlib.sha256(), 0, b""
    try:
        with open(temp, "wb") as out:
            while chunk := stream.read(CHUNK):
                if len(head) < 64:
                    head += chunk[: 64 - len(head)]
                size += len(chunk)
                if size > limit:
                    raise AppError(413, "FILE_TOO_LARGE", f"Files may be at most {settings.max_upload_mb} MB.",
                                   {"file": "Too large."})
                digest.update(chunk)
                out.write(chunk)
        if size == 0:
            raise AppError(422, "FILE_EMPTY", "The file is empty.", {"file": "Empty file."})
        if not _looks_right(head, check):
            raise AppError(422, "FILE_TYPE_MISMATCH", f"This file is not really a .{ext} file.",
                           {"file": "The content does not match the file type."})
        os.replace(temp, final)
    except BaseException:
        temp.unlink(missing_ok=True)
        raise
    return Stored(name=name, extension=ext, mime_type=mime, size_bytes=size, sha256=digest.hexdigest(),
                  storage_path=rel.as_posix())


def path_of(storage_path: str) -> Path:
    root = upload_root()
    full = (root / storage_path).resolve()
    if root not in full.parents:
        raise AppError(404, "NOT_FOUND", "File not found.")
    return full


def remove(storage_path: str) -> None:
    try:
        path_of(storage_path).unlink(missing_ok=True)
    except AppError:
        pass


def _key() -> str:
    return settings.jwt_secret + ":files"


def file_url(file_id: int | str | None, company_id: int) -> str | None:
    """A signed, short-lived download link for a file of this company (None for no file)."""
    if file_id in (None, ""):
        return None
    exp = datetime.now(UTC) + timedelta(minutes=settings.file_link_minutes)
    token = jwt.encode({"fid": str(file_id), "cid": str(company_id), "exp": exp}, _key(), algorithm="HS256")
    return f"{settings.public_base_url.rstrip('/')}/api/files/{file_id}/download?token={token}"


def read_file_token(token: str, file_id: int) -> int | None:
    """The company the token was issued for, or None when it is invalid, expired or for another file."""
    try:
        claims = jwt.decode(token, _key(), algorithms=["HS256"], options={"require": ["exp", "fid", "cid"]})
    except jwt.PyJWTError:
        return None
    if claims.get("fid") != str(file_id):
        return None
    return int(claims["cid"])
