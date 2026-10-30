"""Small helpers for the work part: dates relative to today, and uploading generated files."""
import struct
import sys
import zlib
from datetime import date, datetime, time, timedelta

from scripts.demo import Api
from scripts.demo_data import World


def day(w: World, n: int, workday: bool = True) -> date:
    """Today plus n days; a Saturday or Sunday moves back to the Friday before."""
    d = w.today + timedelta(days=n)
    if workday and d.weekday() >= 5:
        d -= timedelta(days=d.weekday() - 4)
    return d


def iso(d: date | None) -> str | None:
    return d.isoformat() if d else None


def at(d: date, hh: int, mm: int = 0) -> str:
    """A wall-clock moment on day d, as the API takes it."""
    return datetime.combine(d, time(hh, mm)).isoformat()


_ACTIVE: dict[int, list[str]] = {}


def active_people(w: World) -> list[str]:
    """Everyone still employed now: parts that ran before this one may have separated someone."""
    if id(w) not in _ACTIVE:
        rows = w.admin.all("/employees")
        _ACTIVE[id(w)] = [e["name"] for e in rows if e.get("status") not in ("left", "inactive") and e["name"] in w.employees]
    return _ACTIVE[id(w)]


def upload(api: Api, name: str, content: bytes, mime: str, module: str) -> dict:
    """POST /files (multipart) as this person; returns the FileOut."""
    r = api.client.post("/api/files", files={"file": (name, content, mime)}, data={"module": module},
                        headers=api.headers)
    if r.status_code != 201:
        sys.exit(f"POST /files {name} -> {r.status_code}: {r.text}")
    return r.json()["data"]


def pdf(title: str, lines: list[str]) -> bytes:
    """A one-page A4 PDF with a title and some lines of text (Helvetica)."""
    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("latin-1", "replace").decode("latin-1")

    ops = ["BT", "/F1 20 Tf", "60 780 Td", f"({esc(title)}) Tj", "/F1 11 Tf", "0 -34 Td"]
    for line in lines:
        ops += [f"({esc(line)}) Tj", "0 -18 Td"]
    ops.append("ET")
    stream = "\n".join(ops).encode("latin-1", "replace")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def png(width: int, height: int, top: tuple[int, int, int], bottom: tuple[int, int, int],
        boxes: list[tuple[int, int, int, int, tuple[int, int, int]]] = ()) -> bytes:
    """A PNG with a vertical gradient and some filled rectangles (x, y, w, h, colour): a wireframe look."""
    rows = []
    for y in range(height):
        t = y / max(height - 1, 1)
        base = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        row = [base] * width
        for bx, by, bw, bh, colour in boxes:
            if by <= y < by + bh:
                row[bx:bx + bw] = [colour] * min(bw, width - bx)
        rows.append(b"\x00" + b"".join(bytes(px) for px in row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", raw) + chunk(b"IEND", b""))
