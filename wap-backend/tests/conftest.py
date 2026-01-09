"""Pytest configuration and fixtures."""
import os
import pytest
from fastapi.testclient import TestClient


@pytest.fixture(scope="session", autouse=True)
def setup_test_env():
    """Set up test environment variables."""
    os.environ["FIREBASE_CREDENTIALS_JSON"] = '{"type":"service_account","project_id":"test"}'
    os.environ["AZURE_OPENAI_ENDPOINT"] = "https://test.openai.azure.com"
    os.environ["AZURE_OPENAI_API_KEY"] = "test-key"
    os.environ["AZURE_SEARCH_ENDPOINT"] = "https://test.search.windows.net"
    os.environ["AZURE_SEARCH_API_KEY"] = "test-key"
    os.environ["DEBUG"] = "true"


@pytest.fixture
def client():
    """Create a test client for the FastAPI app."""
    from app.main import app
    return TestClient(app)

