"""
Supabase client — uses the service role key so it bypasses RLS.
This is intentional: the tournament engine is a trusted backend service.
Never expose the service role key to the frontend.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict
from supabase import Client, create_client


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    api_secret_key: str
    environment: str = "development"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    s = get_settings()
    return create_client(s.supabase_url, s.supabase_service_role_key)
