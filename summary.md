# KundliMilan AI — Project Status

**Updated:** 2026-10-28 (second session)  
**Workspace:** `/home/vikas/Desktop/kundali-app`  
**Nothing has been committed, published or deployed.**

## 1. Product and sources of truth

Bilingual (English/Hindi) Vedic Kundli matching app: saved birth profiles, pair matching, fixed-Person-1
multi-candidate comparison, private PDF reports. Low-traffic trial (<10 users/day), Android first, iOS-ready.

The original handoff is now at the repo root:
- `docs/PRD.md`, `docs/USER_FLOWS.md`, `docs/SCREEN_SPEC.md`, `docs/BUILD_PLAN.md`
- `design/DESIGN_SYSTEM.md`, `architecture/*`, `prompts/CODEX_START_PROMPT.md`
- The handoff's README, manifest and dev `infra/` files are kept unchanged in `docs/handoff/` for provenance, because its
  Redis compose and "no app" README are superseded.

Requirements that must stay true:
- Same screens in both languages.
- Guest use first.
- Deterministic engine-only scores, with "not available" instead of guesses.
- Person 1 stays fixed in comparisons, with consistent rules, stable sorting and visible ties/warnings.
- Private S3 with expiring signed downloads.
- Owner-scoped data with export/delete.
- Astrology is presented as a cultural framework, not scientific evidence.

## 2. Architecture (unchanged decisions)

- **Mobile:** Flutter.
- **Backend:** FastAPI, SQLAlchemy 2, Alembic.
- **Database:** PostgreSQL. SQLite only for quick local work.
- **Jobs:** one serial worker leasing rows from the PostgreSQL `jobs` table. **No Redis or Celery.**
- **Storage and PDFs:** WeasyPrint PDFs in a private S3-compatible bucket, downloaded through SigV4 presigned URLs.
- **Calculation:** disabled by default. There is an experimental `vedic-calc` adapter and a generic external-provider boundary.
- **Deployment:** Docker Compose (API plus exactly one worker) behind the server's existing HTTPS proxy, using the existing PostgreSQL/S3.

## 3. What this session verified and changed

### 3.1 Local engine (`server/app/local_engine.py`) — fixed, still experimental

- **Root cause:** `NakshatraInfo` and `PlanetPosition` are frozen Pydantic models. The adapter now uses `moon.nakshatra_info.nakshatra` / `.pada`
  instead of subscripting.
- **Time handling:** charts are built from the stored UTC instant with `timezone_offset=0`. Tests check this against a local-time chart and raw
  Swiss Ephemeris Lahiri output, including an IST date rollover.
- **Validation:** local output now passes the same `validate_facts` checks as provider output. It must have eight named rows, per-row
  maxima, total equal to the sum of rows, 36 possible, a pinned version/ruleset, string warnings and Manglik forced to `unavailable`.
- **New warning:** `moon_near_boundary_time_sensitive` is added when an approximate birth time puts the Moon within 0.65° of a nakshatra or sign boundary.
- **Upstream deviations found** (documented in `docs/ENGINE_RESEARCH.md`, pinned by a characterisation test):

  | Pair | Published table | Upstream |
  |---|---|---|
  | Mars/Saturn | 0.5 | 0 |
  | Venus/Moon | 0.5 | 3 |
  | Moon/Mercury (friend + enemy) | 1 | 3 |

  The yoni, gana, vashya, bhakoot/nadi exceptions and tara variants also need a reviewer's decision.
  **The engine must not be called accurate or enabled for production.**
- **Reference fixtures:** an empty slot for domain-reviewed cases exists at `server/tests/fixtures/ashtakoota_reference.json`. Its test skips until a reviewer fills it.

### 3.2 Backend fixes

- **Worker** (`worker.py`):
  - A job whose lease expired after the last attempt is now failed with `lease_expired`. Before, a crash mid-job, such as an OOM during PDF rendering, re-ran forever.
  - Limits are configurable.
  - Finished jobs record `finished_at` and are purged after `JOB_RETENTION_DAYS`.
  - Failure logs contain only IDs and reason codes.
