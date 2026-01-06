"""Azure AI Search client for vector operations."""

from typing import List, Dict, Any
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SearchField,
    SearchFieldDataType,
    VectorSearch,
    HnswAlgorithmConfiguration,
    VectorSearchProfile,
    SearchableField,
    SimpleField,
)
from azure.search.documents.models import VectorizedQuery

from app.config import settings


class AzureSearchService:
    """Service for managing Azure AI Search vector operations."""

    def __init__(self):
        """Initialize Azure AI Search client and ensure index exists."""
        credential = AzureKeyCredential(settings.azure_search_api_key)

        # Index client for schema management
        self.index_client = SearchIndexClient(
            endpoint=settings.azure_search_endpoint,
            credential=credential,
        )

        # Search client for document operations
        self.search_client = SearchClient(
            endpoint=settings.azure_search_endpoint,
            index_name=settings.azure_search_index,
            credential=credential,
        )

        self.index_name = settings.azure_search_index
        self._ensure_index()

    def _ensure_index(self):
        """Create index if it doesn't exist."""
        try:
            self.index_client.get_index(self.index_name)
        except Exception:
            # Index doesn't exist, create it
            self._create_index()

    def _create_index(self):
        """Create the search index with vector fields."""
        fields = [
            SimpleField(name="id", type=SearchFieldDataType.String, key=True),
            SimpleField(name="uid", type=SearchFieldDataType.String, filterable=True),
            SearchableField(name="email", type=SearchFieldDataType.String),
            SearchableField(name="display_name", type=SearchFieldDataType.String),
            SimpleField(name="photo_url", type=SearchFieldDataType.String),
            SearchableField(name="full_name", type=SearchFieldDataType.String),
            SearchableField(name="username", type=SearchFieldDataType.String),
            SearchableField(name="bio", type=SearchFieldDataType.String),
            SearchableField(name="city", type=SearchFieldDataType.String, filterable=True),
            SimpleField(name="timezone", type=SearchFieldDataType.String),
            SearchableField(name="skills_to_offer", type=SearchFieldDataType.String),
            SearchableField(name="services_needed", type=SearchFieldDataType.String),
            SimpleField(name="dm_open", type=SearchFieldDataType.Boolean, filterable=True),
            SimpleField(name="show_city", type=SearchFieldDataType.Boolean, filterable=True),
            # Vector fields
            SearchField(
                name="offer_vec",
                type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True,
                vector_search_dimensions=settings.vector_dim,
                vector_search_profile_name="vector-profile",
            ),
            SearchField(
                name="need_vec",
                type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True,
                vector_search_dimensions=settings.vector_dim,
                vector_search_profile_name="vector-profile",
            ),
        ]

        vector_search = VectorSearch(
            algorithms=[
                HnswAlgorithmConfiguration(name="hnsw-config"),
            ],
            profiles=[
                VectorSearchProfile(
                    name="vector-profile",
                    algorithm_configuration_name="hnsw-config",
                ),
            ],
        )

        index = SearchIndex(
            name=self.index_name,
            fields=fields,
            vector_search=vector_search,
        )

        self.index_client.create_index(index)

    def upsert_profile(
        self,
        username: str,
        offer_vec: List[float],
        need_vec: List[float],
        payload: Dict[str, Any],
    ):
        """
        Upsert a profile to Azure AI Search.

        Args:
            username: Unique identifier (used as document ID)
            offer_vec: Embedding of skills_to_offer
            need_vec: Embedding of services_needed
            payload: Profile metadata
        """
        document = {
            "id": username,
            "uid": payload.get("uid", username),
            "email": payload.get("email", ""),
            "display_name": payload.get("display_name", ""),
            "photo_url": payload.get("photo_url", ""),
            "full_name": payload.get("full_name", ""),
            "username": payload.get("username", ""),
            "bio": payload.get("bio", ""),
            "city": payload.get("city", ""),
            "timezone": payload.get("timezone", ""),
            "skills_to_offer": payload.get("skills_to_offer", ""),
            "services_needed": payload.get("services_needed", ""),
            "dm_open": payload.get("dm_open", True),
            "show_city": payload.get("show_city", True),
            "offer_vec": offer_vec,
            "need_vec": need_vec,
        }

        self.search_client.merge_or_upload_documents([document])

    def search_offers(
        self,
        query_vec: List[float],
        limit: int = 10,
        score_threshold: float = 0.3,
    ) -> List[Dict[str, Any]]:
        """
        Search profiles by their offer vector.

        Args:
            query_vec: Query embedding
            limit: Max results
            score_threshold: Minimum similarity score

        Returns:
            List of matching profiles with scores
        """
        vector_query = VectorizedQuery(
            vector=query_vec,
            k_nearest_neighbors=limit,
            fields="offer_vec",
        )

        results = self.search_client.search(
            search_text=None,
            vector_queries=[vector_query],
            top=limit,
        )

        matches = []
        for result in results:
            score = result.get("@search.score", 0)
            # Azure AI Search returns scores differently, normalize if needed
            # HNSW with cosine returns scores where higher is better
            if score >= score_threshold:
                matches.append({
                    "username": result.get("id"),
                    "score": score,
                    "uid": result.get("uid"),
                    "email": result.get("email"),
                    "display_name": result.get("display_name"),
                    "photo_url": result.get("photo_url"),
                    "full_name": result.get("full_name"),
                    "bio": result.get("bio"),
                    "city": result.get("city"),
                    "timezone": result.get("timezone"),
                    "skills_to_offer": result.get("skills_to_offer"),
                    "services_needed": result.get("services_needed"),
                    "dm_open": result.get("dm_open"),
                    "show_city": result.get("show_city"),
                })

        return matches

    def search_needs(
        self,
        query_vec: List[float],
        limit: int = 10,
        score_threshold: float = 0.3,
    ) -> List[Dict[str, Any]]:
        """
        Search profiles by their need vector.

        Args:
            query_vec: Query embedding
            limit: Max results
            score_threshold: Minimum similarity score

        Returns:
            List of matching profiles with scores
        """
        vector_query = VectorizedQuery(
            vector=query_vec,
            k_nearest_neighbors=limit,
            fields="need_vec",
        )

        results = self.search_client.search(
            search_text=None,
            vector_queries=[vector_query],
            top=limit,
        )

        matches = []
        for result in results:
            score = result.get("@search.score", 0)
            if score >= score_threshold:
                matches.append({
                    "username": result.get("id"),
                    "score": score,
                    "uid": result.get("uid"),
                    "email": result.get("email"),
                    "display_name": result.get("display_name"),
                    "photo_url": result.get("photo_url"),
                    "full_name": result.get("full_name"),
                    "bio": result.get("bio"),
                    "city": result.get("city"),
                    "timezone": result.get("timezone"),
                    "skills_to_offer": result.get("skills_to_offer"),
                    "services_needed": result.get("services_needed"),
                    "dm_open": result.get("dm_open"),
                    "show_city": result.get("show_city"),
                })

        return matches

    def delete_profile(self, username: str):
        """Delete a profile from Azure AI Search."""
        self.search_client.delete_documents([{"id": username}])


# Global instance
_azure_search_service = None


def get_azure_search_service() -> AzureSearchService:
    """Get or create Azure Search service singleton."""
    global _azure_search_service
    if _azure_search_service is None:
        _azure_search_service = AzureSearchService()
    return _azure_search_service
