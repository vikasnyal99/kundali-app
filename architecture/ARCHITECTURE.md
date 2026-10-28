# Lean Trial Architecture

Flutter app -> HTTPS REST API (FastAPI/Pydantic) -> PostgreSQL (profiles/matches/jobs/report metadata) and S3 (private PDFs). API enqueues work to Redis-backed RQ/Celery worker for astrology computation, optional AI explanation, HTML/PDF rendering and S3 upload.

## Why this fits
<10 users/day initially; start with one VPS/dedicated Linux host and 1 API worker + 1 job worker, reuse existing PostgreSQL and S3. Redis optional if simpler DB-backed jobs are preferred; scheduled job polling is acceptable at this scale with transactional locking. Do not introduce Kubernetes.

## Suggested layout
`mobile/` Flutter, `server/app/api/`, `server/app/models/`, `server/app/services/astrology/`, `server/app/services/explanations/`, `server/app/services/reports/`, `server/app/workers/`, `tests/`, `infra/`.

## Astrology engine
Evaluate license, data files and behavior for Swiss Ephemeris (pyswisseph) and any implementation of traditional Guna Milan. Do not assume the ephemeris library itself calculates all eight Kootas. Implement explicit, tested mappings and rule variants with domain review. Record chosen ayanamsa and precise calculation settings; add golden test fixtures. Mark Manglik rule variant. The app MUST NOT fabricate calculations while awaiting a real engine.

## AI explanation
Use only API key stored server-side. Provide structured computed facts in prompt, demand JSON-schema output, validate every claim/score against facts; sanitize and cap tokens. Cache by facts hash + prompt version + language. Provide deterministic templates as fallback. Never send more personal data than required; redact identifiers where possible.

## Security
HTTPS, JWT/session or anonymous scoped device tokens, authorization checks on every profile/match/report, parameterized SQL, encryption in transit, credentials via env/secret manager, rate limiting, CORS allowlist, request-size limits, no PII in logs, private S3 bucket with server-generated expiring signed URLs, S3 server-side encryption, retention/deletion policy, backups and restore tests. Never commit keys.

## Observability
Structured error logs and correlation IDs, basic health endpoint, failure counters, job retry (bounded exponential backoff) and dead-letter/failed-job inspection. Alert on repeated failures, storage growth, expired credentials.

## Privacy
Birth date/time/location is personal data. User consent and privacy policy, export/delete flow, defined retention and right to withdraw. Avoid implying that named people have consented to data processing; design clear disclosure.
