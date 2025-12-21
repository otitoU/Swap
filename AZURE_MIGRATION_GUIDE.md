# Azure Migration Guide - $wap Platform

## Overview
This guide will walk you through migrating the $wap skill-exchange platform from Firebase/Fly.io to Azure services in 2-3 days.

## Timeline
- **Day 1**: Azure setup + Database migration (4-6 hours)
- **Day 2**: Backend migration + deployment (4-6 hours)
- **Day 3**: Frontend migration + testing (4-6 hours)

---

## Prerequisites

### 1. Azure Account Setup
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login

# Set your subscription (if you have multiple)
az account list --output table
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 2. Required Tools
- Azure CLI (installed above)
- Python 3.11+
- Docker
- Firebase CLI (for data export)
- Flutter SDK

### 3. Environment Variables to Prepare
You'll need these from your current setup:
- Firebase service account JSON
- Qdrant Cloud credentials (if keeping Qdrant)
- Current database data

---

## Day 1: Azure Infrastructure Setup

### Step 1.1: Provision Azure Resources (30 minutes)

Run the infrastructure provisioning script:

```bash
cd azure-migration
chmod +x provision-azure-resources.sh
./provision-azure-resources.sh
```

This creates:
- Resource Group
- Azure Cosmos DB (NoSQL)
- Azure Blob Storage
- Azure Cache for Redis
- Azure Container Registry
- Azure Container Apps Environment
- Azure AD B2C Tenant (manual step required)

**Manual Step**: Azure AD B2C tenant creation requires portal access:
1. Go to https://portal.azure.com
2. Search "Azure AD B2C"
3. Click "Create" → Follow prompts
4. Note down the tenant name and domain

### Step 1.2: Export Firebase Data (30 minutes)

```bash
cd azure-migration/data-migration
chmod +x export-firebase-data.sh
./export-firebase-data.sh
```

This exports:
- All user profiles from Firestore
- Storage files (profile images)
- User authentication data

Output: `firebase-export/` directory with JSON files

### Step 1.3: Import Data to Cosmos DB (30 minutes)

```bash
cd azure-migration/data-migration
python import-to-cosmos.py --input firebase-export/profiles.json
```

This imports all profiles to Cosmos DB with the same structure.

### Step 1.4: Migrate Storage Files (30 minutes)

```bash
cd azure-migration/data-migration
python migrate-storage-to-blob.py --input firebase-export/storage/
```

Uploads all files to Azure Blob Storage with same paths.

### Step 1.5: Rebuild Vector Index (1-2 hours)

**Option A: Keep Qdrant Cloud** (Recommended - easiest)
- No changes needed, keep using Qdrant Cloud
- Update environment variables only

**Option B: Migrate to Azure AI Search**
```bash
cd azure-migration/vector-migration
python migrate-to-azure-search.py
```

### Step 1.6: Configure Azure Cache for Redis (15 minutes)

Redis connection string is output from Step 1.1. Test connection:

```bash
redis-cli -h your-cache.redis.cache.windows.net \
  -p 6380 \
  -a YOUR_ACCESS_KEY \
  --tls \
  PING
```

Expected output: `PONG`

---

## Day 2: Backend Migration

### Step 2.1: Update Backend Code (1 hour)

The updated backend code is in `wap-backend-azure/`. Review changes:

```bash
cd wap-backend-azure
git diff --no-index ../wap-backend/app ./app
```

Key changes:
- `app/services/database.py` → Cosmos DB client
- `app/services/storage.py` → Azure Blob Storage
- `app/services/cache.py` → Azure Cache for Redis
- `app/config.py` → Azure configuration
- `requirements.txt` → Azure SDK packages

### Step 2.2: Test Backend Locally (30 minutes)

```bash
cd wap-backend-azure

# Copy environment template
cp .env.azure.example .env

# Edit .env with your Azure credentials
nano .env

# Run locally with Docker
docker-compose -f docker-compose.azure.yml up
```

