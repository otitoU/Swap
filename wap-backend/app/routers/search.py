"""Search endpoints."""

from typing import List
from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.schemas import ProfileSearchResult
from app.embeddings import get_embedding_service
from app.qdrant_client import get_qdrant_service

router = APIRouter(prefix="/search", tags=["search"])


class SearchRequest(BaseModel):
    """Request model for semantic search."""
    
    query: str = Field(..., min_length=1, description="Search query")
    limit: int = Field(10, ge=1, le=100, description="Max results")
    score_threshold: float = Field(0.3, ge=0, le=1, description="Minimum similarity score")


@router.post("", response_model=List[ProfileSearchResult])
def search_profiles(request: SearchRequest):
    """
    Semantic search for profiles based on what they can offer.
    
    Uses BERT embeddings to find profiles whose skills semantically match
    the search query. Searches the offer_vec field in Qdrant.
    
    Example:
        Query: "teach me guitar and music"
        Returns: Profiles of people who can teach guitar, music theory, etc.
    """
    embedding_service = get_embedding_service()
    qdrant_service = get_qdrant_service()
    
    # Generate query embedding
    query_vec = embedding_service.encode(request.query)
    
    # Search offers
    results = qdrant_service.search_offers(
        query_vec=query_vec,
        limit=request.limit,
        score_threshold=request.score_threshold,
    )
    
    return [ProfileSearchResult(**result) for result in results]

