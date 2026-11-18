"""Refuses request bodies over a size limit before they are read into memory or spooled to disk (BE-10).

Starlette parses a multipart upload completely before a route can look at its size, so without this a
client can stream gigabytes at the API. The limit is checked twice: against Content-Length up front, and
against the bytes actually received (chunked bodies send no length, or a false one).
"""
import json

from app.core.config import settings

# Room for the multipart framing and the other form fields around a file of the maximum size.
_MULTIPART_MARGIN = 1024 * 1024


def max_body_bytes() -> int:
    return settings.max_upload_mb * 1024 * 1024 + _MULTIPART_MARGIN


class _TooLarge(Exception):
    pass


class BodyLimit:
    """Pure ASGI middleware, so it sees the body as it arrives, chunk by chunk."""

    def __init__(self, app, max_bytes: int | None = None):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = self.max_bytes or max_body_bytes()
        declared = _content_length(scope)
        if declared is not None and declared > limit:
            await _refuse(send, limit)
            return

        received = 0
        started = False
        refused = False

        async def limited_receive():
            # Past the limit the 413 goes out at once and the app is told the client has gone, so it stops
            # reading. (Raising here would not work: FastAPI turns any error while parsing a form into a 400.)
            nonlocal received, refused
            if refused:
                return {"type": "http.disconnect"}
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    if not started:
                        await _refuse(send, limit)
                    refused = True
                    return {"type": "http.disconnect"}
            return message

        async def tracking_send(message):
            nonlocal started
            if refused:
                return  # the 413 has been sent; whatever the app answers after the disconnect is dropped
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except _TooLarge:  # pragma: no cover - kept for apps that raise instead of reading on
            if not started and not refused:
                await _refuse(send, limit)
        except Exception:
            if not refused:
                raise


def _content_length(scope) -> int | None:
    for name, value in scope.get("headers") or ():
        if name == b"content-length":
            try:
                return int(value)
            except ValueError:
                return None
    return None


async def _refuse(send, limit: int) -> None:
    body = json.dumps({"message": f"The request is too large. The limit is {limit // (1024 * 1024)} MB.",
                       "code": "PAYLOAD_TOO_LARGE"}).encode()
    await send({"type": "http.response.start", "status": 413,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode()),
                            (b"connection", b"close")]})
    await send({"type": "http.response.body", "body": body})
