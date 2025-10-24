# UTS Aggregator

Simple event aggregator implemented with FastAPI and SQLite-based dedup store.

Build: docker build -t uts-aggregator .
Run: docker run -p 8080:8080 uts-aggregator

Endpoints:
- POST /publish  (batch or single) - publish events (not implemented in runtime placeholder)
- GET /events?topic=... - list processed events
- GET /stats - basic counters and uptime

Quick start (local):

1) Create venv and install deps:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install --upgrade pip
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python -m uvicorn src.main:app --host 0.0.0.0 --port 8080
```

Activate virtualenv (PowerShell)

If Activate.ps1 is blocked by PowerShell's execution policy, use a per-session (temporary) bypass — this does NOT change system settings:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& .\.venv\Scripts\Activate.ps1
```

Single-line child PowerShell alternative (runs one child process with bypass):

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -Command "& '.\\.venv\\Scripts\\Activate.ps1'"
```

There is also a small helper script included in this repository to make activation easier from the project root:

```powershell
# From project root
powershell -ExecutionPolicy Bypass -File tools\activate_venv.ps1
# or (if your policy already permits running the helper)
& .\tools\activate_venv.ps1
```

Persistent change (only if you understand the security tradeoffs):

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Notes:
- The per-process options are the safest for development: they don't modify user or machine policy.
- `RemoteSigned` allows local scripts but requires downloaded scripts to be signed.
- If you are on a managed machine (corporate), check with your admin before changing policies.

2) Publish example (single):

```powershell
curl -X POST http://localhost:8080/publish -H "Content-Type: application/json" -d "{\"topic\":\"t\",\"event_id\":\"e1\",\"timestamp\":\"2025-10-24T00:00:00Z\",\"source\":\"curl\",\"payload\":{}}"
```

Docker:

Build: `docker build -t uts-aggregator .`
Run: `docker run -p 8080:8080 uts-aggregator`

Docker Compose (run aggregator + publisher load generator):

```powershell
docker-compose up --build
```

Assumptions:
- Dedup store is local-only SQLite file at `./data/dedup.db` inside container. Mount a volume if you want persistence across container recreation.
- Ordering is not guaranteed across topics. If strict ordering is required, modify to per-topic queues and sequential processing per topic.

Benchmark helper:

There is a PowerShell helper to automate kill->start->publish->collect stats:

```powershell
cd C:\UTS_Sister
powershell -File tools\run_benchmark.ps1 -Count 5000 -DupRatio 0.2 -BatchSize 200
```

The script will print elapsed seconds and the /stats JSON after running the publisher.

