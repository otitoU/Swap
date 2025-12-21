"""Configuration management for Azure deployment."""

from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application settings for Azure."""

    # Azure Cosmos DB
    cosmos_endpoint: Optional[str] = None
    cosmos_key: Optional[str] = None
    cosmos_database: str = "swap_db"
    cosmos_container: str = "profiles"

    # Azure Blob Storage
    storage_account_name: Optional[str] = None
    storage_connection_string: Optional[str] = None
    storage_container: str = "profile-images"

    # Azure Cache for Redis
    redis_enabled: bool = True
    redis_hostname: Optional[str] = None
    redis_port: int = 6380  # Azure Redis uses SSL on 6380
    redis_password: Optional[str] = None
    redis_use_ssl: bool = True  # Azure Redis requires SSL
    redis_connection_string: Optional[str] = None  # Alternative to hostname/password
    redis_ttl: int = 3600  # Cache TTL in seconds (1 hour)

    # Qdrant (can keep Qdrant Cloud or migrate to Azure AI Search)
    qdrant_host: str = "localhost"
    qdrant_port: int = 6333
    qdrant_url: Optional[str] = None  # Full URL for Qdrant Cloud
    qdrant_api_key: Optional[str] = None  # API key for Qdrant Cloud
    qdrant_collection: str = "swap_users"

    # Embeddings (using smaller, faster model)
    embedding_model: str = "sentence-transformers/all-MiniLM-L6-v2"
    vector_dim: int = 384  # MiniLM uses 384 dimensions

    # Azure AD B2C (for authentication)
    azure_ad_tenant_id: Optional[str] = None
    azure_ad_client_id: Optional[str] = None
    azure_ad_client_secret: Optional[str] = None
    azure_ad_policy_name: str = "B2C_1_signupsignin"

    # App
    app_name: str = "$wap"
    debug: bool = False

    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
