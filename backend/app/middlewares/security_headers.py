"""Security headers on every API response (BE-12). The web server in front can add more; these are the ones
the API itself can vouch for.

- The API returns data, never pages, so its responses may not be framed, sniffed or run as a document.
- Answers carry salaries and identity numbers: no shared caches, and no copy kept by the browser unless
  the route set its own Cache-Control (file downloads keep theirs, which is private).
- HSTS in production only, so a developer's plain-http API on a LAN is not pinned to https.
- The interactive docs load their own scripts and styles, so they get no Content-Security-Policy.
"""
from app.core.config import settings

_DOC_PATHS = ("/docs", "/redoc", "/openapi.json")


class SecurityHeaders:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        is_docs = scope.get("path", "").startswith(_DOC_PATHS)

        async def with_headers(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers") or [])
                present = {name.lower() for name, _ in headers}

                def add(name: bytes, value: bytes) -> None:
                    if name not in present:
                        headers.append((name, value))

                add(b"x-content-type-options", b"nosniff")
                add(b"referrer-policy", b"no-referrer")
                add(b"cache-control", b"no-store")
                if not is_docs:
                    add(b"x-frame-options", b"DENY")
                    add(b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'")
                if settings.is_production:
                    add(b"strict-transport-security", b"max-age=31536000; includeSubDomains")
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, with_headers)
