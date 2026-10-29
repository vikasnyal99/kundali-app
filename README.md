# KundliMilan AI

Bilingual (English/Hindi) Vedic Kundli matching app: saved birth profiles, pair matching, fixed-Person-1
multi-candidate comparison, and private PDF reports. Flutter (Android first, iOS-ready) + FastAPI +
PostgreSQL + a single PostgreSQL-backed worker (**no Redis/Celery**) + private S3-compatible storage.

> **Status: trial prototype, not production-ready.** Calculation is disabled by default. The optional local
> engine is experimental (AGPL licence, rules not domain-validated, known upstream deviations); see
> [docs/ENGINE_RESEARCH.md](docs/ENGINE_RESEARCH.md). No score is ever invented: without an engine the app
> says "not available". Current status and open decisions are tracked in [summary.md](summary.md).

## Layout

| Path | Contents |
|---|---|
| `server/` | FastAPI app (`app/`), worker, Alembic migrations, tests, place-index builder (`scripts/`) |
| `mobile/` | Flutter app, `lib/l10n/app_{en,hi}.arb`, widget tests |
| `infra/` | `Dockerfile`, `compose.yml` (production: API + 1 worker, external DB/S3), `compose.dev.yml` (local PostgreSQL + MinIO) |
| `docs/` | Product requirements (`PRD.md`, `USER_FLOWS.md`, `SCREEN_SPEC.md`, `BUILD_PLAN.md`), `DEPLOYMENT.md`, `ENGINE_RESEARCH.md`, original handoff in `docs/handoff/` |
| `architecture/`, `design/`, `prompts/` | Original handoff architecture, design system and start prompt |

## Local setup

Prerequisites: Python 3.12, Docker (for PostgreSQL/MinIO), Flutter stable (3.47+ tested). Run commands from the repo root unless noted.

### 1. Backend dependencies

```bash
python3 -m venv .venv
.venv/bin/pip install -r server/requirements-dev.txt
# Optional, local evaluation only (AGPL; read docs/ENGINE_RESEARCH.md first):
.venv/bin/pip install -r server/requirements-engine.txt
cp .env.example .env        # never commit .env
```

PDF rendering needs Pango and a Devanagari font on the host (Debian/Ubuntu: `sudo apt install libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz-subset0 fonts-noto-core`).

### 2. Database and storage

```bash
docker compose -f infra/compose.dev.yml up -d postgres       # 127.0.0.1:55432, disposable
```

In `.env`, set `DATABASE_URL=postgresql+psycopg://kundli:local-dev-only@127.0.0.1:55432/kundli`
(SQLite `sqlite:///./kundli.db` also works for quick UI work, but locking/migrations are only proven on PostgreSQL).

For reports you need S3-compatible storage. `docker compose -f infra/compose.dev.yml up -d minio` starts MinIO on
`127.0.0.1:59000` (image from quay.io; your Docker CLI may require `docker login quay.io` first). Then set
`S3_ENDPOINT_URL=http://127.0.0.1:59000`, `S3_BUCKET=kundli-reports`, `S3_REGION=us-east-1`,
`AWS_ACCESS_KEY_ID=devminio`, `AWS_SECRET_ACCESS_KEY=devminio-password-change`, and create the bucket once:

```bash
.venv/bin/python -c "import boto3;boto3.client('s3',endpoint_url='http://127.0.0.1:59000',region_name='us-east-1',aws_access_key_id='devminio',aws_secret_access_key='devminio-password-change').create_bucket(Bucket='kundli-reports')"
```

Without storage, reports fail visibly with `storage_not_configured`; everything else works.

### 3. Migrate, then run the API and the single worker (two terminals)

```bash
cd server
../.venv/bin/alembic upgrade head
../.venv/bin/uvicorn app.main:app --reload --port 8100      # terminal 1
../.venv/bin/python -m app.worker                          # terminal 2 (polls the jobs table)
curl -s localhost:8100/health/ready
```

Settings come from the repo-root `.env` (or `server/.env`); real environment variables override them. To try calculations locally, set
`ASTROLOGY_MODE=local_experimental` (requires the engine install above). Every result is then labelled experimental.

### 4. App: web screens + native shell

All screens are a Flutter **web** app (`mobile/lib/main.dart`) served by the API at `/`; the Android APK is only a
native splash and a WebView (`mobile/lib/shell.dart`). Screen changes therefore ship with a server deploy, no new APK.

```bash
cd mobile && flutter pub get
flutter build web --release -t lib/main.dart                 # → mobile/build/web
cd ../server && WEB_DIR=../mobile/build/web ASTROLOGY_MODE=local_experimental \
  ../.venv/bin/uvicorn app.main:app --port 8100              # open http://localhost:8100 (API under /v1)
# Shell APK (rarely rebuilt). Default APP_URL is https://kundaliapi.zivantaai.com/
cd ../mobile && flutter build apk --release --split-per-abi -t lib/shell.dart
flutter run -t lib/shell.dart --dart-define=APP_URL=http://10.0.2.2:8100/   # emulator → local server (debug allows HTTP)
```

The web app calls the API on the site that served it; `--dart-define=API_BASE_URL=...` overrides that. On first launch
the shell hands the old native app's guest session to the web app once (`handoff.html`), so saved people stay.

## Tests

```bash
cd server && ../.venv/bin/python -m pytest -q          # SQLite + unit tests; integration tests skip
# Integration against disposable services (the schema is DROPPED on each test):
TEST_POSTGRES_URL=postgresql+psycopg://kundli:local-dev-only@127.0.0.1:55432/kundli \
TEST_S3_ENDPOINT=http://127.0.0.1:59000 ../.venv/bin/python -m pytest -q
# Without MinIO, moto's S3 emulator works too (it cannot prove signed-URL expiry):
#   ../.venv/bin/pip install "moto[server]>=5,<6"; ../.venv/bin/moto_server -H 127.0.0.1 -p 59001
#   TEST_S3_EMULATOR=1 TEST_S3_ENDPOINT=http://127.0.0.1:59001 ... pytest
cd ../mobile && flutter analyze && flutter test
```

Never point `TEST_POSTGRES_URL` or `TEST_S3_ENDPOINT` at shared or production services.

## Place data

Birthplace suggestions come from an offline GeoNames index (`server/app/data/places.tsv.gz`, CC BY 4.0, attribution
shown in the app's Settings). No third-party geocoding request is made. Refresh with
`.venv/bin/python -I server/scripts/build_places.py /tmp/geonames`.

## Deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). Nothing has been deployed.
