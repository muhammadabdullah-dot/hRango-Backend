from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

# Values that appear in examples and tutorials. A secret equal to one of them is treated as not set.
_KNOWN_DEFAULTS = {"change-me", "changeme", "change_me", "secret", "jwt-secret", "jwt_secret", "password", "default",
                   "test", "dev", "development", "hrango", "your-secret", "your_secret_key", "replace-me"}
MIN_SECRET_LENGTH = 32


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "HRango API"
    # "production" (the default, so a forgotten setting fails safe) or "development". Development allows
    # CORS_ORIGINS=* and serves the API docs; production refuses "*" and hides /docs unless API_DOCS=true.
    app_env: Literal["development", "production"] = "production"
    # 127.0.0.1: this PC only. 0.0.0.0: every network card, so other PCs on the LAN can reach it.
    host: str = "127.0.0.1"
    port: int = 8000
    # SQL Server ODBC connection string, e.g.
    # Driver={ODBC Driver 18 for SQL Server};Server=localhost;Database=hrango_dev;Trusted_Connection=yes;TrustServerCertificate=yes
    db_url: str = ""
    # Signs sign-in tokens. Required: at least 32 random characters, never an example value. The API
    # refuses to start without it (check_startup). Changing it signs everyone out.
    jwt_secret: str = ""
    # Signs file download links. Required, and different from JWT_SECRET, so either can be rotated alone.
    file_link_secret: str = ""
    # Pause sign-in after repeated failures (app/core/login_throttle.py). Off only in tests that sign in wrongly
    # on purpose many times from one address.
    login_throttle: bool = True
    # Proxies whose X-Forwarded-For / X-Forwarded-Proto are believed (comma-separated addresses, "*" = any).
    # Behind nginx or IIS on the same machine keep 127.0.0.1; without this every caller looks like the proxy,
    # and the sign-in limits and session list would see one address.
    forwarded_allow_ips: str = "127.0.0.1"
    # How long a sign-in lasts. There is no refresh token yet; signing in again starts a new session.
    token_hours: int = 12
    # Platform staff sign in for a working day at most.
    staff_token_hours: int = 8
    # Comma-separated frontend origins, e.g. https://app.example.com. Blank = no cross-origin calls (the
    # frontend is served from the API's address or proxies /api). "*" (any origin) only in development.
    cors_origins: str = ""
    # Serve /docs, /redoc and /openapi.json. Blank = on in development, off in production.
    api_docs: bool | None = None
    # Where the server's log goes. Blank = the "logs" folder beside the app.
    log_dir: str = ""
    # Uploaded files live on this server's disk: <upload_dir>/<company>/<module>/<yyyy>/<mm>/<uuid>.<ext>.
    # Blank = the "uploads" folder beside the app. Back it up with the database.
    upload_dir: str = ""
    max_upload_mb: int = 25
    # Download links are signed and expire after this many minutes.
    file_link_minutes: int = 30
    # This API's address as browsers reach it, e.g. https://api.example.com. Blank = links start at /api, which
    # only works when the frontend is served from the same address (or proxies /api).
    public_base_url: str = ""
    # Deliver webhooks from a background thread inside the API. Turn it off when scripts/webhooks.py
    # runs as its own service instead (and in tests).
    webhook_worker: bool = True
    webhook_poll_seconds: int = 5
    # Let webhooks call private and loopback addresses (a receiver on a developer's own machine).
    # Never in production: a customer could reach the hosting network (app/core/outbound.py).
    webhook_allow_private: bool = False
    # Writing with AI (request applications, project docs, task suggestions). Blank = off: those routes
    # answer 503 AI_UNAVAILABLE and the screens keep their manual editors.
    ai_provider: str = ""
    # Sending mail (password reset, invitations, payroll close, salary revisions, share invitations). Off until
    # set up: mails are not sent and their status reads "disabled". app/core/mail.py.
    mail_enabled: bool = False
    # "smtp" (any provider: SES, SendGrid, Mailgun and Microsoft 365 all speak SMTP), or "file", which writes
    # each message as an .eml file to MAIL_FILE_DIR instead (development: open them in any mail program), with an
    # .html copy beside it that a browser opens.
    mail_backend: Literal["smtp", "file"] = "smtp"
    mail_file_dir: str = ""
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    # STARTTLS on port 587 (the usual), or implicit TLS on port 465 (smtp_ssl). Plain SMTP only in development.
    smtp_starttls: bool = True
    smtp_ssl: bool = False
    smtp_timeout_seconds: int = 20
    # Sender shown to people, e.g. "hRango <no-reply@example.com>"; the address must be one the provider allows.
    mail_from: str = ""
    mail_reply_to: str = ""
    # The web app's address as people open it, e.g. https://app.example.com: links in e-mails start here.
    app_public_url: str = "http://localhost:5190"

    # Billing (app/services/billing_service.py). Who invoices are from, as printed on them; the bank account
    # customers pay into (shown on Billing and in invoice e-mails; several lines, "\n" between them); and where
    # staff are told that a bank transfer proof is waiting (blank: nobody is e-mailed, the Platform portal still
    # lists it).
    billing_seller_name: str = "hRango"
    billing_seller_address: str = ""
    billing_seller_tax_number: str = ""
    billing_bank_details: str = ""
    billing_notify_email: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def docs_enabled(self) -> bool:
        return (not self.is_production) if self.api_docs is None else self.api_docs

    def startup_problems(self) -> list[str]:
        """Settings the API must not start with, in words an operator can act on (empty = fine)."""
        problems = [f"{name.upper()} {why}" for name, why in (
            ("jwt_secret", _secret_problem(self.jwt_secret)),
            ("file_link_secret", _secret_problem(self.file_link_secret)),
        ) if why]
        if self.jwt_secret and self.jwt_secret == self.file_link_secret:
            problems.append("FILE_LINK_SECRET must be different from JWT_SECRET.")
        if self.is_production and "*" in self.cors_origin_list:
            problems.append('CORS_ORIGINS="*" is for development only: list the frontend origin(s), '
                            "e.g. https://app.example.com, or leave it blank when the frontend proxies /api.")
        if self.is_production and self.webhook_allow_private:
            problems.append("WEBHOOK_ALLOW_PRIVATE=true is for development only: it lets customers' webhooks "
                            "reach the hosting network.")
        if self.mail_enabled:
            if not self.mail_from.strip():
                problems.append("MAIL_FROM is required when MAIL_ENABLED=true, e.g. hRango <no-reply@example.com>.")
            if self.mail_backend == "smtp" and not self.smtp_host.strip():
                problems.append("SMTP_HOST is required when MAIL_ENABLED=true and MAIL_BACKEND=smtp.")
            if self.is_production and self.mail_backend == "file":
                problems.append("MAIL_BACKEND=file is for development only: nothing would reach anyone.")
            if self.is_production and self.mail_backend == "smtp" and not (self.smtp_starttls or self.smtp_ssl):
                problems.append("SMTP needs SMTP_STARTTLS=true or SMTP_SSL=true in production: passwords and "
                                "reset links would cross the network unencrypted.")
        if self.is_production and not self.app_public_url.startswith("https://"):
            problems.append("APP_PUBLIC_URL must be the web app's https:// address in production "
                            "(links in e-mails start there).")
        return problems


def _secret_problem(value: str) -> str | None:
    if not value.strip():
        return "is not set."
    if value.strip().lower() in _KNOWN_DEFAULTS:
        return "is an example value. Anyone who knows it can sign in as any user."
    if len(value) < MIN_SECRET_LENGTH:
        return f"is too short ({len(value)} characters; at least {MIN_SECRET_LENGTH})."
    return None


def check_startup(current: "Settings") -> None:
    """Stops the API before it serves a request with settings that would let anyone forge sign-ins."""
    problems = current.startup_problems()
    if problems:
        raise SystemExit(
            "HRango API will not start:\n  - " + "\n  - ".join(problems)
            + "\nMake each secret with: .venv\\Scripts\\python.exe -c \"import secrets; print(secrets.token_urlsafe(48))\""
            + "\nand put it in .env. Changing JWT_SECRET signs everyone out; changing FILE_LINK_SECRET ends open"
            " download links.")


settings = Settings()
