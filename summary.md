# KundliMilan AI — Project Status

**Updated:** 2026-10-29 (fourth session: instant matches, OpenAI summaries, new PDF; see §11)  
**Workspace:** `/home/vikas/Desktop/kundali-app`  
**Live** at `https://kundaliapi.zivantaai.com` (since 2026-10-30; `http://65.1.226.15` kept for old debug builds) on EC2
`pulse-start`, server at commit `b8a80ce` on `main`. See §10–§12.

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

1. **Astrology correctness:** Graha Maitri is now computed from the published naisargika table (§10); the other seven kootas were checked against published tables, but there are still no domain-reviewed fixtures. The owner chose to launch anyway; results keep the experimental labels.
2. **Licensing:** `vedic-calc` is AGPL-3.0-or-later and **is in the deployed image**. The service's source must stay available to its users (repo is public); an AGPL `LICENSE` and an in-app source link are still missing.
3. **Guest data loss:** clearing app data or 90 days of inactivity orphans the user's data. There is no recovery.
4. **Rate limiting:** the in-process limiter is per process. The proxy-level limit and correct `FORWARDED_ALLOW_IPS` are required.
5. **Memory:** worker memory for large or concurrent Hindi PDFs hasn't been measured on the target server.
6. **Person roles:** Person 1/2 map to the groom-/bride-side rule positions, which the UI discloses. A domain reviewer should confirm the wording and approach.

## 8. Decisions needed from you

1. **Engine:** accept AGPL obligations, obtain permission, implement reviewed rule tables in-house, or choose a provider. Also, who will domain-review the rules and supply reference cases?
2. ~~**AI explanations**~~ **decided 2026-10-29:** OpenAI `gpt-4.1-mini`, explanation text only, live (§11). Still open: a consent/privacy notice that chart attributes are sent to OpenAI.
3. **Account recovery:** which sign-in method, if any, for the trial.
4. **Manglik:** which rule variant should be validated, or keep it unavailable.
5. **Local tooling:** whether to `docker login quay.io` so the MinIO tests can run (the Android SDK and JDK 17 are now installed).
6. **Target:** first deliverable — local prototype, private trial deployment, or store release (this determines signing and privacy-policy work).

## 9. Prompt to continue

```text
Continue KundliMilan AI. Read summary.md (current status) and README.md, then the requirements in docs/PRD.md,
docs/USER_FLOWS.md, docs/SCREEN_SPEC.md, design/DESIGN_SYSTEM.md, architecture/ and docs/DEPLOYMENT.md.
Verify claims against the code before changing it. Never fabricate scores (AI must not produce scores), never
type secrets into consoles, and commit, push or deploy only when explicitly asked. The live server is described in
summary.md §10–§11 and docs/DEPLOYMENT.md §8 (the owner deploys over SSM: git pull, then infra/server-deploy.sh;
never only docker compose, which skips migrations). Next: open items in §10 and §11, then the decisions in §8.
Update summary.md at the end.
```

## 10. Deployment (2026-10-29)

