# Phased Delivery Plan for Codex

## Phase 0 — verify & scaffold
Confirm API key provider, existing PostgreSQL/S3 connection variables, astrology engine licensing and allowed redistribution. Create project skeleton (Flutter + FastAPI), linting and CI, `.env.example` but never actual secrets.

## Phase 1 — data & basic mobile
Migrations, guest-scoped ownership, profiles CRUD, validation, bilingual localization, all navigation screens; widget/backend tests.

## Phase 2 — deterministic astrology computation
Real ephemeris and Koota rules, documented methodology, golden tests, robust timezone/geolocation handling, uncertainty warnings; verify sample cases against trusted reference results before labeling them accurate.

## Phase 3 — matches & comparisons
Async job handling, profile revision snapshots, match persistence, pinned Person 1 and many Person 2 ranking, tie handling, cached/recomputed invalidations; end-to-end test.

## Phase 4 — reports & optional AI
Server-side AI explanation with strict constraints, deterministic fallback, HTML-to-PDF Hindi support, private S3 upload/signed download; tests and retry cases.

## Phase 5 — security, deployment & release
Small Linux deployment, TLS, backups, privacy controls, rate limits, telemetry, user acceptance in both languages, Android release build. Keep iOS compatibility in code but release later.

## Definition of done
All P0 acceptance criteria pass, no fake scores or placeholder endpoint responses in production paths, sensitive resources restricted by owner, tests green, documentation updated, app works when AI is disabled.
