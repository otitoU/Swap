"""Azure Cosmos DB service - replaces Firebase Firestore."""

from typing import Optional, Dict, Any, List
from datetime import datetime
from azure.cosmos import CosmosClient, PartitionKey, exceptions

from app.config import settings


class CosmosDBService:
    """Service for Azure Cosmos DB operations."""

    def __init__(self):
        """Initialize Cosmos DB client."""
        self._initialized = False
        self._client = None
        self._database = None
        self._container = None
        self._init_cosmos()

    def _init_cosmos(self):
        """Initialize Cosmos DB connection."""
        if self._initialized:
            return

        if not settings.cosmos_endpoint or not settings.cosmos_key:
            raise ValueError(
                "COSMOS_ENDPOINT and COSMOS_KEY must be set in environment variables"
            )

        # Initialize Cosmos client
        self._client = CosmosClient(settings.cosmos_endpoint, settings.cosmos_key)
        self._database = self._client.get_database_client(settings.cosmos_database)
        self._container = self._database.get_container_client(settings.cosmos_container)
        self._initialized = True
        print(f"✓ Cosmos DB connected: {settings.cosmos_database}/{settings.cosmos_container}")

    @property
    def container(self):
        """Get Cosmos DB container client."""
        if not self._initialized:
            self._init_cosmos()
        return self._container

    def create_profile(self, uid: str, profile_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new profile.

        Args:
            uid: User ID (used as both id and partition key)
            profile_data: Profile data dictionary

        Returns:
            Created profile data
        """
        # Add timestamps
        now = datetime.utcnow().isoformat()
        profile_data['created_at'] = now
        profile_data['updated_at'] = now
        profile_data['id'] = uid  # Cosmos DB requires 'id' field
        profile_data['uid'] = uid  # Also store as uid for compatibility

        # Create document
        created_item = self.container.create_item(body=profile_data)
        return created_item

    def get_profile(self, uid: str) -> Optional[Dict[str, Any]]:
        """
        Get a profile by UID.

        Args:
            uid: User ID

        Returns:
            Profile data or None if not found
        """
        try:
            item = self.container.read_item(item=uid, partition_key=uid)
            return item
        except exceptions.CosmosResourceNotFoundError:
            return None
        except exceptions.CosmosHttpResponseError as e:
            print(f"Error reading profile {uid}: {e.message}")
            return None

    def update_profile(self, uid: str, profile_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update an existing profile.

        Args:
            uid: User ID
            profile_data: Updated profile data

        Returns:
            Updated profile data
        """
        # Get existing profile
        existing = self.get_profile(uid)
        if not existing:
            raise exceptions.CosmosResourceNotFoundError(f"Profile {uid} not found")

        # Update timestamp
        profile_data['updated_at'] = datetime.utcnow().isoformat()

        # Merge with existing data
        existing.update(profile_data)

        # Replace document
        updated_item = self.container.replace_item(item=uid, body=existing)
        return updated_item

    def upsert_profile(self, uid: str, profile_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create or update a profile (upsert operation).

        Args:
            uid: User ID
            profile_data: Profile data

        Returns:
            Profile data
        """
        existing = self.get_profile(uid)

        if existing:
            # Update existing
            profile_data['updated_at'] = datetime.utcnow().isoformat()
            # Keep created_at from existing
            if 'created_at' not in profile_data and 'created_at' in existing:
                profile_data['created_at'] = existing['created_at']
        else:
            # Create new
            now = datetime.utcnow().isoformat()
            profile_data['created_at'] = now
            profile_data['updated_at'] = now

        # Ensure id and uid are set
        profile_data['id'] = uid
        profile_data['uid'] = uid

        # Upsert document
        upserted_item = self.container.upsert_item(body=profile_data)
        return upserted_item

    def delete_profile(self, uid: str) -> bool:
        """
        Delete a profile.

        Args:
            uid: User ID

        Returns:
            True if deleted
        """
        try:
            self.container.delete_item(item=uid, partition_key=uid)
            return True
        except exceptions.CosmosResourceNotFoundError:
            return False
        except exceptions.CosmosHttpResponseError as e:
            print(f"Error deleting profile {uid}: {e.message}")
            return False

    def list_profiles(self, limit: int = 100) -> List[Dict[str, Any]]:
        """
        List all profiles.

        Args:
            limit: Maximum number of profiles to return

        Returns:
            List of profiles
        """
        query = f"SELECT TOP {limit} * FROM c"
        items = list(
            self.container.query_items(
                query=query, enable_cross_partition_query=True
            )
        )
        return items

    def get_profile_by_email(self, email: str) -> Optional[Dict[str, Any]]:
        """
        Get a profile by email.

        Args:
            email: User email

        Returns:
            Profile data or None if not found
        """
        query = "SELECT * FROM c WHERE c.email = @email"
        parameters = [{"name": "@email", "value": email}]

        items = list(
            self.container.query_items(
                query=query,
                parameters=parameters,
                enable_cross_partition_query=True,
            )
        )

        return items[0] if items else None

    def get_profiles_by_city(self, city: str, limit: int = 100) -> List[Dict[str, Any]]:
        """
        Get profiles by city (bonus query for Azure).

        Args:
            city: City name
            limit: Maximum results

        Returns:
            List of profiles
        """
        query = f"SELECT TOP {limit} * FROM c WHERE c.city = @city"
        parameters = [{"name": "@city", "value": city}]

        items = list(
            self.container.query_items(
                query=query,
                parameters=parameters,
                enable_cross_partition_query=True,
            )
        )

        return items


# Global instance
_cosmos_service = None


def get_cosmos_service() -> CosmosDBService:
    """Get or create Cosmos DB service singleton."""
    global _cosmos_service
    if _cosmos_service is None:
        _cosmos_service = CosmosDBService()
    return _cosmos_service


def get_cosmos_db():
    """Dependency for getting Cosmos DB client (FastAPI dependency)."""
    service = get_cosmos_service()
    return service.container