**Where:** EC2 `i-0afa5311a28d6d635` (`pulse-start`, m7i-flex.large, Amazon Linux 2023, ap-south-1, Elastic IP
65.1.226.15), shared with the Pulse monitoring stack and panchang. Access via SSM Session Manager in the console (the
laptop's AWS CLI keys are invalid; CloudShell is blocked by pending account verification). Checkout: `/opt/kundali-app`.

**What runs:** `kundli-db` (postgres:16-alpine, volume `kundli-milan_kundli-pg`, roles `kundli_owner` for migrations
and `kundli_app` for runtime), `kundli-api`, one `kundli-worker`; image `kundli-milan:server` built with the engine.
No host ports. Caddy (`monitoring-service-caddy-1`) routes `http://65.1.226.15` → `kundli-api:8000`. Block appended to
`/opt/pulse/infrastructure/docker-compose/Caddyfile` (backup `Caddyfile.bak.20261028212732`). Secrets in
`/opt/kundali-app/.env` and `.env.db` (root, 600). Reports in `s3://kundali-milan/reports/` via instance role `pulse-ec2`.
`ASTROLOGY_MODE=local_experimental`, `ASTROLOGY_RELEASE_APPROVED=true` by the owner's decision.

**Changes this session:**
| File | Change |
|---|---|
| `server/app/local_engine.py` | Graha Maitri computed from the naisargika relationship table (fixes upstream Mars/Saturn, Venus/Moon, Moon/Mercury); `RULESET` → `…+naisargika-maitri-v1` |
| `server/app/services.py` | S3 client uses the regional endpoint + virtual host (global-host presigned URLs got a 307 → 403) |
| `infra/compose.server.yml`, `infra/db-init.sh`, `infra/server-deploy.sh` (new) | Server stack, DB role bootstrap, idempotent deploy (secrets, build, migrate, start, Caddy via stdin) |
| `infra/Dockerfile` | git/gcc/g++ only during the engine build (pyswisseph has no wheel), purged in the same layer |
| `.dockerignore` (new), `.gitignore` | Exclude `.env*`, `.git`, `.venv`, `mobile` from the build context; ignore `.env.db` |
| `server/tests/test_local_engine.py`, `server/tests/test_config.py` | Published 7×7 Graha Maitri table, adapter corrections, regional presigned URL |
| `docs/DEPLOYMENT.md` | §8 Shared EC2 host |

**Verification:** backend `pytest` 46 passed, 7 skipped; ruff (CI rules) clean. Local run of `compose.server.yml`:
roles created, migrations, healthy containers, real scores. Live over `http://65.1.226.15`: `/health/ready` →
`{"status":"ok","calculation_available":true}`; 3-person comparison (26 and 22 of 36, correctly ranked); EN and HI
PDF reports stored in S3, signed download works (15 KB / 19 KB PDFs), anonymous object URL → 403; account delete → 204.
Other sites on the host unchanged (zivantaai.com 307, app.zivantaai.com 200, api./panchang. 404 at `/` as before).

**Problems found and fixed:** engine build lacked a compiler; presigned URLs used the global S3 host; Caddy's read-only
single-file mount pointed at a stale copy of the Caddyfile (now reloaded via stdin).

**Open items:**
1. ~~IAM `s3:DeleteObject`~~ **resolved 2026-10-29:** permission added by the owner; failed `delete_object` jobs re-queued
   and completed, probe object and all test data removed (DB: 0 users/people/reports). Live re-test: a deleted
   account's PDF returns 404.
2. ~~**Hostname + HTTPS**~~ **resolved 2026-10-30:** `https://kundaliapi.zivantaai.com` (§12).
3. ~~**OpenAI key**~~ **resolved 2026-10-29:** summaries are live (§11). The key is in the server's `.env` (entered at the
   deploy prompt) and in the laptop's gitignored `.env`; it is not in git. The key pasted in chat earlier should still be
   revoked if it is a different one. A privacy notice about sending chart attributes to OpenAI is still missing.
4. AGPL `LICENSE` + in-app source link; privacy notice; release signing; backups (`pg_dump` of `kundli-db`); monitoring.
5. A Pulse redeploy that replaces the Caddyfile drops the KundliMilan block; re-run `infra/server-deploy.sh`.

## 11. Speed, AI summaries and the new PDF (2026-10-29, fourth session)

**Reported by the owner:** "Generate match" gave no feedback for a long time (e.g. Deepak & Kirti Saini, Vikas &
Nikita); the PDF did not look like a professional janam patri milan; the summary should be its own page, with a
"Generate full report" button at the end that produces a downloadable PDF; summaries should use OpenAI.

**Root cause of the slowness:** OpenAI was not involved: it was not used anywhere. The calculation takes about 1 ms,
but every match went through the job queue (worker polled every 3 s) and the app polled every 3 s. One network error
stopped polling for good, and the score only appeared as a small line at the bottom of the match screen. Measured live
before the change: about 2.8 s per match. A person saved with an "unknown" birth time makes the match fail with
`birth_time_required`, which the app showed only as "Needs attention". Production logs were **not** checked: opening
the AWS console from this machine was blocked by the permission system.

### What changed

