#!/usr/bin/env bash
# Install or update KundliMilan on the shared EC2 host. Run as root from the checkout:
#   sudo SITE=kundaliapi.zivantaai.com bash infra/server-deploy.sh
# SITE is a Caddy site address: a hostname gets automatic HTTPS (Let's Encrypt), http://IP stays plain HTTP.
# Each SITE gets its own block once; earlier sites (e.g. http://65.1.226.15 for old app builds) are kept. Secrets are generated
# once into .env (API/worker) and .env.db (database), both mode 600, and are never printed.
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE="docker compose -f infra/compose.server.yml"
EDGE_NETWORK=${EDGE_NETWORK:-monitoring-service_default}
CADDY=${CADDY_CONTAINER:-monitoring-service-caddy-1}
CADDYFILE=${CADDYFILE:-/opt/pulse/infrastructure/docker-compose/Caddyfile}
SITE=${SITE:?set SITE, e.g. SITE=kundaliapi.zivantaai.com}

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
# Optional OpenAI key for match summaries: asked once without echo, stored only in .env (never in git).
if ! grep -q '^OPENAI_API_KEY=.' .env && [ -t 0 ]; then
  read -rsp "OpenAI API key for match summaries (Enter to skip): " key; echo
  if [ -n "$key" ]; then
    sed -i '/^OPENAI_API_KEY=/d' .env; printf 'OPENAI_API_KEY=%s\n' "$key" >> .env; echo "OpenAI key saved to .env"
  fi
  unset key
fi

$COMPOSE build
$COMPOSE up -d --wait kundli-db
$COMPOSE run --rm --no-deps -e DATABASE_URL="postgresql+psycopg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@kundli-db:5432/${POSTGRES_DB}" kundli-api alembic upgrade head
$COMPOSE up -d --wait

if ! grep -qxF "$SITE {" "$CADDYFILE"; then
  backup="$CADDYFILE.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$CADDYFILE" "$backup"
  cat >> "$CADDYFILE" <<EOF

# KundliMilan API (added by /opt/kundali-app/infra/server-deploy.sh; backup: $backup)
$SITE {
	encode gzip
	reverse_proxy kundli-api:8000
}
EOF
  echo "Caddy: added $SITE"
fi
# Feed the host file over stdin: Caddy's read-only single-file mount was found pointing at an older inode
# (the file had been replaced after Caddy started), so the in-container path is not trusted.
if ! docker exec -i "$CADDY" caddy validate --config /dev/stdin --adapter caddyfile < "$CADDYFILE"; then
  if [ -n "${backup:-}" ]; then cat "$backup" > "$CADDYFILE"; echo "Caddyfile invalid; restored $backup" >&2; fi
  exit 1
fi
docker exec -i "$CADDY" caddy reload --config /dev/stdin --adapter caddyfile < "$CADDYFILE"
docker exec "$CADDY" wget -qO- localhost:2019/config/ | grep -q 'kundli-api:8000' && echo "Caddy: kundli route active"
$COMPOSE ps
