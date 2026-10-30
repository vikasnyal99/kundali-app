# Web app stage: the screens in mobile/lib/main.dart compiled with `flutter build web`, served by the API
# at '/' (the Android app is only a native splash + WebView, mobile/lib/shell.dart). Flutter is installed
# from the pinned release archive (checksum-verified) so server builds match local ones.
FROM debian:bookworm-slim AS web
ARG FLUTTER_VERSION=3.47.8
ARG FLUTTER_SHA256=baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN flutter config --no-analytics >/dev/null && flutter precache --web >/dev/null
WORKDIR /src
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/lib ./lib
COPY mobile/web ./web
COPY mobile/assets ./assets
COPY mobile/analysis_options.yaml ./
RUN flutter build web --release -t lib/main.dart

# Pin by digest before a live rollout: docker buildx imagetools inspect python:3.12-slim-bookworm
FROM python:3.12-slim-bookworm
# Optional experimental AGPL engine (see docs/ENGINE_RESEARCH.md). Off unless a licensing decision is made.
ARG INSTALL_ENGINE=false
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 XDG_CACHE_HOME=/tmp/cache
# Pango/HarfBuzz for WeasyPrint shaping and font subsetting; Noto includes Devanagari for Hindi PDFs.
RUN apt-get update && apt-get install -y --no-install-recommends libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz-subset0 fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY server/requirements.txt server/requirements-engine.txt ./
# The engine needs git (source pin) and a C/C++ compiler (pyswisseph has no wheel); both are removed in the same layer.
RUN pip install --no-cache-dir -r requirements.txt \
    && if [ "$INSTALL_ENGINE" = "true" ]; then \
         apt-get update && apt-get install -y --no-install-recommends git gcc g++ libc6-dev \
         && pip install --no-cache-dir -r requirements-engine.txt \
         && apt-get purge -y --auto-remove git gcc g++ libc6-dev && rm -rf /var/lib/apt/lists/*; fi \
    && useradd --uid 10001 --create-home app
COPY server/app ./app
COPY server/migrations ./migrations
COPY server/alembic.ini ./
COPY --from=web /src/build/web ./web
ENV WEB_DIR=/app/web
USER app
# Uvicorn trusts X-Forwarded-For only from FORWARDED_ALLOW_IPS (set it to the reverse proxy / Docker gateway address).
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8000","--workers","1","--no-access-log","--proxy-headers"]