Test endpoints:
```bash
# Health check
curl http://localhost:8000/healthz

# Create test profile
curl -X POST http://localhost:8000/api/v1/profiles \
  -H "Content-Type: application/json" \
  -d @test-data/sample-profile.json

# Search test
curl "http://localhost:8000/api/v1/search?query=car+repair&limit=5"
```

### Step 2.3: Build and Push Docker Image (30 minutes)

```bash
cd wap-backend-azure

# Build image
docker build -t swap-backend-azure:latest .

# Tag for Azure Container Registry
docker tag swap-backend-azure:latest \
  swapregistry.azurecr.io/swap-backend:latest

# Login to ACR
az acr login --name swapregistry

# Push image
docker push swapregistry.azurecr.io/swap-backend:latest
```

### Step 2.4: Deploy to Azure Container Apps (30 minutes)

```bash
cd azure-migration/deployment

# Deploy backend
./deploy-backend.sh
```

This creates Container App with:
- Auto-scaling (0-10 replicas)
- HTTPS ingress
- Environment variables from Azure Key Vault
- Health probes

### Step 2.5: Verify Deployment (15 minutes)

```bash
# Get backend URL
BACKEND_URL=$(az containerapp show \
  --name swap-backend \
  --resource-group swap-rg \
  --query properties.configuration.ingress.fqdn \
  -o tsv)

echo "Backend URL: https://$BACKEND_URL"

# Test endpoints
curl https://$BACKEND_URL/healthz
curl https://$BACKEND_URL/docs
```

---

## Day 3: Frontend Migration

### Step 3.1: Update Flutter App for Azure AD B2C (2 hours)

The updated frontend code is in `swap_frontend_azure/`.

Key changes:
- `pubspec.yaml` → Add `msal_flutter` package
- `lib/services/auth_service.dart` → Azure AD B2C authentication
- `lib/services/api_service.dart` → New backend URL + JWT tokens
- `lib/config/azure_config.dart` → Azure configuration

```bash
cd swap_frontend_azure

# Install dependencies
flutter pub get

# Run locally for testing
flutter run -d chrome
```

### Step 3.2: Configure Azure AD B2C (1 hour)

**Manual steps in Azure Portal:**

1. **Create User Flows**:
   - Sign up and sign in
   - Profile editing
   - Password reset

2. **Register Application**:
   - Application type: Public client/native
   - Redirect URIs:
     - `msalYOUR_CLIENT_ID://auth` (mobile)
     - `http://localhost:3000/auth` (local web)
     - `https://your-domain.com/auth` (production web)

3. **Note down**:
   - Tenant name: `your-tenant.onmicrosoft.com`
   - Client ID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
   - Policy names: `B2C_1_signupsignin`, etc.

4. **Update Flutter config**:
   ```dart
   // lib/config/azure_config.dart
   static const String tenantName = 'your-tenant';
   static const String clientId = 'your-client-id';
   ```

### Step 3.3: Build Flutter Web (30 minutes)

```bash
cd swap_frontend_azure

# Build for web
flutter build web --release --web-renderer canvaskit

# Output is in build/web/
```

### Step 3.4: Deploy to Azure Static Web Apps (30 minutes)

```bash
cd azure-migration/deployment

# Deploy frontend
./deploy-frontend.sh
```

This creates Static Web App with:
- Global CDN
- Custom domain support
- Automatic HTTPS
- GitHub Actions integration

### Step 3.5: Configure Custom Domain (30 minutes)

```bash
# Add custom domain
az staticwebapp hostname set \
  --name swap-frontend \
  --resource-group swap-rg \
  --hostname your-domain.com

# Get validation token
az staticwebapp hostname show \
  --name swap-frontend \
  --resource-group swap-rg \
  --hostname your-domain.com
```

Add TXT record to your DNS:
- Name: `@` or `your-domain.com`
- Value: [validation token from above]

### Step 3.6: Update Azure AD B2C Redirect URIs

