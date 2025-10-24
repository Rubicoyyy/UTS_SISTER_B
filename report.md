# UTS Aggregator — Report

Tanggal: 24 Oktober 2025

Versi: 1.0

Ringkasan singkat
-----------------
Laporan ini menjelaskan desain dan implementasi UTS Aggregator, layanan pengumpul event berbasis Python (FastAPI) dengan deduplikasi lokal (SQLite) dan consumer asynchronous. Tujuan utama: menjamin idempotency (satu event diproses sekali), durability terhadap restart (dedup state persist), serta kemampuan menahan duplicate deliveries (simulasi at-least-once delivery).

Bab 1 — Latar Belakang & Tujuan
--------------------------------
Modern microservice sering menerima event dari banyak publisher, termasuk pengiriman ulang (retries) yang menyebabkan duplicate deliveries. Aggregator ini dibuat untuk:

- Menyediakan endpoint ingestion (HTTP POST) yang menerima single atau batch event.
- Mencegah pemrosesan ganda berdasarkan (topic, event_id) (deduplication & idempotency).
- Menyimpan dedup state lokal yang tahan terhadap restart (SQLite).
- Memberikan statistik dasar dan daftar event yang sudah diproses.

Bab 2 — Spesifikasi Event & API
--------------------------------
Event JSON minimal:

{
  "topic": "string",
  "event_id": "string-unik",
  "timestamp": "ISO8601",
  "source": "string",
  "payload": { ... }
}

API:
- POST /publish — menerima single object atau array. Memvalidasi schema menggunakan Pydantic.
- GET /events?topic=... — mengembalikan daftar event unik yang telah diproses.
- GET /stats — mengembalikan counters: received, unique_processed, duplicate_dropped, topics, uptime_seconds.

Bab 3 — Desain Sistem
---------------------
Arsitektur tingkat tinggi:

- FastAPI HTTP server — menerima request POST /publish.
- In-memory queue (asyncio.Queue) — menyimpan event sebelum diproses.
- Consumer asinkron — loop yang membaca queue dan melakukan operation dedup + pemrosesan.
- DedupStore (SQLite) — tabel events dengan PRIMARY KEY (topic, event_id). Insert yang gagal karena PK duplicate menandakan duplicate.

Alasan desain:
- SQLite dipilih karena sederhana, local-only, dan persisten ke filesystem — memenuhi syarat "tahan restart" tanpa layanan eksternal.
- In-memory queue sederhana cukup untuk skenario pengujian; untuk produksi dengan ordering/throughput strict, gunakan broker (Kafka, RabbitMQ) dan per-partition ordering.

Bab 4 — Idempotency & Deduplication
-----------------------------------
Implementasi:

- Saat consumer memproses sebuah event, ia mencoba melakukan INSERT ke tabel `events` (topic,event_id,timestamp,source,payload). Jika insert sukses, event dianggap new dan diproses. Jika terjadi sqlite3.IntegrityError (duplicate PK), maka event dianggap duplikat dan tidak diproses ulang.
- Semua duplicate dicatat di log.

Persistensi:
- Database SQLite disimpan di `./data/dedup.db` (di dalam container jika dijalankan di Docker). Dengan volume Docker yang tepat, file ini bertahan antar restart container sehingga dedup tetap berlaku.

Bab 5 — Reliability, Ordering & Crash Tolerance
------------------------------------------------
Reliability:
- At-least-once delivery di-simulasikan oleh publisher (dapat mengirim event yang sama berkali-kali). Karena dedup, processing bersifat idempotent.
- Consumer sederhana: jika consumer crash saat memproses sebelum insert commit, event belum tercatat dan dapat diproses ulang (menjamin at-least-once). Untuk exactly-once memerlukan sink yang mendukung transactional processing end-to-end.

Ordering:
- Saat ini, aggregator tidak menjamin total ordering. Event diproses oleh satu consumer yang membaca dari satu in-memory FIFO queue; karena publisher dapat mem-batch atau mengirim paralel, urutan relatif dapat tidak konsisten antar waktu.
- Apakah total ordering dibutuhkan? Itu bergantung use-case:
  - Jika aplikasi downstream membutuhkan ordering per-topic, perlu implementasi per-topic queueing/partitioning dan pemrosesan sekuensial per partition.
  - Jika hanya dedup diperlukan tanpa ordering ketat, desain sekarang cukup.

Bab 6 — Pengujian & Hasil
-------------------------
Unit tests (pytest) yang disertakan:

1. test_dedup_basic — verifikasi dedup insert & duplicate detection.
2. test_persistence — simulasikan restart dengan membuka kembali DedupStore; memastikan duplikat masih terdeteksi.
3. test_schema_and_stats — publish via HTTP dan cek /events dan /stats konsisten.
4. test_small_stress — masukkan 1000 record ke store (dengan banyak duplikasi) dan pastikan selesai dalam batas waktu wajar (<5s pada dev machine saya).
5. test_batch_publish_and_stats — publish batch 200 events dengan ~20% duplikasi, cek stats konsisten.

Hasil:
- Semua 5 tests lulus pada mesin pengembang (Windows, Python 3.11). Test run: 5 passed, beberapa Pydantic deprecation warnings (ev.dict() — dapat diupgrade ke model_dump()).

