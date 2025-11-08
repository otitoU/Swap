"""API endpoint tests."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.db import Base, get_db
from app.config import settings

# Test database
SQLALCHEMY_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)


def override_get_db():
    """Override database dependency for testing."""
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db

client = TestClient(app)


def test_health_check():
    """Test health check endpoint."""
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_root():
    """Test root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "docs" in data


def test_upsert_profile():
    """Test profile creation."""
    profile_data = {
        "username": "testuser",
        "bio": "Test bio",
        "can_offer": "Python programming",
        "wants_learn": "Guitar lessons",
        "availability": ["monday", "tuesday"],
        "lat": 40.7128,
        "lon": -74.0060,
    }
    
    response = client.post("/profiles/upsert", json=profile_data)
    assert response.status_code == 200
    data = response.json()
    assert data["username"] == "testuser"
    assert data["can_offer"] == "Python programming"


def test_search():
    """Test semantic search."""
    # First create a profile
    profile_data = {
        "username": "guitarist",
        "can_offer": "Guitar lessons and music theory",
        "wants_learn": "Web development",
    }
    client.post("/profiles/upsert", json=profile_data)
    
    # Search for guitar
    search_request = {
        "query": "guitar music",
        "limit": 10,
    }
    
    response = client.post("/search", json=search_request)
    assert response.status_code == 200
    results = response.json()
    assert isinstance(results, list)


def test_reciprocal_match():
    """Test reciprocal matching."""
    match_request = {
        "my_offer_text": "Python and web development",
        "my_need_text": "Guitar and music",
        "limit": 10,
    }
    
    response = client.post("/match/reciprocal", json=match_request)
    assert response.status_code == 200
    results = response.json()
    assert isinstance(results, list)

