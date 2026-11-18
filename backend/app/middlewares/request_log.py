"""Gives every request an id (X-Request-Id, echoed back) and logs one line per request.

A caller's own X-Request-Id is kept only when it is a plain token (letters, digits, '.', '_', '-', at most
64), so it cannot forge log lines or carry markup into the log viewer (BE-12)."""
import logging
import re
import time
import uuid

from fastapi import Request

log = logging.getLogger("hrango")

_SAFE_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")


def request_id_of(header: str | None) -> str:
    return header if header and _SAFE_ID.fullmatch(header) else uuid.uuid4().hex[:12]


async def request_log(request: Request, call_next):
    request_id = request_id_of(request.headers.get("X-Request-Id"))
    request.state.request_id = request_id
    started = time.perf_counter()
    response = await call_next(request)
    ms = (time.perf_counter() - started) * 1000
    response.headers["X-Request-Id"] = request_id
    log.info("%s %s %s %.0fms [%s]", request.method, request.url.path, response.status_code, ms, request_id)
    return response