Stress & performance:
- Untuk skala >=5000 events (permintaan tugas), terdapat script `scripts/publisher.py` yang dapat mengirim 5000 events dengan duplicate ratio 0.2 ke endpoint aggregator (via docker-compose atau lokal). Ini alat untuk mengukur responsivitas. Saya menyiapkan `docker-compose.yml` agar menjalankan aggregator + publisher demo; Anda dapat menjalankan `docker-compose up --build` untuk simulasi.

Bab 7 — Deployment, Operasi & Instruksi
--------------------------------------
Cara build image Docker:

```
docker build -t uts-aggregator .
```

Run container:

```
docker run -p 8080:8080 uts-aggregator
```

Docker Compose (demo load-generator):

```
docker-compose up --build
```

Run lokal tanpa Docker (development):

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install --upgrade pip
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python -m uvicorn src.main:app --host 0.0.0.0 --port 8080
```

API examples:

Publish single via curl:

```powershell
curl -X POST http://localhost:8080/publish -H "Content-Type: application/json" -d "{\"topic\":\"t\",\"event_id\":\"e1\",\"timestamp\":\"2025-10-24T00:00:00Z\",\"source\":\"curl\",\"payload\":{}}"
```

GET events:

```
GET http://localhost:8080/events?topic=t
```

GET stats:

```
GET http://localhost:8080/stats
```

Analisis Keterbatasan & Rekomendasi Produksi
-------------------------------------------
- SQLite adalah solusi sederhana dan tepat untuk tugas ini (local-only persistence). Untuk beban produksi tinggi, gunakan WAL mode, tune PRAGMA settings, atau pertimbangkan server-side DB (Postgres) atau distributed log (Kafka) untuk durability dan throughput.
- Ordering: implementasikan per-topic partitions jika ordering per-topic diperlukan. Gunakan broker yang mendukung ordering semantics.
- Observability: tambahkan metrics (Prometheus), structured logging, serta tracing untuk troubleshooting.

Referensi
---------
- FastAPI docs — https://fastapi.tiangolo.com
- SQLite docs — https://sqlite.org/docs.html
- Pydantic (model migration notes) — https://errors.pydantic.dev/2.12/migration/

Lampiran: struktur file (ringkas)

- src/main.py — FastAPI app + consumer
- src/dedup.py — DedupStore (SQLite)
- scripts/publisher.py — Load generator for testing
- tests/test_aggregator.py — pytest suite (5 tests)
- Dockerfile, docker-compose.yml, requirements.txt, README.md

---
Jika Anda mau, saya bisa:

- Mengubah `ev.dict()` menjadi `ev.model_dump()` untuk menghilangkan Pydantic deprecation warnings (cepat).
- Menjalankan benchmark 5000 events sekarang dan melaporkan throughput/latency (saya akan gunakan docker-compose atau menjalankan uvicorn lokal + scripts/publisher.py). Perlu konfirmasi apakah Anda mau saya jalankan di mesin ini.
- Menghasilkan PDF dari `report.md` (butuh konversi lokal atau tool tambahan).

Selesai.
# Report

## Desain singkat

Aggregator dibangun sebagai HTTP ingestion (FastAPI) + in-memory queue (asyncio.Queue) + persistent dedup store (SQLite). Tujuan utama: idempotency lokal, tahan restart, dan kemampuan memproses duplicate deliveries.

Komponen:
- HTTP ingest (POST /publish)
- Consumer async membaca dari queue dan memanggil `DedupStore.record_event`.
- DedupStore: SQLite dengan PK (topic,event_id) untuk atomic dedup.

## Idempotency & Durability

- Karena dedup state disimpan di SQLite, setelah restart service tidak akan memproses event yang sama lagi (jika file DB tetap ada).
- Logging mencatat duplicate detection.

## Ordering

Saat ini aggregator tidak menjamin total ordering. Hanya FIFO pada single queue — namun concurrency internal atau batch producer tidak membuat ordering per-topic terjamin.

Pertimbangan:
- Jika aplikasi memerlukan ordering per-topic, rekomendasi: implement per-topic partition/queue dan proses sekuensial per-partition.
- Ganti in-memory queue dengan persistent queue (mis. Kafka/Rabbit) kalau butuh durability/ordering tinggi di production.

## Reliability

- At-least-once delivery: dipenuhi dari sisi publisher (yang dapat mengirim ulang). Dedup memastikan hanya satu pemrosesan untuk identitas event.

## Performance

- Test dasar (unit test stress kecil) menunjukkan operasi SQLite insert dengan banyak duplikasi menyelesaikan 1000 inserts dalam waktu singkat. Untuk beban 5000+ events disarankan menguji menggunakan `scripts/publisher.py` dan docker-compose untuk mensimulasikan traffic.

## Tests

- Tests: 5 tests (dedup basic, persistence, schema+stats, small stress, batch publish+stats). Semua lulus pada mesin developer.

## Instruksi run singkat

Build image:

```
docker build -t uts-aggregator .
```

Run container:

```
docker run -p 8080:8080 uts-aggregator
```

Docker Compose demo load:

```
docker-compose up --build
```

## Catatan & Next steps

- Migrasi ke persistent broker untuk ordering/throughput lebih baik.
- Tambahkan metrics dan observability.

