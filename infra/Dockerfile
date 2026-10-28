# Pin by digest before a live rollout: docker buildx imagetools inspect python:3.12-slim-bookworm
FROM python:3.12-slim-bookworm
# Optional experimental AGPL engine (see docs/ENGINE_RESEARCH.md). Off unless a licensing decision is made.
ARG INSTALL_ENGINE=false
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 XDG_CACHE_HOME=/tmp/cache
# Pango/HarfBuzz for WeasyPrint shaping and font subsetting; Noto includes Devanagari for Hindi PDFs.
RUN apt-get update && apt-get install -y --no-install-recommends libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz-subset0 fonts-noto-core \
    $( [ "$INSTALL_ENGINE" = "true" ] && echo git ) && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY server/requirements.txt server/requirements-engine.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && if [ "$INSTALL_ENGINE" = "true" ]; then pip install --no-cache-dir -r requirements-engine.txt; fi \
    && useradd --uid 10001 --create-home app
COPY server/app ./app
COPY server/migrations ./migrations
COPY server/alembic.ini ./
USER app
# Uvicorn trusts X-Forwarded-For only from FORWARDED_ALLOW_IPS (set it to the reverse proxy / Docker gateway address).
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8000","--workers","1","--no-access-log","--proxy-headers"]