| Change | Where |
|---|---|
| Local-engine matches, comparisons and retries are computed inside the request; provider mode still uses the queue | `server/app/main.py` `compute()` |
| Worker polls every 1 s (`WORKER_POLL_SECONDS`) | `config.py`, `.env.example` |
| OpenAI summary around the engine facts (`gpt-4.1-mini`, JSON schema output). Only the koota table, Moon-chart attributes and dosha flags are sent: no names, dates or places (people are `{P1}`/`{P2}`, filled in locally). Any digit in the answer, a missing koota note or a stray placeholder rejects it in favour of the template (not cached, so the next view retries). | `server/app/summary.py`, `GET /v1/matches/{id}/summary?locale=` |
| Deterministic EN/HI template summary when no key is set or a call fails | `summary.py` `template()` |
| Summary cached per match and locale; pre-generated in the background after `POST /v1/matches`; `VERSION` (now `v2`) regenerates cached text when the prompt changes | `main.py` `warm_summary`, `summary.py` |
| `matches.summaries` JSON column | `db.py`, `migrations/versions/002_match_summaries.py` |
| 4-page janam patri milan PDF: Ganesh invocation, couple card, guna medallion, verdict scale and dosha badges, Ashtakoot table with each person's varna/vashya/tara/yoni/maitri/gana/bhakoot/nadi; birth details and Avakhada chakra with the overview and dosha notes; North Indian Lagna charts and planetary positions; koota-wise reading, strengths, considerations, guidance; method notes and disclaimer | `server/app/report.py` |
| Chart details (Lagna, nine grahas, Avakhada) recomputed for display from the stored birth data; Hindi names for signs, nakshatras, grahas and Avakhada values; North Indian chart with SVG lines and HTML labels (WeasyPrint's SVG text detaches Devanagari vowel signs) | `server/app/jyotish.py` |
| Report list returns the couple's names and score | `main.py` `report_json` |
| App: a single match opens a new summary page at once (score, band, doshas, AI summary, koota cards, strengths, considerations, guidance); "Generate full report" at the end polls every 1.5 s and opens the PDF, then shows "Download PDF"; match polling every 1 s, tolerant of up to 5 failed polls; failure codes explained; Reports tab shows names, score and language | `mobile/lib/main.dart`, both ARB files |
| Deploy script asks once, without echo, for the OpenAI key and stores it only in the server `.env` | `infra/server-deploy.sh`, `docs/DEPLOYMENT.md` |

### Commits (all pushed to `main` and deployed)

| Commit | Content |
|---|---|
| `cff728c` | Instant matches, OpenAI summaries, new PDF, summary page, deploy prompt |
| `fb1d9aa` | Method notes as compact lines so the PDF stays at four pages (real engine version strings had pushed it to five) |
| `aa2418b` | One short sentence per koota note and tighter list spacing (English AI text had spilled onto a fifth page); summary `VERSION` → `v2` |

### Verification

- Backend `pytest`: **55 passed, 7 skipped** (new `tests/test_summary.py`: inline calculation without jobs, immediate
  `birth_time_required`, template summary and caching, mocked OpenAI with names filled in and no birth data sent,
  rejection of invented numbers/missing notes/stray placeholders, full report with real chart details). Migration 002
  applied to a scratch SQLite database.
- Mobile: `flutter analyze` clean; `flutter test` **9 passed** (new: match opens its summary; full report polls and
  requests the download URL).
- Live OpenAI from the laptop: EN and HI summaries in about 6 s. The first prompt let the model garble the Hindi total
  ("कुल 25.5 में से 36 गुण") and misspell terms; the prompt now forbids all numbers and requires the given names.
- Live server after the final deploy (throwaway guests, deleted afterwards): match ready in 0.4 s (was about 2.8 s);
  pre-warmed summary 0.07 s, cold Hindi summary about 6.4 s, `source: ai`; PDF ready in about 3.4 s; two pairs × EN/HI
  all 4 pages.

### Notes and open items

1. **Deploying:** the first attempt rebuilt without `git pull`, so every build layer was `CACHED` and the old code kept
   running. Always `sudo git pull`, check `git log --oneline -1`, then `infra/server-deploy.sh` (it also runs migrations).
2. **Secrets:** the owner put the OpenAI key in `.env.example`, which is tracked in a public repo. It was moved to the
   gitignored `.env` (mode 600) before committing; staged diffs were checked for `sk-` keys before each push.
3. **Old reports** keep their old layout: an existing report for a match and language is reused.
4. **Flutter SDK** is now at `~/.local/opt/flutter` (3.47.8 stable); the previous `/tmp/kundli-flutter` had disappeared.
   APK: `flutter build apk --release` (defaults to the HTTPS API, see §12) with `JAVA_HOME=~/.local/opt/jdk17`,
   `GRADLE_OPTS=-Dorg.gradle.vfs.watch=false`.
5. **Privacy:** add a notice that chart attributes (not names or birth data) are sent to OpenAI.
6. **Upstream rule note (for the domain reviewer):** vedic-calc gives Yoni 3/4 when both people have the same animal and
   the same gender; most published tables give 4/4. Not changed.
7. iOS was discussed and deferred: the Flutter project is iOS-ready, but builds need macOS (e.g. Codemagic) and an
   Apple Developer account.

## 12. Domain and HTTPS (2026-10-30)

- **DNS:** the owner added an A record at Hostinger: `kundaliapi` → `65.1.226.15`, TTL 60, on `zivantaai.com`
  (nameservers `ns1/ns2.dns-parking.com`). Resolves on 8.8.8.8 and 1.1.1.1.
- **Problem found:** HTTPS failed with a TLS alert because Caddy had no site for the name, so it had no certificate.
  `infra/server-deploy.sh` only added a site when no KundliMilan route existed, so the IP block blocked any new one.
- **Fix (`b8a80ce`):** the script adds one Caddy block per `SITE` (exact `SITE {` line match). A hostname gets a
  Let's Encrypt certificate automatically. The `http://65.1.226.15` block is kept for existing debug builds.
  Deploy: `cd /opt/kundali-app && sudo git pull && sudo SITE=kundaliapi.zivantaai.com bash infra/server-deploy.sh`.
- **App:** `mobile/lib/api.dart` defaults `API_BASE_URL` to `https://kundaliapi.zivantaai.com`;
  `server/scripts/api_smoke.sh` defaults to the same. `flutter analyze` clean, `flutter test` 9 passed.
  Release APK built: `mobile/build/app/outputs/flutter-apk/app-release.apk` (54.6 MB, signed with the debug key like
  the earlier debug APK, so it installs over it and keeps data).
- **Verified live:** `/health/ready` over HTTPS in 0.15 s; certificate issuer Let's Encrypt, valid until 2027-01-27
  (Caddy renews). Full `api_smoke.sh` over HTTPS passed: match, ranked comparison, PDF with signed download, unsigned
  object → 403, export, account delete → 204, signed URL after delete → 404. `http://65.1.226.15` still answers.
- **Open:** a real release signing key before any Play Store upload; retire the IP block once no debug builds remain;
  a Pulse redeploy that replaces the Caddyfile drops both blocks (re-run the deploy script per site).

## 13. Person form and unknown birth time (2026-10-30)

**Reported:** every match showed "A birth time is marked as unknown"; the owner wants the form as Full name → one
birth-place search (also by pincode) that fills itself → no latitude/longitude → time accuracy (no time asked when
Unknown) → DD / MM / YYYY → HH : MM AM/PM.

**Finding:** that message is the app's text for `birth_time_required`, which the server returned for any person saved
with accuracy "Unknown". The old form defaulted to "Exact", and widget tests confirm the form sends `exact` unless
Unknown is chosen. Production data was not inspected, so which people were saved as Unknown is not confirmed.

| Change | Where |
|---|---|
| Unknown time no longer fails: the person is saved at 12:00 noon local time (no time needed in the request) and matched with warnings `birth_time_unknown_noon`, plus `unknown_time_moon_changes_that_day` when the Moon changed nakshatra or rashi during that local day (it does on most days). External providers still require a time | `schemas.py`, `local_engine.py` (`moon_at`, `moon_changes_that_day`), `services.py` |
| PDF for an unknown time: time shown as "unknown", Lagna "—", no Lagna chart (dashed note instead), planets labelled as noon positions | `report.py` |
| Pincode search (6-digit prefix, at least 3 digits) and post-office fallback for town/village names; 155,546 post offices from GeoNames India postal codes (CC BY 4.0), `app/data/pincodes.tsv.gz` (1.4 MB), built by `scripts/build_pincodes.py` | `places.py` |
| New form: Full name; one place search (city, town or pincode) that must be chosen from suggestions, with coordinates and timezone hidden; "Birth time known?" Exact/Approximate/Unknown; DD / MM / YYYY boxes (real past dates only); HH : MM boxes with AM/PM, hidden for Unknown; DST choice only shown when the server reports an ambiguous time | `mobile/lib/main.dart` `PersonEditor` |
| People list shows DD/MM/YYYY and 12-hour time (or "time unknown"); summary page explains unknown-time warnings | `main.dart`, both ARB files |

**Verification:** backend `pytest` 59 passed, 7 skipped (new: noon save without a time, steady day 1996-01-05 vs.
changing day 1998-02-20, provider mode still requires a time, report without Lagna chart, pincode and post-office
search). `flutter analyze` clean, `flutter test` 10 passed (new: form body for exact time 9:30 PM → `21:30:00`, unknown
time sends no time, invalid 31 February and unchosen place are rejected). Release APK rebuilt (55.0 MB).
Check on the server which saved people are Unknown:
`sudo docker exec kundli-db psql -U kundli_owner -d kundli -c "select data->>'time_accuracy', count(*) from people group by 1"`.
