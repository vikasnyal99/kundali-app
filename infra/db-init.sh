#!/bin/sh
# Runs once, when the kundli-db volume is first initialised. POSTGRES_USER (kundli_owner) owns the schema
# and runs migrations; the API and worker connect as kundli_app with data-only privileges.
set -eu
psql -v ON_ERROR_STOP=1 -v app_pw="$KUNDLI_APP_PASSWORD" --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE kundli_app LOGIN PASSWORD :'app_pw' CONNECTION LIMIT 12;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO kundli_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO kundli_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO kundli_app;
SQL
