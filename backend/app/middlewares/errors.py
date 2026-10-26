"""Every error leaves the API in the shape the frontend reads (src/types/api.ts, ApiErrorBody):
{"message": "...", "code": "...", "fieldErrors": {"field": "message"}}."""
import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.errors import AppError

log = logging.getLogger("hrango")


def _body(message: str, code: str, field_errors: dict[str, str] | None = None) -> dict:
    body = {"message": message, "code": code}
    if field_errors:
        body["fieldErrors"] = field_errors
    return body


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(_body(exc.message, exc.code, exc.field_errors), status_code=exc.status)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        fields: dict[str, str] = {}
        for e in exc.errors():
            loc = [str(p) for p in e["loc"][1:]] if e["loc"] and e["loc"][0] in ("body", "query", "path") else [
                str(p) for p in e["loc"]]
            fields.setdefault(".".join(loc) or "request", e["msg"])
        return JSONResponse(_body("Some fields need your attention.", "VALIDATION_FAILED", fields), status_code=422)

    @app.exception_handler(StarletteHTTPException)
    async def http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = {404: "NOT_FOUND", 405: "METHOD_NOT_ALLOWED"}.get(exc.status_code, "HTTP_ERROR")
        return JSONResponse(_body(str(exc.detail), code), status_code=exc.status_code)

    @app.exception_handler(Exception)
    async def unexpected(request: Request, exc: Exception) -> JSONResponse:
        log.exception("unhandled error on %s %s [%s]", request.method, request.url.path,
                      getattr(request.state, "request_id", "-"))
        return JSONResponse(_body("Something went wrong on our side. Please try again.", "SERVER_ERROR"),
                            status_code=500)
