from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Repo-root .env when run from server/, or ./.env; real environment variables always win.
    model_config = SettingsConfigDict(env_file=('../.env','.env'), extra='ignore')
    database_url: str = 'sqlite:///./kundli.db'
    jwt_signing_key: str = 'development-only-change-before-deployment'
    app_env: str = 'development'
    s3_endpoint_url: str | None = None
    s3_bucket: str = ''
    s3_region: str = 'ap-south-1'
    report_presign_ttl_seconds: int = 300
    astrology_mode: str = 'disabled'
    astrology_release_approved: bool = False
    astrology_url: str = ''
    astrology_api_key: str = ''
    astrology_engine_version: str = 'unconfigured'
    cors_origins: str = 'http://localhost:8080'
    # The worker only renders PDFs and runs provider calculations; local matches are computed inline.
    worker_poll_seconds: float = 1
    job_max_attempts: int = 3
    job_lease_minutes: int = 10
    job_retention_days: int = 14
    # Server-side encryption header for uploads; empty for S3-compatible stores without SSE support.
    s3_sse: str = 'AES256'
    # Optional AI provider for explanation text only; scores always come from the deterministic engine.
    # Set the key in .env on the server, never in code (the repository is public).
    openai_api_key: str = ''
    openai_model: str = 'gpt-4.1-mini'
    openai_base_url: str = 'https://api.openai.com/v1'
    openai_timeout_seconds: float = 25
    def check(self):
        if self.app_env == 'production':
            if self.astrology_mode == 'local_experimental' and not self.astrology_release_approved:
                raise RuntimeError('Local engine requires license and independent validation approval for production')
            if len(self.jwt_signing_key) < 40 or self.jwt_signing_key.startswith('development'):
                raise RuntimeError('Production requires a random JWT_SIGNING_KEY of at least 40 characters')
            if not self.database_url.startswith('postgresql'):
                raise RuntimeError('Production requires PostgreSQL')
            if '*' in self.cors_origins or not all(o.startswith('https://') for o in self.cors_origins.split(',') if o):
                raise RuntimeError('Production CORS_ORIGINS must list exact https:// origins')
settings = Settings()
settings.check()
