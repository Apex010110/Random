"""Runtime configuration. Everything comes from environment variables (see .env.example)."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "demo"  # demo | production
    database_url: str = "sqlite:///./cartcloser_demo.db"

    # Demo-mode merchant auth: a static bearer token mapped to the seeded merchant user.
    # Production must replace this with real merchant auth (see docs/security.md).
    demo_merchant_token: str = "demo-merchant-token"
    demo_other_tenant_token: str = "other-tenant-token"

    # AI provider. Empty key => deterministic rule-based assistant only.
    ai_provider: str = "rules"  # rules | anthropic
    anthropic_api_key: str = ""
    ai_model: str = "claude-opus-5-5"
    ai_timeout_seconds: float = 8.0

    # Webhook secrets. Empty => endpoint answers 503 "not connected".
    shopify_webhook_secret: str = ""
    woocommerce_webhook_secret: str = ""

    # WhatsApp Business Platform. Not implemented: the simulator is the only channel.
    whatsapp_enabled: bool = False

    scheduler_interval_seconds: float = 1.0
    cors_origins: str = "*"

    @property
    def demo_mode(self) -> bool:
        return self.app_env == "demo"


@lru_cache
def get_settings() -> Settings:
    return Settings()
