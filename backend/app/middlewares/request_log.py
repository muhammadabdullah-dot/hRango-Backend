"""Gives every request an id (X-Request-Id, echoed back) and logs one line per request."""
import logging
import time
import uuid

from fastapi import Request

log = logging.getLogger("hrango")


async def request_log(request: Request, call_next):
    request_id = request.headers.get("X-Request-Id") or uuid.uuid4().hex[:12]
    request.state.request_id = request_id
    started = time.perf_counter()
    response = await call_next(request)
    ms = (time.perf_counter() - started) * 1000
    response.headers["X-Request-Id"] = request_id
    log.info("%s %s %s %.0fms [%s]", request.method, request.url.path, response.status_code, ms, request_id)
    return response
