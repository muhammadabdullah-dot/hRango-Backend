"""Outgoing HTTP to addresses that customers choose (webhooks), without letting them reach into the
hosting network (BE-03, server-side request forgery).

- Only http(s) URLs with a host name, and no user:password@ part.
- The host is resolved and every address must be public (ipaddress.is_global): no loopback, private
  (10/8, 172.16/12, 192.168/16, fc00::/7), link-local (169.254/16, where cloud metadata lives), shared
  carrier space, multicast or reserved ranges. Checked when the URL is saved, and again on every
  connection, which then goes to the exact address that was checked, so a DNS answer that changes
  between the check and the connection (rebinding) cannot slip through.
- Redirects are never followed: a 3xx is a failed delivery.
- Errors are reported in coarse words (timeout, refused, blocked address, TLS) and the receiver's reply
  body is not kept, so a delivery list cannot be used to read or map other systems.

settings.webhook_allow_private lets a developer send to a receiver on their own machine (and the tests use it).
"""
import http.client
import ipaddress
import socket
import ssl
import urllib.error
import urllib.parse
import urllib.request

from app.core.config import settings


class BlockedAddress(Exception):
    """The URL or the address it resolves to may not be called."""


def _allow_private() -> bool:
    return settings.webhook_allow_private


def _address_allowed(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    if _allow_private():
        return not ip.is_multicast and not ip.is_unspecified
    return ip.is_global and not ip.is_multicast


def check_url(url: str, require_https: bool = False) -> urllib.parse.SplitResult:
    """The parsed URL when it may be called; BlockedAddress with a reason a user can read otherwise."""
    try:
        parts = urllib.parse.urlsplit(url.strip())
        port = parts.port
    except ValueError as exc:
        raise BlockedAddress("The address is not a valid URL.") from exc
    if parts.scheme not in ("http", "https"):
        raise BlockedAddress("The address must start with http:// or https://.")
    if require_https and parts.scheme != "https":
        raise BlockedAddress("The address must start with https://.")
    if not parts.hostname:
        raise BlockedAddress("The address needs a host name.")
    if parts.username is not None or parts.password is not None:
        raise BlockedAddress("Put credentials in the receiver's settings, not in the address.")
    if port == 0:
        raise BlockedAddress("The address has no valid port.")
    resolve(parts.hostname, port or (443 if parts.scheme == "https" else 80))
    return parts


def resolve(host: str, port: int) -> list[str]:
    """Every address the host resolves to, all of them allowed; BlockedAddress otherwise."""
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except (socket.gaierror, UnicodeError) as exc:
        raise BlockedAddress("The host name could not be found.") from exc
    addresses = []
    for *_, sockaddr in infos:
        ip = ipaddress.ip_address(sockaddr[0].split("%", 1)[0])
        if not _address_allowed(ip):
            raise BlockedAddress("The address points to a private or internal network, which webhooks may not call.")
        addresses.append(str(ip))
    if not addresses:
        raise BlockedAddress("The host name could not be found.")
    return addresses


def _connect(host: str, port: int, timeout: float) -> socket.socket:
    last: OSError | None = None
    for address in resolve(host, port):
        try:
            return socket.create_connection((address, port), timeout=timeout)
        except OSError as exc:
            last = exc
    raise last or OSError("no address")


class _CheckedHTTPConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = _connect(self.host, self.port, self.timeout)


class _CheckedHTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        sock = _connect(self.host, self.port, self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)


class _CheckedHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(_CheckedHTTPConnection, req)


class _CheckedHTTPSHandler(urllib.request.HTTPSHandler):
    def __init__(self):
        super().__init__(context=ssl.create_default_context())

    def https_open(self, req):
        return self.do_open(_CheckedHTTPSConnection, req, context=self._context)


class _NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # urllib then raises HTTPError with the 3xx code


_opener = urllib.request.OpenerDirector()
for _handler in (_CheckedHTTPHandler(), _CheckedHTTPSHandler(), _NoRedirects(), urllib.request.HTTPErrorProcessor(),
                 urllib.request.HTTPDefaultErrorHandler(), urllib.request.UnknownHandler()):
    _opener.add_handler(_handler)


def post(url: str, body: bytes, headers: dict[str, str], timeout: float) -> tuple[int | None, str | None]:
    """POSTs and returns (status code, None) for any HTTP answer, or (None, a short error) when there was none."""
    try:
        check_url(url)
    except BlockedAddress as exc:
        return None, f"Blocked: {exc}"
    request = urllib.request.Request(url, data=body, method="POST", headers=headers)
    try:
        with _opener.open(request, timeout=timeout) as resp:
            resp.read(1024)  # let the receiver finish; the body is not kept
            return resp.status, None
    except urllib.error.HTTPError as exc:
        if 300 <= exc.code < 400:
            return exc.code, "Redirects are not followed. Use the final address."
        return exc.code, None
    except urllib.error.URLError as exc:
        return None, _reason(exc.reason)
    except Exception as exc:  # noqa: BLE001 - every failure becomes a delivery error
        return None, _reason(exc)


def _reason(exc: object) -> str:
    if isinstance(exc, BlockedAddress):
        return f"Blocked: {exc}"
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return "No answer within the time limit."
    if isinstance(exc, ssl.SSLError):
        return "The secure connection failed (certificate or TLS)."
    if isinstance(exc, ConnectionRefusedError):
        return "The receiver refused the connection."
    return "The receiver could not be reached."