- **API** (`main.py`):
  - Editing a person now invalidates only the comparisons that used that person. Before, all of the owner's comparisons were deleted.
  - Concurrent identical comparisons and duplicate report requests are race-safe (unique `(match_id, locale)`).
  - Comparison ties break deterministically by name, then id.
  - New sliding session renewal: `POST /v1/guest-sessions/refresh`.
  - New `GET /v1/places` endpoint.
  - The rate-limiter's memory use is now bounded.
- **Migration:** `migrations/versions/001_initial.py` is now explicit DDL instead of `metadata.create_all`. Alembic autogenerate finds **zero** differences from the
  models on PostgreSQL 16. `env.py` accepts an injected connection for tests.
- **Storage** (`services.py`):
  - The S3 client is pinned to **SigV4**. Tests showed boto3 producing legacy SigV2 URLs, which post-2014 regions such as `ap-south-1` reject.
  - The SSE header is configurable via `S3_SSE`.
- **PDF:** fully localized. Hindi koota names, translated warnings, birth details, time accuracy, a methodology table, the Manglik
  "unavailable" line and the disclaimer. Shaping was visually checked in the production image (Noto Sans Devanagari embedded and subset).
- **Config:**
  - Production now also refuses wildcard or non-HTTPS CORS.
  - Settings read the repo-root `.env` when run from `server/`.
  - Test fixtures pin behavior-relevant settings, so a developer's `.env` can't change test results.

### 3.3 Mobile (`mobile/`)

- The summary's claimed analyzer failure was already resolved: `flutter analyze` showed no errors, only 15 lint infos, which are now fixed.
- `Api` is now injectable (HTTP client and base URL). It tolerates non-JSON error pages and renews the guest session on every launch.
  If the token has expired, it starts a new session and tells the user that earlier data is unreachable.
- API error codes map to localized messages (`err_*` keys in both ARB files). Unknown codes show the generic message plus the code.
- Comparison results show rank, "Tied score", "Has warnings", and the "not available" text for unconfigured calculation.
- The person editor has a GeoNames place search that fills place, latitude, longitude and timezone, all still editable for confirmation.
  GeoNames attribution is shown in Settings.
- Android:
  - Added the `INTERNET` permission to the **main** manifest. Release builds previously could not reach the API.
  - Label set to "KundliMilan".
  - `allowBackup="false"`, which keeps secure storage working and keeps birth data out of cloud backups.
  - Cleartext HTTP is allowed only in debug builds.

### 3.4 MVP feature review (step 5)

| Feature | Decision |
|---|---|
| Place autocomplete/geocoding (P0) | **Implemented** offline. `server/app/data/places.tsv.gz` (34,191 GeoNames cities with IANA timezones and Hindi aliases, 866 KiB) is built by `server/scripts/build_places.py`. No third-party calls. Public Nominatim was rejected because its policy forbids autocomplete. |
| Account recovery/merge (P1 in PRD) | **Deferred.** Mitigations: sliding 90-day renewal, export, an explicit notice when a session is replaced. Needs an auth decision (email OTP, phone, Google/Apple) plus a merge design. |
| Validated Manglik | **Deferred.** Stays `unavailable` (enforced in `validate_facts`). Needs a chosen rule variant (lagna/moon/venus reference, houses, cancellations) and reviewed fixtures. |
| Optional AI explanations | **Deferred.** Deterministic templates are used everywhere. The provider was never confirmed. Planned design (from `architecture/ARCHITECTURE.md`): server-side key, facts-only prompt, JSON-schema output, rejection of any number not in the facts, cache by facts hash/prompt/locale, template fallback. |

### 3.5 Ops and docs

- **`infra/Dockerfile`:**
  - adds `libharfbuzz-subset0`
  - writable font cache on the read-only root filesystem
  - copies only app, migrations and `alembic.ini`
  - `--proxy-headers`
  - opt-in `INSTALL_ENGINE` build arg, off by default (AGPL)
- **`infra/compose.yml`:**
  - project name `kundli-milan`
  - `cap_drop: ALL`, `pids_limit`, log rotation
  - configurable localhost port
  - shared hardening block
