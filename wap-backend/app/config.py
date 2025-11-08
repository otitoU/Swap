"""Configuration management."""

from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application settings."""
    
    # Firebase (replaces PostgreSQL)
    firebase_credentials_path: Optional[str] = None  # Path to service account JSON
    firebase_credentials_json: Optional[str] = None  # JSON string from env var
    
    # Qdrant
    qdrant_host: str = "localhost"
    qdrant_port: int = 6333
    qdrant_collection: str = "swap_users"
    
    # Embeddings
    embedding_model: str = "sentence-transformers/bert-base-nli-mean-tokens"
    vector_dim: int = 768
    
    # App
    app_name: str = "$wap"
    debug: bool = False
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()

