"""Uploads: stored under the company's folder by type check, read back through signed links only."""
from pathlib import Path

from app.core import files
from tests import factories


def test_upload_download_delete(client, db, company, admin):
    h = admin["headers"]
    f = factories.upload(client, h, name="..\\..\\Offer Letter.pdf", module="requests")
    assert f["name"] == "Offer Letter.pdf" and f["extension"] == "pdf" and f["mimeType"] == "application/pdf"
    assert f["sizeBytes"] == len(factories.PDF_BYTES) and f["module"] == "requests"

    row = db.call_one("core.usp_file_get", company_id=company, id=int(f["id"]))
    assert row["storage_path"].startswith(f"{company}/requests/") and row["storage_path"].endswith(".pdf")
    assert Path(files.upload_root(), row["storage_path"]).read_bytes() == factories.PDF_BYTES
    assert len(row["sha256"]) == 64

    # The signed link works without the Authorization header.
    got = client.get(f["url"])
    assert got.status_code == 200 and got.content == factories.PDF_BYTES
    assert "attachment" in got.headers["content-disposition"] and "Offer%20Letter.pdf" in got.headers["content-disposition"]
    assert "inline" in client.get(f["url"] + "&inline=true").headers["content-disposition"]
    assert client.get(f"/api/files/{f['id']}/download", params={"token": "forged"}).status_code == 403
    other = factories.upload(client, h)
    assert client.get(f"/api/files/{other['id']}/download", params={"token": f["url"].split("token=")[1]}).status_code == 403

    assert client.get(f"/api/files/{f['id']}", headers=h).status_code == 200
    stranger = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    assert client.get(f"/api/files/{f['id']}", headers=stranger["headers"]).status_code == 404
    assert client.delete(f"/api/files/{f['id']}", headers=stranger["headers"]).status_code == 403

    assert client.delete(f"/api/files/{f['id']}", headers=h).status_code == 204
    assert not Path(files.upload_root(), row["storage_path"]).exists()
    assert client.get(f["url"]).status_code == 404


def test_rejected_uploads(client, admin):
    h = admin["headers"]

    def up(name: str, content: bytes, module: str = "core"):
        return client.post("/api/files", files={"file": (name, content)}, data={"module": module}, headers=h)

    assert up("run.exe", b"MZ\x90\x00").json()["code"] == "FILE_TYPE_NOT_ALLOWED"
    assert up("photo.png", b"MZ not a png").json()["code"] == "FILE_TYPE_MISMATCH"
    assert up("notes.txt", b"").json()["code"] == "FILE_EMPTY"
    assert up("notes.txt", b"plain text", module="../etc").status_code == 422
    assert up("notes.txt", b"plain text", module="nonsense").status_code == 422
    assert up("picture.PNG", factories.PNG_BYTES).status_code == 201
    assert client.post("/api/files", files={"file": ("a.pdf", factories.PDF_BYTES)}).status_code == 401


def test_file_in_use_cannot_be_deleted(client, db, company, admin):
    f = factories.upload(client, admin["headers"])
    cur = db.conn.cursor()
    cur.execute("INSERT core.attachment (company_id, entity_type, entity_id, file_id) VALUES (?, N'test.thing', 1, ?)",
                company, int(f["id"]))
    cur.close()
    r = client.delete(f"/api/files/{f['id']}", headers=admin["headers"])
    assert r.status_code == 409 and r.json()["code"] == "FILE_IN_USE"


def test_other_company_cannot_use_a_file(client, db, admin, company):
    f = factories.upload(client, admin["headers"])
    other = factories.company(db)
    assert db.call("core.usp_file_get", company_id=other, id=int(f["id"])) == []
    cur = db.conn.cursor()
    usable = cur.execute("SELECT COUNT(*) FROM core.fn_file_usable(?, ?)", other, int(f["id"])).fetchval()
    cur.close()
    assert usable == 0


def test_unused_uploads_are_purged(client, db, company, admin):
    """Old uploads no record uses are removed; ones a record points at stay."""
    from app.core import files as store

    unused = factories.upload(client, admin["headers"])
    used = factories.upload(client, admin["headers"])
    cur = db.conn.cursor()
    cur.execute("INSERT core.attachment (company_id, entity_type, entity_id, file_id) VALUES (?, N'test.thing', 2, ?)",
                company, int(used["id"]))
    cur.execute("UPDATE core.stored_file SET created_at = DATEADD(DAY, -10, created_at) WHERE id IN (?, ?)",
                int(unused["id"]), int(used["id"]))
    paths = [r[0] for r in cur.execute("EXEC core.usp_file_purge_unused @company_id = ?", company).fetchall()]
    cur.close()
    for p in paths:
        store.remove(p)
    assert db.call("core.usp_file_get", company_id=company, id=int(unused["id"])) == []
    assert db.call("core.usp_file_get", company_id=company, id=int(used["id"])) != []


def test_links_use_the_public_address_when_set(monkeypatch):
    """The frontend may be served from another address: the link then has to name this API."""
    from app.core.config import settings
    from app.core.files import file_url

    assert file_url(5, 1).startswith("/api/files/5/download?token=")
    monkeypatch.setattr(settings, "public_base_url", "http://172.16.1.67:8000/")
    assert file_url(5, 1).startswith("http://172.16.1.67:8000/api/files/5/download?token=")
