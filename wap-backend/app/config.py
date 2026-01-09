"""Configuration management."""

from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application settings."""
    
    # Firebase (replaces PostgreSQL)
    firebase_credentials_path: Optional[str] = None  # Path to service account JSON
    firebase_credentials_json: Optional[str] = None  # JSON string from env var

    # Azure OpenAI (for embeddings)
    azure_openai_endpoint: Optional[str] = None
    azure_openai_api_key: Optional[str] = None
    azure_openai_api_version: str = "2024-02-01"
    azure_embedding_deployment: str = "text-embedding-3-small"
    vector_dim: int = 1536  # text-embedding-3-small uses 1536 dimensions

    # Azure AI Search (for vector storage and search)
    azure_search_endpoint: Optional[str] = None
    azure_search_api_key: Optional[str] = None
    azure_search_index: str = "swap-users"
    
    # Redis Cache (optional - disabled for serverless deployment)
    redis_enabled: bool = False  # Set to True for local dev with Redis
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_ttl: int = 3600  # Cache TTL in seconds (1 hour)
    redis_url: Optional[str] = None  # Full URL for managed Redis (e.g., Upstash)

    # Email (Resend)
    resend_api_key: Optional[str] = None
    email_from: str = "onboarding@resend.dev"  # Default Resend test sender
    email_enabled: bool = True  # Set to False to disable all emails
    app_url: str = "http://localhost:3000"  # Frontend URL for email links

    # App
    app_name: str = "$wap"
    debug: bool = False
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()

