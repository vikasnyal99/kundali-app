# Shared-server deployment

No Redis or Celery: one API process and one serial worker that polls the PostgreSQL `jobs` table, using the
server's **existing** PostgreSQL, S3-compatible bucket and HTTPS reverse proxy. **Nothing in this repository has
been deployed**, and these steps do not touch other applications. Do not run them on the shared server without
explicit authorisation and concrete values.

## 0. Release gates (do not skip)

- Astrology engine: licensing decision **and** domain-reviewed fixtures passing (`server/tests/fixtures/ashtakoota_reference.json`).
  Until then keep `ASTROLOGY_MODE=disabled` (the app shows "not available", never a score). `ASTROLOGY_RELEASE_APPROVED=true` is not validation.
- Android: release signing configured (currently the debug key), device acceptance in both languages.
- Storage: signed-URL and deletion checks against the real bucket (step 7).

## 1. Accounts and least privilege

**PostgreSQL.** Create a database and roles dedicated to this app:

```sql
CREATE ROLE kundli_owner LOGIN PASSWORD '...';        -- runs migrations only
CREATE ROLE kundli_app   LOGIN PASSWORD '...' CONNECTION LIMIT 12;  -- API + worker at runtime
CREATE DATABASE kundli OWNER kundli_owner;
\c kundli
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO kundli_app;
ALTER DEFAULT PRIVILEGES FOR ROLE kundli_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO kundli_app;
```

Use `sslmode=require` (or `verify-full`) in `DATABASE_URL` when the database is not on the same host.
Connection budget: each process uses a pool of 3 with an overflow of 2. API (1 process) plus worker comes to **at most 10**
connections, plus one more during migrations. Make sure this fits the shared server's `max_connections`.

**S3.** Use a private bucket (or a dedicated prefix in an existing one) with Block Public Access on, and no public ACLs or
bucket policy grants to `*`. Runtime credentials should be limited to the report prefix:

```json
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:PutObject","s3:GetObject","s3:DeleteObject"],
 "Resource":"arn:aws:s3:::BUCKET/reports/*"}]}
```