- **`infra/compose.dev.yml` (new):** disposable PostgreSQL on `127.0.0.1:55432` and MinIO on `127.0.0.1:59000` with a local SSE key. No Redis.
- **`docs/DEPLOYMENT.md` rewritten:**
  - least-privilege DB roles and connection budget
  - S3 prefix IAM policy, public-access block and lifecycle rule
  - `.env` permissions and production guards
  - migrate-then-start and rollback
  - nginx/Caddy route snippets with `FORWARDED_ALLOW_IPS`/gateway explanation
  - logs, backups/restore, retention, a failed-jobs monitoring query
  - post-deploy checks, and a `no-new-privileges` troubleshooting note
- **`README.md` (new):** complete local setup, tests, place data.
- **`.github/workflows/check.yml`:** CI backend job now runs against a PostgreSQL service, with fonts installed, the engine installed for adapter tests and `requirements-dev.txt`.

## 4. Exact files changed

**Moved:**
- `KundliMilan_AI_Codex_Handoff/{architecture,design,prompts}` → `architecture/`, `design/`, `prompts/`
- `.../docs/{PRD,USER_FLOWS,SCREEN_SPEC,BUILD_PLAN}.md` → `docs/`
- `.../README.md`, `manifest.json`, `infra/*` → `docs/handoff/` (provenance note prepended to the README; nothing else edited)

**Backend modified:**
- `server/app/local_engine.py`, `services.py`, `worker.py`, `main.py`, `db.py`, `config.py`
- `server/migrations/env.py`, `server/migrations/versions/001_initial.py`
- `server/pytest.ini`

**Backend new:**
- `server/app/places.py`, `server/app/data/places.tsv.gz`, `server/scripts/build_places.py`, `server/requirements-dev.txt`
- Tests: `server/tests/conftest.py`, `test_local_engine.py`, `test_integration.py`, `test_reports.py`, `test_storage.py`, `test_places.py`, `test_config.py`
- Fixture slot: `server/tests/fixtures/ashtakoota_reference.json`

**Mobile modified:**
- `mobile/lib/main.dart`, `mobile/lib/api.dart`
- `mobile/lib/l10n/app_en.arb`, `mobile/lib/l10n/app_hi.arb`
- `mobile/android/app/src/main/AndroidManifest.xml`, `mobile/android/app/src/debug/AndroidManifest.xml`

**Mobile new:** `mobile/test/flows_test.dart`

**Ops/docs:**
- Modified: `infra/Dockerfile`, `infra/compose.yml`, `.env.example`, `.github/workflows/check.yml`, `docs/DEPLOYMENT.md`, `docs/ENGINE_RESEARCH.md` (appended), `summary.md`
- New: `infra/compose.dev.yml`, `README.md`

Unchanged: `server/tests/test_app.py` (its one unused import is pre-existing).

## 5. Commands run and results

