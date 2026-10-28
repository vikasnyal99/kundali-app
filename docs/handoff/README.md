> **Provenance note (2026-10-28):** original handoff README, kept unchanged below. The spec files now live at the repo root (`docs/`, `design/`, `architecture/`, `prompts/`). Its `infra/` files are superseded by `infra/compose.dev.yml` (no Redis) and `docs/DEPLOYMENT.md`.

# KundliMilan AI — Complete Codex Handoff

A practical, implementation-ready handoff for a **trial-stage bilingual Kundli matchmaking mobile app**. The repository contains detailed requirements, interaction flows, architecture, schemas, API contract, deployment outline, design specifications and a copy-paste Codex prompt. This is a **planning/handoff package**, not a finished running app or native Figma document.

## Locked product choices
- Flutter Android-first; structure code for iOS later.
- Hindi and English, same UI layout; language-specific typography and copy.
- Free initial trial, fewer than 10 active users per day. Avoid unnecessary scaling services.
- Existing PostgreSQL, S3-compatible object storage for generated reports/assets.
- User has an AI API key; access it **server-side only** using env secrets; feature should also work with deterministic reports when AI is unavailable. Never hardcode credentials.
- Vedic astrology calculations through a trustworthy library / engine; show computed method, timezone and assumptions; no invented scores.
- Primary workflow: create/select Person 1 → add/select Person 2 → generate traditional Kundli match → bilingual explanations → downloadable PDF.
- Comparison mode: fix Person 1 and swap among many Person 2 profiles; rank only on consistently calculated, transparent scores, with ties and warnings.
- Optional login initially, minimal anonymous/trial-friendly flow; protect sensitive birth details.

## Files
- `docs/PRD.md`: requirements and acceptance criteria
- `docs/USER_FLOWS.md`: step-by-step UX
- `docs/SCREEN_SPEC.md`: screen details and strings
- `design/DESIGN_SYSTEM.md`: themes and Figma-ready design tokens
- `architecture/ARCHITECTURE.md`: system design, reliability and privacy
- `architecture/DATA_MODEL.sql`: PostgreSQL starter schema
- `architecture/API_CONTRACT.md`: HTTP endpoints and example payloads
- `architecture/REPORT_PIPELINE.md`: match, AI and PDF lifecycle
- `infra/docker-compose.yml`: local/dev services (app + Redis + Postgres + MinIO)
- `infra/.env.example`: configuration names only
- `infra/DEPLOYMENT.md`: small Linux deployment checklist
- `prompts/CODEX_START_PROMPT.md`: paste into Codex after extraction
- `docs/BUILD_PLAN.md`: phase-by-phase deliverables

## Start
1. Extract ZIP to a new project folder.
2. Open **that folder** in Codex.
3. Paste `prompts/CODEX_START_PROMPT.md` into Codex.
4. Add secrets to `infra/.env` locally (never commit them).
5. Ask Codex to implement one phase at a time and run tests.

## Important limitations
- Product and design text reconstruct the previous handoff; original Figma and production assets are not embedded.
- Astrology matching is a culturally rooted traditional practice, not scientific evidence about future relationship outcomes. Avoid deterministic life decisions.
- No browser-based scraping or using a consumer ChatGPT page as an undocumented backend API.
