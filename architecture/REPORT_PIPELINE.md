# Report Pipeline

1. API validates ownership, input birth fields and calculation settings.
2. API creates idempotent match job keyed by profile revisions + settings hash.
3. Worker resolves local birth-time/timezone, calculates astrological data and Koota scores via tested engine.
4. Store deterministic fact JSON and methodology metadata in PostgreSQL.
5. Generate English/Hindi narrative via templates; optionally ask AI for stylistic explanation constrained to facts, schema-validate, reject hallucinated numeric details and fallback on failure.
6. Render UTF-8 HTML template using local/packaged Devanagari web font; convert PDF via WeasyPrint or headless Chromium. Test Hindi glyph shaping and pagination.
7. Write PDF to private S3 prefix `reports/{owner_scope}/{match_id}/{report_version}.pdf` with metadata/checksum and encryption.
8. Store report object key, size/hash, locale, renderer version, status; publish ready state.
9. Serve expiring presigned download URL after authorization; support refresh on expiry.
10. Retry transient failures only and keep reason code for inspection; avoid duplicate report generation by content hashes.

## Suggested report pages
Cover (both people, creation date), methodology and accuracy note, summary score/36, 8 Koota breakdowns, other evaluated findings with caveats, optional interpretation, footer with disclaimer/engine version.
