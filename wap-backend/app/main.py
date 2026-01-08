"""FastAPI application entry point."""

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.firebase_db import get_firebase_service
from app.routers import (
    profiles,
    search,
    swaps,
    swap_requests,
    messages,
    moderation,
    swap_completion,
    reviews,
    points,
    portfolio,
)

# #########################################################################################

# import firebase_admin
# from firebase_admin import credentials

# cred = credentials.Certificate("path/to/serviceAccountKey.json")
# firebase_admin.initialize_app(cred)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle management for the application."""
    # Startup - Initialize Firebase
    try:
        get_firebase_service()
        print("Firebase connected")
    except Exception as e:
        print(f"Firebase not configured: {e}")

    # Pre-load ML model (optional - skip if Azure not configured)
    try:
        from app.embeddings import get_embedding_service
        print("Loading embedding model...")
        embedding_service = get_embedding_service()
        embedding_service.encode("warmup")
        print("Embedding model ready!")
    except Exception as e:
        print(f"Embedding service not available: {e}")
        print("Search/matching features will be disabled until Azure is configured")

    yield
    # Shutdown
    pass


app = FastAPI(
    title=settings.app_name,
    description="Skill-for-skill exchange platform with Firebase & semantic matching",
    version="0.2.0",
    lifespan=lifespan,
)

# CORS - Allow all origins for development/hackathon
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(profiles.router)
app.include_router(search.router)
app.include_router(swaps.router)
app.include_router(swap_requests.router)
app.include_router(swap_completion.router)
app.include_router(reviews.router)
app.include_router(points.router)
app.include_router(portfolio.router)
app.include_router(messages.router)
app.include_router(moderation.router)


@app.get("/healthz")
def health_check():
    """Health check endpoint with service status."""
    from app.cache import get_cache_service

    cache = get_cache_service()

    return {
        "status": "healthy",
        "services": {
            "firebase": "connected",
            "azure_search": "configured" if settings.azure_search_endpoint else "not configured",
            "azure_openai": "configured" if settings.azure_openai_endpoint else "not configured",
            "redis": "connected" if cache.enabled else "disabled",
        }
    }


@app.get("/")
def root():
    """Root endpoint."""
    return {
        "message": "Welcome to $wap - Skill-for-skill exchange platform",
        "version": "0.3.0",
        "database": "Firebase Firestore",
        "vector_db": "Azure AI Search",
        "embeddings": "Azure OpenAI",
        "docs": "/docs",
        "health": "/healthz",
    }

