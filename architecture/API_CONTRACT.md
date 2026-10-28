# REST API Contract (v1)
All JSON over HTTPS. IDs UUID; timestamps ISO 8601 UTC. `Authorization: Bearer <token>` with scoped anonymous/session access. Return `{error:{code,message,details}}` consistently.

- `POST /v1/guest-sessions` -> scoped token (rate limited)
- `GET /v1/me/settings`, `PATCH /v1/me/settings` -> language, defaults
- `POST /v1/people`, `GET /v1/people`, `GET /v1/people/{id}`, `PATCH /v1/people/{id}`, `DELETE /v1/people/{id}`
- `POST /v1/matches` body `{person1_id,person2_id,locale,settings}` -> `{match_id,status}`; idempotency key supported
- `GET /v1/matches/{match_id}` -> total, per-koota details, warnings, computation version, interpretation, report status
- `POST /v1/comparisons` body `{person1_id,person2_ids:[...],locale,settings}` -> comparison_id, per-candidate match status
- `GET /v1/comparisons/{id}` -> stable sorted results (only compare same rules/settings)
- `POST /v1/matches/{id}/reports` -> report job id/status; `GET /v1/reports/{id}` -> status, expiry-aware download endpoint
- `POST /v1/reports/{id}/download-url` -> `{url,expires_at}` when authorized/ready
- `GET /health/live`, `GET /health/ready`

## Person payload example
```json
{"display_name":"Sample","birth_date":"1997-09-14","birth_time_local":"09:30:00","birth_timezone":"Asia/Kolkata","birth_place_name":"Delhi, India","latitude":28.6139,"longitude":77.2090,"time_accuracy":"exact"}
```

## Match result shape
```json
{"id":"uuid","status":"ready","score":{"earned":27.5,"possible":36,"kootas":[{"key":"varna","earned":1,"possible":1}],"ruleset_version":"v1"},"manglik":{"status":"evaluated","value":"see_rules","variant":"declared-variant"},"warnings":[],"calculation":{"engine":"configured-engine","version":"x.y","ayanamsa":"configured","calculated_at":"ISO8601"},"report_id":"uuid"}
```
Numbers above are **illustrative API examples**, not genuine astrology results. Responses must reflect actual computed facts.
