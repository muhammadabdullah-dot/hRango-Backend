"""ROWVERSION travels as 16 hex characters. Edits and deletes send back the one last read, so two
people cannot overwrite each other (the procedure answers 409 when it no longer matches)."""
from app.core.errors import AppError


def row_version_out(value: bytes | None) -> str | None:
    return value.hex() if value is not None else None


def row_version_in(text: str | None, required: bool = True) -> bytes | None:
    if not text:
        if required:
            raise AppError(422, "VALIDATION_FAILED", "rowVersion is required.", {"rowVersion": "Required."})
        return None
    try:
        value = bytes.fromhex(text)
    except ValueError:
        value = b""
    if len(value) != 8:
        raise AppError(422, "VALIDATION_FAILED", "rowVersion is not valid.", {"rowVersion": "Not valid."})
    return value
