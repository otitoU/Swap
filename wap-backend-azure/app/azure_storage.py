"""Azure Blob Storage service - replaces Firebase Storage."""

from typing import Optional, BinaryIO
from azure.storage.blob import BlobServiceClient, ContentSettings
from app.config import settings


class AzureStorageService:
    """Service for Azure Blob Storage operations."""

    def __init__(self):
        """Initialize Azure Blob Storage client."""
        self._initialized = False
        self._blob_service_client = None
        self._container_client = None
        self._init_storage()

    def _init_storage(self):
        """Initialize Blob Storage connection."""
        if self._initialized:
            return

        if not settings.storage_connection_string:
            raise ValueError(
                "STORAGE_CONNECTION_STRING must be set in environment variables"
            )

        # Initialize Blob Service client
        self._blob_service_client = BlobServiceClient.from_connection_string(
            settings.storage_connection_string
        )
        self._container_client = self._blob_service_client.get_container_client(
            settings.storage_container
        )

        # Ensure container exists
        if not self._container_client.exists():
            self._container_client.create_container()
            print(f"Created container: {settings.storage_container}")

        self._initialized = True
        print(
            f"✓ Azure Blob Storage connected: {settings.storage_account_name}/{settings.storage_container}"
        )

    def upload_file(
        self,
        file_data: BinaryIO,
        blob_name: str,
        content_type: Optional[str] = None,
        overwrite: bool = True,
    ) -> str:
        """
        Upload a file to blob storage.

        Args:
            file_data: File data (binary)
            blob_name: Name/path for the blob
            content_type: MIME type (e.g., 'image/jpeg')
            overwrite: Whether to overwrite existing blob

        Returns:
            Blob URL
        """
        if not self._initialized:
            self._init_storage()

        blob_client = self._container_client.get_blob_client(blob_name)

        # Set content settings
        content_settings = None
        if content_type:
            content_settings = ContentSettings(content_type=content_type)

        # Upload blob
        blob_client.upload_blob(
            file_data, content_settings=content_settings, overwrite=overwrite
        )

        # Return blob URL
        return blob_client.url

    def download_file(self, blob_name: str) -> bytes:
        """
        Download a file from blob storage.

        Args:
            blob_name: Name/path of the blob

        Returns:
            File data as bytes
        """
        if not self._initialized:
            self._init_storage()

        blob_client = self._container_client.get_blob_client(blob_name)
        download_stream = blob_client.download_blob()
        return download_stream.readall()

    def delete_file(self, blob_name: str) -> bool:
        """
        Delete a file from blob storage.

        Args:
            blob_name: Name/path of the blob

        Returns:
            True if deleted, False if not found
        """
        if not self._initialized:
            self._init_storage()

        try:
            blob_client = self._container_client.get_blob_client(blob_name)
            blob_client.delete_blob()
            return True
        except Exception as e:
            print(f"Error deleting blob {blob_name}: {e}")
            return False

    def get_file_url(self, blob_name: str) -> str:
        """
        Get public URL for a blob.

        Args:
            blob_name: Name/path of the blob

        Returns:
            Blob URL
        """
        if not self._initialized:
            self._init_storage()

        blob_client = self._container_client.get_blob_client(blob_name)
        return blob_client.url

    def list_files(self, prefix: Optional[str] = None) -> list[str]:
        """
        List blobs in container.

        Args:
            prefix: Optional prefix to filter blobs

        Returns:
            List of blob names
        """
        if not self._initialized:
            self._init_storage()

        blob_list = self._container_client.list_blobs(name_starts_with=prefix)
        return [blob.name for blob in blob_list]


# Global instance
_storage_service = None


def get_storage_service() -> AzureStorageService:
    """Get or create Azure Storage service singleton."""
    global _storage_service
    if _storage_service is None:
        _storage_service = AzureStorageService()
    return _storage_service
