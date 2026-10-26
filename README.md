# hRango-Backend

The hRango API (FastAPI on SQL Server, procedural: every read and write is a stored procedure) and its
database design. The web app lives in its own repository (raza722/HRango).

| Folder | What it is |
|---|---|
| `backend/` | The API: routers, controllers, services, repos, schemas; `db/` (migrations, procedures, seeds); `scripts/` (seeder, nightly jobs, webhooks); tests. Start with `backend/README.md`. |
| `erd/` | The ERD source, one file per module (`erd/source/*.md`), and `build.py`, which generates the SQL baseline, `HRango - ERD.md` and `HRango - ERD.drawio`. |
| `comparison/` | Per module: the documents vs the frontend screens vs the ERD, and the decisions taken. |

Quick start (Windows, SQL Server, Python 3.14):

```
cd backend
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
copy .env.example .env        (set DB_URL and JWT_SECRET)
.venv\Scripts\python.exe -m scripts.seed --create --bootstrap --company "Your Company" --admin-email admin@example.com
run.bat
```
