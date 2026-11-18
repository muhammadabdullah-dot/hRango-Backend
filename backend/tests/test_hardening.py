"""Startup secrets (BE-01), production CORS and docs (0.2, BE-12), body size limit (BE-10), security
headers and the request id (BE-12)."""
import jwt
import pytest
from fastapi.testclient import TestClient

from app.core import files
from app.core.config import Settings, check_startup, settings
from app.middlewares.body_limit import BodyLimit, max_body_bytes
from app.middlewares.request_log import request_id_of

GOOD = "x" * 40
OTHER = "y" * 40


def _settings(**values) -> Settings:
    base = {"jwt_secret": GOOD, "file_link_secret": OTHER, "app_env": "production", "cors_origins": "",
            "app_public_url": "https://app.example.com", "mail_enabled": False, "webhook_allow_private": False}
    return Settings(_env_file=None, **{**base, **values})


# ---------------------------------------------------------------- secrets and startup

@pytest.mark.parametrize("secret, words", [
    ("", "is not set"),
    ("   ", "is not set"),
    ("change-me", "example value"),
    ("CHANGE-ME", "example value"),
    ("secret", "example value"),
    ("short-but-random-1234", "too short"),
])
def test_weak_sign_in_secret_is_refused(secret, words):
    problems = _settings(jwt_secret=secret).startup_problems()
    assert any(p.startswith("JWT_SECRET") and words in p for p in problems), problems


def test_weak_file_link_secret_is_refused():
    problems = _settings(file_link_secret="change-me").startup_problems()
    assert any(p.startswith("FILE_LINK_SECRET") for p in problems), problems


def test_the_two_secrets_must_differ():
    assert "FILE_LINK_SECRET must be different from JWT_SECRET." in _settings(file_link_secret=GOOD).startup_problems()


def test_good_settings_start():
    assert _settings().startup_problems() == []
    check_startup(_settings())  # no exception


def test_check_startup_stops_with_every_problem_listed():
    with pytest.raises(SystemExit) as stopped:
        check_startup(_settings(jwt_secret="change-me", file_link_secret=""))
    message = str(stopped.value)
    assert "JWT_SECRET" in message and "FILE_LINK_SECRET" in message and "secrets.token_urlsafe" in message


def test_open_cors_only_in_development():
    assert any("CORS_ORIGINS" in p for p in _settings(cors_origins="*").startup_problems())
    assert any("CORS_ORIGINS" in p for p in _settings(cors_origins="https://app.example.com, *").startup_problems())
    assert _settings(cors_origins="*", app_env="development").startup_problems() == []
    assert _settings(cors_origins="https://app.example.com").startup_problems() == []


def test_production_is_the_default_environment():
    # A server whose .env forgets APP_ENV gets the strict rules (the tests themselves set development).
    assert Settings.model_fields["app_env"].default == "production"
    assert Settings.model_fields["cors_origins"].default == ""


def test_docs_follow_the_environment_unless_set():
    assert _settings().docs_enabled is False
    assert _settings(app_env="development").docs_enabled is True
    assert _settings(api_docs=True).docs_enabled is True
    assert _settings(app_env="development", api_docs=False).docs_enabled is False


# ---------------------------------------------------------------- file links use their own secret

def test_file_links_are_signed_with_their_own_secret():
    url = files.file_url(7, 3)
    token = url.split("token=", 1)[1]
    assert files.read_file_token(token, 7) == 3
    assert files.read_file_token(token, 8) is None


def test_a_link_signed_the_old_way_no_longer_works():
    """Before BE-01 the link key was JWT_SECRET + ':files'; such a token must now be refused."""
    old = jwt.encode({"fid": "7", "cid": "3", "exp": 4102444800}, settings.jwt_secret + ":files", algorithm="HS256")
    assert files.read_file_token(old, 7) is None
    forged_with_sign_in_secret = jwt.encode({"fid": "7", "cid": "3", "exp": 4102444800}, settings.jwt_secret,
                                            algorithm="HS256")
    assert files.read_file_token(forged_with_sign_in_secret, 7) is None


# ---------------------------------------------------------------- body size limit

def _echo_app(limit: int) -> TestClient:
    """A bare ASGI app that reads the whole body. (A Starlette app would turn the cut-off into its own 500 before
    the limit could answer; in the API the limit is the outermost layer, see the test below.)"""
    async def echo(scope, receive, send):
        size, more = 0, True
        while more:
            message = await receive()
            size += len(message.get("body", b""))
            more = message.get("more_body", False)
        body = f'{{"size": {size}}}'.encode()
        await send({"type": "http.response.start", "status": 200, "headers": [(b"content-type", b"application/json")]})
        await send({"type": "http.response.body", "body": body})

    return TestClient(BodyLimit(echo, max_bytes=limit))


def test_body_within_the_limit_passes():
    r = _echo_app(100).post("/echo", content=b"a" * 100)
    assert r.status_code == 200 and r.json() == {"size": 100}


def test_declared_oversized_body_is_refused_before_reading():
    r = _echo_app(100).post("/echo", content=b"a" * 101)
    assert r.status_code == 413
    assert r.json()["code"] == "PAYLOAD_TOO_LARGE"


def test_chunked_body_without_length_is_cut_off():
    def chunks():
        for _ in range(20):
            yield b"a" * 10

    r = _echo_app(100).post("/echo", content=chunks())
    assert r.status_code == 413


def test_body_limit_is_the_outermost_layer():
    from app.main import app

    assert app.user_middleware[0].cls is BodyLimit


def test_api_refuses_a_body_over_the_upload_limit(client):
    r = client.post("/api/files", content=b"0", headers={"Content-Length": str(max_body_bytes() + 1)})
    assert r.status_code == 413
    assert r.json()["code"] == "PAYLOAD_TOO_LARGE"


def test_api_cuts_off_an_oversized_chunked_upload(client, admin):
    """A signed-in upload sent without a length (chunked) is cut off as it streams in."""
    chunk = b"a" * (1024 * 1024)

    def chunks():
        yield (b'--cut\r\nContent-Disposition: form-data; name="file"; filename="big.pdf"\r\n'
               b"Content-Type: application/pdf\r\n\r\n")
        for _ in range(max_body_bytes() // len(chunk) + 2):
            yield chunk
        yield b"\r\n--cut--\r\n"

    r = client.post("/api/files", params={"module": "employees"}, content=chunks(),
                    headers={**admin["headers"], "Content-Type": "multipart/form-data; boundary=cut"})
    assert r.status_code == 413
    assert r.json()["code"] == "PAYLOAD_TOO_LARGE"


# ---------------------------------------------------------------- headers and request id

def test_api_responses_carry_security_headers(client):
    r = client.get("/api/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["referrer-policy"] == "no-referrer"
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["content-security-policy"] == "default-src 'none'; frame-ancestors 'none'"
    assert r.headers["cache-control"] == "no-store"


def test_error_responses_carry_security_headers_too(client):
    r = client.get("/api/no-such-route")
    assert r.status_code == 404
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["cache-control"] == "no-store"


def test_a_plain_request_id_is_kept(client):
    assert client.get("/api/health", headers={"X-Request-Id": "abc-123_x.y"}).headers["x-request-id"] == "abc-123_x.y"


@pytest.mark.parametrize("header", ["a b", "x" * 65, "<script>", "id\r\nforged: line", ""])
def test_an_unsafe_request_id_is_replaced(header):
    replaced = request_id_of(header)
    assert replaced != header and len(replaced) == 12 and replaced.isalnum()
