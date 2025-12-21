#!/usr/bin/env python3
"""
Import Firebase data to Azure Cosmos DB
Reads JSON export from Firebase and imports to Cosmos DB
"""

import json
import argparse
import os
import sys
from datetime import datetime
from azure.cosmos import CosmosClient, PartitionKey, exceptions


def load_config():
    """Load Azure configuration from environment or config file"""
    config_file = '../azure-config.env'

    if os.path.exists(config_file):
        print(f"Loading configuration from {config_file}")
        with open(config_file) as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value

    endpoint = os.getenv('COSMOS_ENDPOINT')
    key = os.getenv('COSMOS_KEY')
    database_name = os.getenv('COSMOS_DATABASE', 'swap_db')
    container_name = os.getenv('COSMOS_CONTAINER', 'profiles')

    if not endpoint or not key:
        print("Error: COSMOS_ENDPOINT and COSMOS_KEY must be set")
        print("Either set environment variables or run provision-azure-resources.sh first")
        sys.exit(1)

    return endpoint, key, database_name, container_name


def import_profiles(input_file, endpoint, key, database_name, container_name):
    """Import profiles from JSON to Cosmos DB"""

    print(f"\nImporting data from: {input_file}")
    print(f"Target: {endpoint}/{database_name}/{container_name}\n")

    # Load JSON data
    with open(input_file, 'r') as f:
        profiles = json.load(f)

    print(f"Found {len(profiles)} profiles to import")

    # Initialize Cosmos client
    client = CosmosClient(endpoint, key)
    database = client.get_database_client(database_name)
    container = database.get_container_client(container_name)

    # Import profiles
    imported = 0
    failed = 0
    skipped = 0

    for i, profile in enumerate(profiles, 1):
        try:
            # Ensure required fields
            if 'uid' not in profile:
                print(f"  [SKIP] Profile {i}: Missing uid field")
                skipped += 1
                continue

            # Use uid as the id for Cosmos DB
            profile['id'] = profile.get('_id', profile['uid'])

            # Remove Firebase-specific ID if present
            if '_id' in profile:
                del profile['_id']

            # Convert timestamp strings back to datetime if needed
            if 'created_at' in profile and isinstance(profile['created_at'], str):
                try:
                    profile['created_at'] = datetime.fromisoformat(profile['created_at'].replace('Z', '+00:00'))
                except:
                    pass

            if 'updated_at' in profile and isinstance(profile['updated_at'], str):
                try:
                    profile['updated_at'] = datetime.fromisoformat(profile['updated_at'].replace('Z', '+00:00'))
                except:
                    pass

            # Upsert to Cosmos DB (insert or update if exists)
            container.upsert_item(profile)

            imported += 1
            if imported % 10 == 0:
                print(f"  Progress: {imported}/{len(profiles)} profiles imported...")

        except exceptions.CosmosHttpResponseError as e:
            print(f"  [ERROR] Profile {i} ({profile.get('uid', 'unknown')}): {e.message}")
            failed += 1
        except Exception as e:
            print(f"  [ERROR] Profile {i}: {str(e)}")
            failed += 1

    # Summary
    print("\n" + "="*50)
    print("Import Summary")
    print("="*50)
    print(f"Total profiles: {len(profiles)}")
    print(f"Imported: {imported}")
    print(f"Failed: {failed}")
    print(f"Skipped: {skipped}")
    print("="*50)

    if failed > 0:
        print("\nWarning: Some profiles failed to import")
        print("Check the error messages above")
        return False

    print("\n✓ Import completed successfully!")
    return True


def verify_import(endpoint, key, database_name, container_name, expected_count):
    """Verify the import by counting documents"""
    print("\nVerifying import...")

    client = CosmosClient(endpoint, key)
    database = client.get_database_client(database_name)
    container = database.get_container_client(container_name)

    # Count documents
    query = "SELECT VALUE COUNT(1) FROM c"
    items = list(container.query_items(query=query, enable_cross_partition_query=True))
    actual_count = items[0] if items else 0

    print(f"Expected: {expected_count} profiles")
    print(f"Actual: {actual_count} profiles")

    if actual_count == expected_count:
        print("✓ Verification passed!")
        return True
    else:
        print(f"⚠ Warning: Count mismatch ({actual_count} != {expected_count})")
        return False


def sample_query(endpoint, key, database_name, container_name):
    """Run a sample query to test the import"""
    print("\nRunning sample queries...")

    client = CosmosClient(endpoint, key)
    database = client.get_database_client(database_name)
    container = database.get_container_client(container_name)

    # Get first 3 profiles
    query = "SELECT TOP 3 c.id, c.email, c.display_name, c.city FROM c"
    items = list(container.query_items(query=query, enable_cross_partition_query=True))

    print("\nSample profiles:")
    for item in items:
        print(f"  - {item.get('display_name', 'N/A')} ({item.get('email', 'N/A')}) - {item.get('city', 'N/A')}")

    print("\n✓ Sample queries successful")


def main():
    parser = argparse.ArgumentParser(description='Import Firebase data to Azure Cosmos DB')
    parser.add_argument('--input', '-i', required=True, help='Input JSON file (from Firebase export)')
    parser.add_argument('--verify', action='store_true', help='Verify import after completion')
    parser.add_argument('--sample', action='store_true', help='Run sample queries after import')

    args = parser.parse_args()

    # Check input file
    if not os.path.exists(args.input):
        print(f"Error: Input file not found: {args.input}")
        sys.exit(1)

    # Load configuration
    endpoint, key, database_name, container_name = load_config()

    # Import data
    success = import_profiles(args.input, endpoint, key, database_name, container_name)

    if not success:
        sys.exit(1)

    # Verification
    if args.verify:
        with open(args.input, 'r') as f:
            expected_count = len(json.load(f))
        verify_import(endpoint, key, database_name, container_name, expected_count)

    # Sample queries
    if args.sample:
        sample_query(endpoint, key, database_name, container_name)

    print("\n✓ All done!")
    print("\nNext steps:")
    print("  1. Update backend code to use Cosmos DB")
    print("  2. Migrate vector embeddings to Qdrant/Azure AI Search")
    print("  3. Test the backend locally")


if __name__ == '__main__':
    main()