| Command (from) | Result |
|---|---|
| `pytest -q` (server/, no services) | **41 passed, 7 skipped** (skips need PostgreSQL/S3, or are the empty reviewed-fixture slot) |
| `TEST_POSTGRES_URL=…55432 TEST_S3_ENDPOINT=…59001 TEST_S3_EMULATOR=1 pytest -q` | **46 passed, 2 skipped**: reviewed-fixture slot; presigned-expiry check (moto can't enforce expiry) |
| `ruff check . --select E9,F63,F7,F82` (server/) | All checks passed |
| `flutter pub get` / `flutter analyze` (mobile/) | resolved / **No issues found** |
| `flutter test` (mobile/) | **8 passed**: onboarding language; fixed-Person-1 compare/remove/re-compare/change-Person-1; localized API error; proxy error page; expired-session replacement; session renewal; settings language switch; place search fill |
| `flutter build web --release` | Built `build/web` (compile check) |
| `flutter build apk --release` (JDK 17, SDK 36, NDK 28.2) | Built `app-release.apk` (54.4 MB): minSdk 24, targetSdk 36, `INTERNET` permission present, label KundliMilan |
| `docker build -f infra/Dockerfile` | Built `kundli-milan:local` (about 350 MB) |
| Container smoke test (read-only filesystem, `--cap-drop ALL`) | health ok, guest session, `/v1/places`; about 83 MiB RSS |
| Hindi PDF rendered inside the image | Correct Devanagari shaping; Noto fonts embedded and subset (visually inspected) |
| API + `python -m app.worker` against PostgreSQL 16 over HTTP, no Redis/Celery | 3-candidate comparison computed by the worker, sorted, warnings shown; report failed honestly with `storage_not_configured`; graceful SIGTERM |

Disposable containers used: `kundli-dev-postgres-1`, now stopped (its volume remains;
`docker compose -f infra/compose.dev.yml down -v` removes it). Python packages added to `.venv`: `pypdf`, `ruff`, `moto[server]`.

## 6. Not done / blocked

- **Android release signing:** the SDK (`~/Android/Sdk`) and JDK 17 (`~/.local/opt/jdk17`) are now installed, and a release APK builds (§5).
  It is signed with the **debug key** and points at a placeholder API URL, so it is for build verification only. Not yet tested on a device.
  The first Gradle run crashed in its file watcher ("Already watching path"); build with `GRADLE_OPTS=-Dorg.gradle.vfs.watch=false` if that recurs.
- **MinIO:** this machine's Docker CLI requires `docker login` before pulling `quay.io/minio/minio` (community images are no longer on Docker Hub,
  and dl.min.io returns 410). S3 behavior was tested against the moto emulator instead. Anonymous access to objects was denied and SSE + checksum
  metadata were verified there, but **signed-URL expiry and real bucket privacy still need a run against MinIO or the real bucket**
  (`TEST_S3_ENDPOINT=…`, without `TEST_S3_EMULATOR`).
- **`no-new-privileges`:** on this host (Docker 29.8 + AppArmor) the option makes every container fail with `exec: operation not permitted`.
  Compose keeps it; DEPLOYMENT.md explains how to handle it if the server behaves the same way.
- **Not tested:** physical device or emulator runs, iOS, and anything on the shared server.

## 7. Remaining risks

1. **Astrology correctness:** the upstream rules deviate from published tables (§3.1), and there are no reviewed fixtures. Keep `ASTROLOGY_MODE=disabled` for any real users.
2. **Licensing:** `vedic-calc` is AGPL-3.0-or-later. It is not in the deployed image by default.
3. **Guest data loss:** clearing app data or 90 days of inactivity orphans the user's data. There is no recovery.
4. **Rate limiting:** the in-process limiter is per process. The proxy-level limit and correct `FORWARDED_ALLOW_IPS` are required.
5. **Memory:** worker memory for large or concurrent Hindi PDFs hasn't been measured on the target server.
6. **Person roles:** Person 1/2 map to the groom-/bride-side rule positions, which the UI discloses. A domain reviewer should confirm the wording and approach.

## 8. Decisions needed from you

1. **Engine:** accept AGPL obligations, obtain permission, implement reviewed rule tables in-house, or choose a provider. Also, who will domain-review the rules and supply reference cases?
2. **AI explanations:** which provider and model (the key must stay server-side), or keep deterministic-only for the trial.
3. **Account recovery:** which sign-in method, if any, for the trial.
4. **Manglik:** which rule variant should be validated, or keep it unavailable.
5. **Local tooling:** whether to `docker login quay.io` so the MinIO tests can run (the Android SDK and JDK 17 are now installed).
6. **Target:** first deliverable — local prototype, private trial deployment, or store release (this determines signing and privacy-policy work).

## 9. Prompt to continue

```text
Continue KundliMilan AI. Read summary.md (current status) and README.md, then the requirements in docs/PRD.md,
docs/USER_FLOWS.md, docs/SCREEN_SPEC.md, design/DESIGN_SYSTEM.md, architecture/ and docs/DEPLOYMENT.md.
Verify claims against the code before changing it. Do not enable the experimental engine for real users,
fabricate scores, use production secrets, commit, publish or deploy unless explicitly asked. Next: act on the
decisions recorded in summary.md §8, run the S3 tests against MinIO/real storage without TEST_S3_EMULATOR,
and produce a signed Android release build once the SDK is available. Update summary.md at the end.
```
