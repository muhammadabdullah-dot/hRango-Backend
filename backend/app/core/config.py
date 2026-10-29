from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "HRango API"
    port: int = 8000
    # SQL Server ODBC connection string, e.g.
    # Driver={ODBC Driver 18 for SQL Server};Server=localhost;Database=hrango_dev;Trusted_Connection=yes;TrustServerCertificate=yes
    db_url: str = ""
    jwt_secret: str = "change-me"
    # How long a sign-in lasts. There is no refresh token yet; signing in again starts a new session.
    token_hours: int = 12
    # Comma-separated frontend origins, or "*" for any. "*" is acceptable in development only because auth
    # is a Bearer header and no cookies are used. Set the real origin(s) in .env before any deployment.
    cors_origins: str = "*"
    # Where the server's log goes. Blank = the "logs" folder beside the app.
    log_dir: str = ""
    # Uploaded files live on this server's disk: <upload_dir>/<company>/<module>/<yyyy>/<mm>/<uuid>.<ext>.
    # Blank = the "uploads" folder beside the app. Back it up with the database.
    upload_dir: str = ""
    max_upload_mb: int = 25
    # Download links are signed and expire after this many minutes.
    file_link_minutes: int = 30
    # Deliver webhooks from a background thread inside the API. Turn it off when scripts/webhooks.py
    # runs as its own service instead (and in tests).
    webhook_worker: bool = True
    webhook_poll_seconds: int = 5
    # Writing with AI (request applications, project docs, task suggestions). Blank = off: those routes
    # answer 503 AI_UNAVAILABLE and the screens keep their manual editors.
    ai_provider: str = ""
    # Sending mail (payroll close, salary revisions, share invitations). Off until SMTP is set up: mails
    # are not sent and their status reads "disabled".
    mail_enabled: bool = False

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
