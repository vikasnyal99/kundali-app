# Small Linux Deployment

Choose stable supported Ubuntu/Debian, Docker Engine and Compose; configure a dedicated non-root deploy user, SSH keys, firewall ports 22/80/443 only, and automatic security updates. For the trial, one small host running API + worker + reverse proxy is adequate after load test. Use the user's **existing PostgreSQL and S3**, not the dev Compose versions in production.

Production proxy: Caddy/Nginx TLS with automatic renewals; API internal network. Redis must not be internet-exposed. Start with one worker; measure peak memory during PDF rendering. Separate credentials for DB, S3 and AI; least privilege IAM for report prefix. Backup PostgreSQL daily with restore testing and define S3 lifecycle/deletion. Log sensitive birth fields only when absolutely necessary (prefer never). Monitor job failures, CPU/RAM/disk and TLS/certificate expiry.

Do not use exposed wildcard CORS, default dev passwords, permanent public bucket objects, or browser automation scraping as a primary AI API. Store PDF in S3 and metadata in DB. Pin image versions/digests before live rollout; review dependencies and licenses.
