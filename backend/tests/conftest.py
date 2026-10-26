"""Tests run against a real SQL Server database: the one DB_URL names (environment first, then
.env). It must be a *_dev or *_test database that the seeder has brought up to date:

    $env:DB_URL = "Driver={ODBC Driver 18 for SQL Server};Server=localhost;Database=hrango_mymodule_dev;Trusted_Connection=yes;TrustServerCertificate=yes"
    .venv\\Scripts\\python.exe -m scripts.seed --reset
    .venv\\Scripts\\python.exe -m pytest tests -q

Each test module makes its own records through tests/factories.py, with unique names, so tests
do not depend on each other or on what is already in the database.
"""
import os
import re
import tempfile

# Tests send webhooks themselves (webhook_dispatcher.dispatch_once); no background worker.
os.environ["WEBHOOK_WORKER"] = "false"
# Uploads from tests go to a throw-away folder, never the real uploads folder.
os.environ.setdefault("UPLOAD_DIR", tempfile.mkdtemp(prefix="hrango_test_uploads_"))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.db import Db, connect  # noqa: E402
from tests import factories  # noqa: E402


def pytest_configure(config):
    m = re.search(r"(?:Database|Initial Catalog)=([^;]+)", settings.db_url, re.I)
    name = m.group(1).strip().lower() if m else ""
    if not (name.endswith("_dev") or name.endswith("_test")):
        raise pytest.UsageError(f"Tests only run against a *_dev or *_test database, not {name or 'nothing'}.")


@pytest.fixture(scope="session")
def db():
    conn = connect()
    yield Db(conn)
    conn.close()


@pytest.fixture(scope="session")
def client():
    from app.main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def company(db) -> int:
    return factories.company(db)


@pytest.fixture(scope="session")
def admin(db, client, company) -> dict:
    """A Company Administrator in the test company: {"user_id", "token", "headers"}."""
    return factories.login_as(db, client, company, role_codes="company_admin")


def auth(token: str, company_id: int | None = None) -> dict:
    headers = {"Authorization": f"Bearer {token}"}
    if company_id is not None:
        headers["X-Company-Id"] = str(company_id)
    return headers
