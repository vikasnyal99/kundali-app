# Product Requirements Document (PRD)
## Purpose
Mobile app for bilingual Vedic Kundli matching and side-by-side candidate compatibility comparison. Optimized for a free, low-traffic trial with an easy upgrade path.

## Audience
Individuals/families reviewing traditional Kundli matches; users may enter details for more than one prospective match. Clear consent and privacy reminders are required.

## MVP capabilities (P0)
1. Language selector (English/Hindi), persistent and switchable.
2. Home dashboard: New Match, Saved People, Compare Candidates, Reports.
3. Person profiles: display name, date of birth, exact local time, birth place with lat/lon, timezone (IANA), gender optional; edit/delete.
4. Robust birth-place selection: geocoding suggestions plus manual place/location/timezone confirmation. Flag approximate birth times.
5. Individual Kundli summary with computed celestial data if engine supports it, and calculation settings in methodology.
6. Pair matching: Ashta Koota/Guna Milan points (out of 36 with sub-scores), Manglik assessment and other traditional observations **only where engine can compute reliably**.
7. Compatibility explanation in Hindi/English using deterministic templates and optional server-side AI rendering; never allow AI to invent facts or numerical calculations.
8. PDF report generated asynchronously; downloadable via short-lived signed S3 URL.
9. Comparison: lock Person 1, select >=2 Person 2 candidates, compute comparable matches and show ranked list, scores, candidate detail, and switch Person 1.
10. Persistent saved matches and reports; display clear status (pending/processing/ready/failed).
11. Input validation, accessible controls, understandable failure/retry flows, privacy and deletion pathways.

## P1 after MVP
- Account sign-in/merge anonymous profile, push notifications, more report layouts, favorites/notes, optional charts and matching-history filters.

## Deliberately out of scope initially
Payments, subscriptions, social discovery, chat/matrimonial marketplace, unvetted compatibility predictions, automated scraping of third-party astrology portals.

## Accuracy and trust
- Scores must come exclusively from computation engine. Store engine/version, ayanamsa, coordinates, timezone, UTC birth instant and calculation timestamp.
- Explicit methodology page + disclaimer: interpretative/traditional framework, not a scientific determinant of relationship success.
- If birth inputs are uncertain or an algorithm unsupported, show "not available" rather than estimate silently.
- Comparison score must be apples-to-apples: same engine/settings for every candidate, deterministic sort and tie handling.

## Core acceptance tests
- Language switch updates navigation/form/report labels without erasing form state.
- Profile create/edit persists in PostgreSQL; birth-time timezone conversion remains correct across DST.
- User can hold Person 1 constant, add 3 Person 2s, refresh scores, inspect each pair, and change Person 1.
- Identical birth input/settings produces same computation under same engine version.
- AI outage still generates non-AI report; invalid model output is rejected.
- PDF stays private in S3 and is only exposed by authorized, expiring URL.
- Delete profile invalidates related matches/reports as policy dictates and schedules S3 cleanup.
- Basic integration test covers draft -> calculation -> stored report -> download.
