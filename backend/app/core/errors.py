"""The one error type the layers raise. The error middleware turns it into the body the frontend
reads (src/types/api.ts, ApiErrorBody): {"message": "...", "code": "...", "fieldErrors": {...}}.

Codes are UPPER_SNAKE. fieldErrors keys are the form's field paths (camelCase), so the form can
show the message under the right input.
"""


class AppError(Exception):
    def __init__(self, status: int, code: str, message: str, field_errors: dict[str, str] | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.field_errors = field_errors or {}


def not_found(what: str) -> AppError:
    return AppError(404, "NOT_FOUND", f"{what} not found.")


def forbidden(message: str = "You do not have permission to do that.") -> AppError:
    return AppError(403, "FORBIDDEN", message)


def invalid(message: str, field: str | None = None) -> AppError:
    return AppError(422, "VALIDATION_FAILED", message, {field: message} if field else None)


def conflict(message: str, field: str | None = None, code: str = "CONFLICT") -> AppError:
    return AppError(409, code, message, {field: message} if field else None)


def unauthenticated(message: str = "Your session has expired. Please sign in again.") -> AppError:
    return AppError(401, "UNAUTHENTICATED", message)