Keep SSE enabled (`S3_SSE=AES256`, or the bucket's default encryption). Add a lifecycle rule as a backstop
for orphaned objects, e.g. expire `reports/` objects after 180 days. Reports can be regenerated from stored facts.
Signed URLs use SigV4 and expire after `REPORT_PRESIGN_TTL_SECONDS` (default 300). Clients request a fresh one each time.

## 2. Configuration

```bash
cp .env.example .env && chmod 600 .env      # owned by the deploy user; never committed
```

Set:
- `APP_ENV=production`
- `DATABASE_URL=postgresql+psycopg://kundli_app:...@host:5432/kundli?sslmode=require`
- `JWT_SIGNING_KEY`: generate with `python -c "import secrets;print(secrets.token_urlsafe(48))"`
- the S3 variables
- `CORS_ORIGINS`: exact `https://` origins only; native apps need none
- `FORWARDED_ALLOW_IPS` (step 5)

The API refuses to start in production with a short or development JWT key, a non-PostgreSQL database, wildcard
or non-HTTPS CORS origins, or the experimental engine without approval. Rotating `JWT_SIGNING_KEY` invalidates
every guest session, and guests have no recovery path, so treat it as a breaking change.

## 3. Build

```bash
docker compose -f infra/compose.yml build          # image kundli-milan:local; engine NOT included
```

Pin `python:3.12-slim-bookworm` by digest in `infra/Dockerfile` before going live. The AGPL engine is only added
with `--build-arg INSTALL_ENGINE=true`, which should happen only after the licensing decision.

## 4. Migrate, then start

```bash
docker compose -f infra/compose.yml run --rm -e DATABASE_URL='postgresql+psycopg://kundli_owner:...' api alembic upgrade head
docker compose -f infra/compose.yml up -d
docker compose -f infra/compose.yml ps   # api healthy; exactly one worker
```

If containers exit at once with `exec ...: operation not permitted`, the host's Docker/AppArmor combination
rejects `no-new-privileges`. This happened on the development machine (Docker 29.8, AppArmor default profile), while
`cap_drop: [ALL]` and `read_only` worked. Investigate the host profile first. Remove the `security_opt` line from
`infra/compose.yml` only as a deliberate, documented exception.

For upgrades, migrate first and then `up -d`. Never scale `worker`. To roll back, redeploy the previous image tag
(migrations are additive; `alembic downgrade` is only for disposable environments).

## 5. Reverse proxy (add a route; do not replace other sites' config)

The API listens on `127.0.0.1:${API_HOST_PORT:-8100}`. Example for nginx, as a new `server`/`location` only:

```nginx
location / {
    proxy_pass http://127.0.0.1:8100;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;   # overwrite, do not append client-supplied values
    proxy_set_header X-Forwarded-Proto https;
    client_max_body_size 64k;
    limit_req zone=kundli burst=20 nodelay;          # zone defined in http{}: limit_req_zone $binary_remote_addr zone=kundli:1m rate=3r/s;
}
```

Caddy equivalent: `reverse_proxy 127.0.0.1:8100` with `header_up X-Forwarded-For {remote_host}`.

Docker's port publishing makes connections reach the container from the bridge gateway, not 127.0.0.1. Find it with
`docker network inspect kundli-milan_default -f '{{(index .IPAM.Config 0).Gateway}}'` (network name = compose project + `_default`)
and set `FORWARDED_ALLOW_IPS` to that address. Without this, every client appears as one IP. The in-process limiter
(10 guest sessions/min and 180 requests/min per IP) would then throttle everyone together, which is why the proxy-level
limit above is the primary control. The in-process limiter is per process and resets on restart.

## 6. Data protection and operations

- **Logs:** the API runs without access logs; the worker logs only job IDs and reason codes. Docker log rotation is
  10 MB × 5 per container (set in compose). Never enable request-body logging at the proxy.
- **Backups:** daily `pg_dump -Fc` of the `kundli` database to storage outside the host, kept for 14–30 days. Run a
  restore test into a scratch database before launch, and periodically after.
- **Retention:** finished job rows are purged after `JOB_RETENTION_DAYS` (default 14). Deleting a person or the account
  removes matches, reports and comparisons immediately and queues S3 deletion. Exports are generated on demand.
  Publish the privacy notice and retention periods before inviting users.
- **Monitoring:** container health (`/health/ready`), CPU/RAM/disk, TLS expiry, and failed jobs:
  `SELECT kind, failure_code, count(*) FROM jobs WHERE status='failed' AND finished_at > now() - interval '1 day' GROUP BY 1,2;`
  A `lease_expired` failure means the worker died mid-job (often memory pressure while rendering a PDF).
- **Resources:** initial limits are API 0.5 CPU / 384 MiB and worker 0.5 CPU / 512 MiB. The place index adds about 20 MB to the API
  after the first search. Measure worker peak memory over a few Hindi reports and adjust to the server's spare capacity.

## 7. Post-deploy verification

1. `curl https://<host>/health/ready` returns `{"status":"ok",...}`.
2. Guest flow from the app: create 3 people, run a comparison, open details, request a report.
3. The report becomes `ready`. The signed URL downloads, and fails after the TTL. An anonymous URL to the object returns 403.
4. Delete a person and confirm the S3 object disappears after the worker runs.
5. Confirm that nothing sensitive appears in `docker compose logs`.

Guest credentials last 90 days and are renewed on each app launch. They live in device secure storage and are lost if
app data is cleared. Account sign-in/recovery is not implemented (see summary.md).

## 8. Shared EC2 host (current target)

Host `pulse-start` (i-0afa5311a28d6d635, ap-south-1, Elastic IP 65.1.226.15) already runs the Pulse monitoring stack and
panchang. Its Caddy (`monitoring-service-caddy-1`, config `/opt/pulse/infrastructure/docker-compose/Caddyfile`)
terminates HTTP/HTTPS for all sites and reaches apps over the `monitoring-service_default` network. Access is via SSM
Session Manager.

```bash
sudo git clone https://github.com/vikasnyal99/kundali-app.git /opt/kundali-app
cd /opt/kundali-app && sudo SITE=kundaliapi.zivantaai.com bash infra/server-deploy.sh
```

`infra/server-deploy.sh` generates `.env` and `.env.db` once (mode 600, never printed), builds the image with the engine,
starts `kundli-db` (own PostgreSQL 16, volume `kundli-milan_kundli-pg`, roles `kundli_owner` for migrations and
`kundli_app` for runtime), migrates, starts `kundli-api` + one `kundli-worker`, then appends one site block to the
Caddyfile (backup kept, validated before reload). Reports go to `s3://kundali-milan/reports/` using the instance role
`pulse-ec2` (no static keys). Updates: `sudo git pull && sudo SITE=... bash infra/server-deploy.sh` (idempotent).

Release decision recorded 2026-10-29: the owner chose to launch with `ASTROLOGY_MODE=local_experimental` and
`ASTROLOGY_RELEASE_APPROVED=true` before domain review. Graha Maitri is computed from the published naisargika table;
results keep the `experimental_engine` / `independent_validation_pending` labels. The engine is AGPL-3.0, so the
service's source must stay available to its users.

Hostname (2026-10-30): `kundaliapi.zivantaai.com` has an A record at Hostinger (TTL 60) → 65.1.226.15. Each `SITE`
gets its own Caddyfile block once; a hostname gets a Let's Encrypt certificate automatically (ports 80/443 must stay
open), and the older `http://65.1.226.15` block is kept so earlier debug builds keep working. The app's default
`API_BASE_URL` is `https://kundaliapi.zivantaai.com`. A Pulse redeploy that replaces the Caddyfile removes the blocks;
re-run the deploy script once per site (`SITE=kundaliapi.zivantaai.com`, and `SITE=http://65.1.226.15` while old
builds are in use).
Caddy's read-only Caddyfile mount on this host was found pointing at an older copy of the file, so the script
validates and reloads by piping the host file over stdin (`caddy reload --config /dev/stdin`). A plain
`caddy reload` inside the container would load the stale copy and drop the KundliMilan route.

### Match summaries (OpenAI)

Summaries are written by OpenAI when `OPENAI_API_KEY` is set in the server's `/opt/kundali-app/.env` (the deploy
script asks for it once, without echo, when run from an interactive shell). `OPENAI_MODEL` defaults to `gpt-4.1-mini`.
Only the koota table, Moon-chart attributes and dosha flags are sent: no names, birth dates, times or places. Answers
that mention numbers not in the facts, or that fail, fall back to the built-in templates (not cached, so the next view
retries). Successful summaries are cached per match and language in `matches.summaries` (migration `002`).
After changing the key: `docker compose -f infra/compose.server.yml up -d` (recreates the API and worker with the new env).
Check: `docker logs kundli-api 2>&1 | grep summary` shows only match IDs and HTTP status codes on failure.