Add production URL to Azure AD B2C app registration:
- `https://your-domain.com/auth`

---

## Testing & Validation

### End-to-End Testing Checklist

```bash
cd azure-migration/testing
python run-e2e-tests.py
```

Manual testing:
- [ ] User registration (new account)
- [ ] User login (existing account)
- [ ] Profile creation
- [ ] Profile editing
- [ ] Semantic search (find skills)
- [ ] Reciprocal matching
- [ ] Image upload
- [ ] Search caching (check Redis)
- [ ] Mobile app (iOS/Android)

### Performance Validation

```bash
# Run load tests
cd azure-migration/testing
python load-test.py --url https://your-backend-url --users 100
```

Expected performance (similar to Fly.io):
- Health check: < 10ms
- Profile create: < 200ms
- Search (uncached): < 100ms
- Search (cached): < 10ms

---

## Cost Monitoring

### Set up cost alerts:

```bash
# Create budget alert
az consumption budget create \
  --budget-name swap-monthly-budget \
  --resource-group swap-rg \
  --amount 100 \
  --time-grain Monthly \
  --start-date 2025-12-01 \
  --end-date 2026-12-01
```

### Estimated Monthly Costs:
- Azure Cosmos DB (Serverless): ~$10-20
- Azure Blob Storage: ~$1-5
- Azure Cache for Redis (Basic 250MB): ~$16
- Azure Container Apps: ~$0-20 (with scale to zero)
- Azure Static Web Apps: Free tier
- Azure AD B2C: Free (< 50k users)
- **Total: ~$30-60/month**

---

## Rollback Plan

If something goes wrong:

### Option 1: Quick Rollback
Keep Firebase running during migration. Don't delete Firebase resources until Azure is stable for 1 week.

### Option 2: DNS Switch
- Azure deployment is separate URL initially
- Only switch DNS when fully tested
- Can revert DNS immediately if needed

---

## Post-Migration Tasks

### Week 1 After Migration:
- [ ] Monitor Azure Application Insights
- [ ] Check error rates
- [ ] Verify all features working
- [ ] Monitor costs daily

### Week 2-4:
- [ ] Optimize Cosmos DB throughput
- [ ] Enable CDN for Blob Storage
- [ ] Set up Azure Monitor alerts
- [ ] Configure auto-scaling rules

### When Stable (After 1 Month):
- [ ] Delete Firebase project (saves costs)
- [ ] Cancel Fly.io subscription
- [ ] Cancel Netlify subscription
- [ ] Update documentation

---

## Support & Troubleshooting

### Common Issues:

**1. Cosmos DB connection timeout**
```bash
# Check firewall rules
az cosmosdb firewall-rules list \
  --account-name swap-cosmos \
  --resource-group swap-rg

# Add your IP
az cosmosdb firewall-rules create \
  --account-name swap-cosmos \
  --resource-group swap-rg \
  --name AllowMyIP \
  --start-ip-address YOUR_IP \
  --end-ip-address YOUR_IP
```

**2. Container App won't start**
```bash
# Check logs
az containerapp logs show \
  --name swap-backend \
  --resource-group swap-rg \
  --tail 100
```

**3. Azure AD B2C redirect errors**
- Verify redirect URIs match exactly
- Check CORS settings in backend
- Ensure HTTPS (not HTTP)

### Get Help:
- Azure Support: https://portal.azure.com → Support
- Documentation: https://docs.microsoft.com/azure
- Community: https://stackoverflow.com/questions/tagged/azure

---

## Next Steps

1. **Start with Day 1** - Run the infrastructure provisioning script
2. **Export your Firebase data** - This can run overnight if large
3. **Review the updated code** - Familiarize yourself with changes
4. **Test locally first** - Before deploying to Azure
5. **Deploy incrementally** - Backend first, then frontend

**Ready to begin?** Start with:
```bash
cd azure-migration
./provision-azure-resources.sh
```

Good luck! 🚀
