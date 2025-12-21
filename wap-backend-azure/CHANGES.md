# Backend Changes for Azure Migration

## Files Modified

### 1. **requirements.txt**
- Added Azure SDK packages:
  - `azure-cosmos==4.5.1` - Cosmos DB client
  - `azure-storage-blob==12.19.0` - Blob Storage client
  - `azure-identity==1.15.0` - Azure authentication
  - `msal==1.26.0` - Microsoft Authentication Library
- Removed: `firebase-admin` (no longer needed)

### 2. **app/config.py**
- Added Azure configuration:
  - Cosmos DB settings (`cosmos_endpoint`, `cosmos_key`, etc.)
  - Azure Blob Storage settings
  - Azure Cache for Redis settings (with SSL support)
  - Azure AD B2C settings
- Removed: Firebase-specific settings

### 3. **app/cosmos_db.py** (NEW - replaces `firebase_db.py`)
- Azure Cosmos DB service implementation
- Same interface as Firebase service for easy migration
- Methods:
  - `create_profile()`, `get_profile()`, `update_profile()`
  - `upsert_profile()`, `delete_profile()`, `list_profiles()`
  - `get_profile_by_email()`
  - Bonus: `get_profiles_by_city()` (leverages SQL queries)

### 4. **app/azure_storage.py** (NEW)
- Azure Blob Storage service
- Methods:
  - `upload_file()` - Upload files with content type
  - `download_file()` - Download files
  - `delete_file()` - Delete files
  - `get_file_url()` - Get public URL
  - `list_files()` - List blobs with optional prefix

### 5. **app/cache.py** (UPDATED)
- Updated to support Azure Cache for Redis
- Added SSL support (required by Azure)
- Connection string support
- Graceful fallback if cache unavailable
- Same interface as before - no changes needed in router code

### 6. **app/routers/profiles.py** (UPDATE REQUIRED)
Change imports:
```python
# OLD
from app.firebase_db import get_firebase_service

# NEW
from app.cosmos_db import get_cosmos_service
```

Change function calls:
```python
# OLD
firebase_service = get_firebase_service()

# NEW
cosmos_service = get_cosmos_service()
```

**The rest of the code remains the same!** The Cosmos DB service has the same interface as the Firebase service.

### 7. **app/routers/search.py** (NO CHANGES)
- No changes needed
- Qdrant client and embeddings remain the same
- Cache service interface unchanged

### 8. **app/routers/swaps.py** (NO CHANGES)
- No changes needed

### 9. Files to Copy As-Is
These files don't need changes - just copy from `wap-backend/`:
- `app/__init__.py`
- `app/main.py`
- `app/schemas.py`
- `app/models.py`
- `app/embeddings.py`
- `app/qdrant_client.py`
- `app/matching.py`
- `app/routers/__init__.py`
- `app/routers/search.py`
- `app/routers/swaps.py`
- `Dockerfile`
- `docker-compose.yml` (for local development)
- `.dockerignore`
- `pyproject.toml`

## Environment Variables Required

Create a `.env` file with these Azure-specific variables:

```bash
# Azure Cosmos DB
COSMOS_ENDPOINT=https://your-cosmos.documents.azure.com:443/
COSMOS_KEY=your-cosmos-key
COSMOS_DATABASE=swap_db
COSMOS_CONTAINER=profiles

# Azure Blob Storage
STORAGE_ACCOUNT_NAME=yourstorageaccount
STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=...

# Azure Cache for Redis
REDIS_ENABLED=true
REDIS_HOSTNAME=your-cache.redis.cache.windows.net
REDIS_PORT=6380
REDIS_PASSWORD=your-redis-key
REDIS_USE_SSL=true

# Or use connection string (alternative to hostname/password)
# REDIS_CONNECTION_STRING=rediss://:password@your-cache.redis.cache.windows.net:6380

# Qdrant (can keep Qdrant Cloud)
QDRANT_URL=https://your-qdrant-instance.com
QDRANT_API_KEY=your-qdrant-api-key
QDRANT_COLLECTION=swap_users

# Azure AD B2C (optional - for future auth)
AZURE_AD_TENANT_ID=your-tenant-id
AZURE_AD_CLIENT_ID=your-client-id
AZURE_AD_CLIENT_SECRET=your-client-secret

# App
APP_NAME=$wap
DEBUG=false
```

## Migration Steps

1. **Copy unchanged files** from `wap-backend/` to `wap-backend-azure/`
2. **Update** `app/routers/profiles.py` to use Cosmos DB
3. **Test locally** with Azure resources
4. **Build and deploy** to Azure Container Apps

## Testing Locally

```bash
cd wap-backend-azure

# Install dependencies
pip install -r requirements.txt

# Set up environment variables (use azure-config.env from provisioning)
cp ../azure-migration/azure-config.env .env
# Edit .env and add any missing values

# Run locally
uvicorn app.main:app --reload --port 8000

# Test endpoints
curl http://localhost:8000/healthz
curl http://localhost:8000/docs
```

## Key Differences from Firebase

| Feature | Firebase | Azure Cosmos DB |
|---------|----------|-----------------|
| **Document ID** | Any string | Requires `id` field + partition key |
| **Timestamps** | Server-side | Client-side (we set them) |
| **Queries** | Limited filters | Full SQL-like queries |
| **Authentication** | Built-in | Separate service (AD B2C) |
| **Real-time** | Built-in listeners | Change feed (different API) |
| **Cost Model** | Pay per operation | Provisioned/serverless throughput |

## Compatibility Notes

The services are designed to be **drop-in replacements**:
- Same method signatures
- Same return types
- Same error handling patterns

This makes migration seamless - most router code doesn't need changes!
