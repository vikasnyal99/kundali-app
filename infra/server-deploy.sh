#!/usr/bin/env bash
# Install or update KundliMilan on the shared EC2 host. Run as root from the checkout:
#   sudo SITE=http://65.1.226.15 bash infra/server-deploy.sh
# SITE is the Caddy site address (later e.g. kundli.example.com for automatic HTTPS). Secrets are generated
# once into .env (API/worker) and .env.db (database), both mode 600, and are never printed.
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE="docker compose -f infra/compose.server.yml"
EDGE_NETWORK=${EDGE_NETWORK:-monitoring-service_default}
CADDY=${CADDY_CONTAINER:-monitoring-service-caddy-1}
CADDYFILE=${CADDYFILE:-/opt/pulse/infrastructure/docker-compose/Caddyfile}
SITE=${SITE:?set SITE, e.g. SITE=http://65.1.226.15}

umask 077
if [ ! -f .env.db ]; then
  cat > .env.db <<EOF
POSTGRES_DB=kundli
POSTGRES_USER=kundli_owner
POSTGRES_PASSWORD=$(openssl rand -hex 24)
KUNDLI_APP_PASSWORD=$(openssl rand -hex 24)
EOF
  echo "created .env.db"
fi
set -a; . ./.env.db; set +a
if [ ! -f .env ]; then
  subnet=$(docker network inspect "$EDGE_NETWORK" -f '{{(index .IPAM.Config 0).Subnet}}')
  cat > .env <<EOF
APP_ENV=production
DATABASE_URL=postgresql+psycopg://kundli_app:${KUNDLI_APP_PASSWORD}@kundli-db:5432/${POSTGRES_DB}
JWT_SIGNING_KEY=$(openssl rand -hex 32)
S3_BUCKET=${S3_BUCKET:-kundali-milan}
S3_REGION=${S3_REGION:-ap-south-1}
S3_SSE=AES256
REPORT_PRESIGN_TTL_SECONDS=300
CORS_ORIGINS=
FORWARDED_ALLOW_IPS=${subnet}
ASTROLOGY_MODE=local_experimental
ASTROLOGY_RELEASE_APPROVED=true
EOF
  echo "created .env (FORWARDED_ALLOW_IPS=${subnet})"
fi

$COMPOSE build
$COMPOSE up -d --wait kundli-db
$COMPOSE run --rm --no-deps -e DATABASE_URL="postgresql+psycopg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@kundli-db:5432/${POSTGRES_DB}" kundli-api alembic upgrade head
$COMPOSE up -d --wait

if ! grep -q 'reverse_proxy kundli-api:8000' "$CADDYFILE"; then
  backup="$CADDYFILE.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$CADDYFILE" "$backup"
  # Append in place (same inode) so Caddy's single-file bind mount sees the change.
  cat >> "$CADDYFILE" <<EOF

# KundliMilan API (added by /opt/kundali-app/infra/server-deploy.sh; backup: $backup)
$SITE {
	encode gzip
	reverse_proxy kundli-api:8000
}
EOF
  if ! docker exec "$CADDY" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
    cat "$backup" > "$CADDYFILE"; echo "Caddyfile invalid; restored $backup" >&2; exit 1
  fi
  docker exec "$CADDY" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
  echo "Caddy: added $SITE"
fi
$COMPOSE ps
