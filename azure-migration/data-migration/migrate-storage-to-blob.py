#!/usr/bin/env python3
"""
Migrate Firebase Storage files to Azure Blob Storage
"""

import os
import sys
import argparse
from pathlib import Path
from azure.storage.blob import BlobServiceClient, ContentSettings


def load_config():
    """Load Azure configuration"""
    config_file = '../azure-config.env'

    if os.path.exists(config_file):
        print(f"Loading configuration from {config_file}")
        with open(config_file) as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value

    connection_string = os.getenv('STORAGE_CONNECTION_STRING')

    if not connection_string:
        print("Error: STORAGE_CONNECTION_STRING must be set")
        print("Run provision-azure-resources.sh first")
        sys.exit(1)

    return connection_string


def get_content_type(file_path):
    """Determine content type based on file extension"""
    ext = Path(file_path).suffix.lower()
    content_types = {
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.png': 'image/png',
        '.gif': 'image/gif',
        '.webp': 'image/webp',
        '.pdf': 'application/pdf',
        '.json': 'application/json',
        '.txt': 'text/plain',
    }
    return content_types.get(ext, 'application/octet-stream')


def upload_directory(input_dir, connection_string, container_name='profile-images'):
    """Upload all files from directory to Azure Blob Storage"""

    print(f"\nMigrating files from: {input_dir}")
    print(f"Target container: {container_name}\n")

    # Initialize Blob Service Client
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)

    # Ensure container exists
    try:
        container_client = blob_service_client.get_container_client(container_name)
        if not container_client.exists():
            container_client.create_container()
            print(f"Created container: {container_name}")
    except Exception as e:
        print(f"Error accessing container: {e}")
        return False

    # Walk through directory and upload files
    uploaded = 0
    failed = 0
    skipped = 0

    input_path = Path(input_dir)
    if not input_path.exists():
        print(f"Error: Directory not found: {input_dir}")
        return False

    files = list(input_path.rglob('*'))
    total_files = len([f for f in files if f.is_file()])

    print(f"Found {total_files} files to upload\n")

    for file_path in files:
        if not file_path.is_file():
            continue

        try:
            # Preserve directory structure
            relative_path = file_path.relative_to(input_path)
            blob_name = str(relative_path).replace('\\', '/')

            # Get blob client
            blob_client = blob_service_client.get_blob_client(
                container=container_name,
                blob=blob_name
            )

            # Check if blob already exists
            if blob_client.exists():
                print(f"  [SKIP] {blob_name} (already exists)")
                skipped += 1
                continue

            # Upload file
            content_type = get_content_type(str(file_path))
            content_settings = ContentSettings(content_type=content_type)

            with open(file_path, 'rb') as data:
                blob_client.upload_blob(
                    data,
                    content_settings=content_settings,
                    overwrite=False
                )

            uploaded += 1
            if uploaded % 10 == 0:
                print(f"  Progress: {uploaded}/{total_files} files uploaded...")
            else:
                print(f"  [OK] {blob_name}")

        except Exception as e:
            print(f"  [ERROR] {file_path}: {str(e)}")
            failed += 1

    # Summary
    print("\n" + "="*50)
    print("Migration Summary")
    print("="*50)
    print(f"Total files: {total_files}")
    print(f"Uploaded: {uploaded}")
    print(f"Skipped: {skipped}")
    print(f"Failed: {failed}")
    print("="*50)

    if failed > 0:
        print("\nWarning: Some files failed to upload")
        return False

    print("\n✓ Migration completed successfully!")
    return True


def verify_upload(connection_string, container_name='profile-images'):
    """Verify uploaded files"""
    print("\nVerifying upload...")

    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_client = blob_service_client.get_container_client(container_name)

    # List blobs
    blob_list = container_client.list_blobs()
    blobs = list(blob_list)

    print(f"Total blobs in container: {len(blobs)}")

    if len(blobs) > 0:
        print("\nSample files:")
        for blob in blobs[:5]:
            print(f"  - {blob.name} ({blob.size} bytes)")

        # Get container URL
        container_url = container_client.url
        print(f"\nContainer URL: {container_url}")
        print("\n✓ Verification passed!")
        return True
    else:
        print("⚠ Warning: No blobs found in container")
        return False


def main():
    parser = argparse.ArgumentParser(description='Migrate Firebase Storage to Azure Blob Storage')
    parser.add_argument('--input', '-i', required=True, help='Input directory (firebase-export/storage/)')
    parser.add_argument('--container', '-c', default='profile-images', help='Azure Blob container name')
    parser.add_argument('--verify', action='store_true', help='Verify upload after completion')

    args = parser.parse_args()

    # Load configuration
    connection_string = load_config()

    # Upload files
    success = upload_directory(args.input, connection_string, args.container)

    if not success:
        sys.exit(1)

    # Verification
    if args.verify:
        verify_upload(connection_string, args.container)

    print("\n✓ All done!")
    print("\nNext steps:")
    print("  1. Update backend code to use Azure Blob Storage")
    print("  2. Test file uploads in the application")


if __name__ == '__main__':
    main()
