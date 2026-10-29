"""Writing with AI. No model is connected yet (settings.ai_provider is blank), so every AI route answers
503 AI_UNAVAILABLE and the screens keep their manual editors. Routes call ensure_available() first, so
connecting a provider later only changes this file."""
from app.core.config import settings
from app.core.errors import AppError


def available() -> bool:
    return bool(settings.ai_provider)


def ensure_available() -> None:
    if not available():
        raise AppError(503, "AI_UNAVAILABLE", "Writing with AI is not switched on for this server.")
