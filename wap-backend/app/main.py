"""FastAPI application entry point."""

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.firebase_db import get_firebase_service
from app.routers import profiles, search, swaps


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle management for the application."""
    # Startup - Initialize Firebase
    get_firebase_service()
    yield
    # Shutdown
    pass


app = FastAPI(
    title=settings.app_name,
    description="Skill-for-skill exchange platform with Firebase & semantic matching",
    version="0.2.0",
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(profiles.router)
app.include_router(search.router)
app.include_router(swaps.router)


@app.get("/healthz")
def health_check():
    """Health check endpoint."""
    return {"ok": True}


@app.get("/")
def root():
    """Root endpoint."""
    return {
        "message": "Welcome to $wap - Skill-for-skill exchange platform",
        "version": "0.2.0",
        "database": "Firebase Firestore",
        "vector_db": "Qdrant",
        "docs": "/docs",
        "health": "/healthz",
    }

