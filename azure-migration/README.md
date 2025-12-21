# Azure Migration Package

Complete migration toolkit for moving $wap platform from Firebase/Fly.io to Azure.

## 📁 Directory Structure

```
azure-migration/
├── README.md                          # This file
├── provision-azure-resources.sh       # Create all Azure resources
├── azure-config.env                   # Generated configuration (after provisioning)
├── data-migration/
│   ├── export-firebase-data.sh        # Export from Firebase
│   ├── import-to-cosmos.py            # Import to Cosmos DB
│   ├── migrate-storage-to-blob.py     # Migrate storage files
│   └── firebase-export/               # Export output directory
├── deployment/
│   ├── deploy-backend.sh              # Deploy backend to Container Apps
│   └── deploy-frontend.sh             # Deploy frontend to Static Web Apps
├── vector-migration/
│   └── (optional - for Azure AI Search migration)
└── testing/
    └── test-backend.sh                # Backend API tests
```

## 🚀 Quick Start

### Prerequisites
- Azure CLI installed and logged in
- Docker installed
- Python 3.11+
- Flutter SDK
- Firebase CLI (for data export)

### Step 1: Provision Azure Resources (30 minutes)

```bash
cd azure-migration
chmod +x provision-azure-resources.sh
./provision-azure-resources.sh
```

This creates:
- ✅ Resource Group
- ✅ Azure Cosmos DB (NoSQL database)
- ✅ Azure Blob Storage (file storage)
- ✅ Azure Cache for Redis (caching)
- ✅ Azure Container Registry (Docker images)
- ✅ Container Apps Environment (backend hosting)
- ✅ Static Web App (frontend hosting)

Output: `azure-config.env` with all connection strings

### Step 2: Export Firebase Data (30 minutes)

```bash
cd data-migration
chmod +x export-firebase-data.sh
./export-firebase-data.sh
```

Exports:
- All user profiles from Firestore → `firebase-export/profiles.json`
- Storage files → `firebase-export/storage/`

### Step 3: Import to Azure (30 minutes)

```bash
# Import profiles to Cosmos DB
python import-to-cosmos.py --input firebase-export/profiles.json --verify

# Migrate storage files
python migrate-storage-to-blob.py --input firebase-export/storage/ --verify
```

### Step 4: Deploy Backend (30 minutes)

```bash
cd ../deployment
chmod +x deploy-backend.sh
./deploy-backend.sh
```

This:
1. Builds Docker image
2. Pushes to Azure Container Registry
3. Deploys to Azure Container Apps
4. Configures environment variables

Output: Backend URL (e.g., `https://swap-backend.azurecontainerapps.io`)

### Step 5: Test Backend (5 minutes)

```bash
cd ../testing
chmod +x test-backend.sh
./test-backend.sh https://your-backend-url
```

### Step 6: Deploy Frontend (30 minutes)

```bash
cd ../deployment
chmod +x deploy-frontend.sh
./deploy-frontend.sh
```

Output: Frontend URL (e.g., `https://your-app.azurestaticapps.net`)

### Step 7: Done! 🎉

Your app is now running on Azure!

---

## 📋 Detailed Guide

See [AZURE_MIGRATION_GUIDE.md](../AZURE_MIGRATION_GUIDE.md) for detailed instructions.

## 🔧 Configuration

After running `provision-azure-resources.sh`, you'll have an `azure-config.env` file with:

```bash
# Azure Resources
AZURE_RESOURCE_GROUP=swap-rg
COSMOS_ENDPOINT=https://...
COSMOS_KEY=...
STORAGE_CONNECTION_STRING=...
REDIS_CONNECTION_STRING=...
ACR_LOGIN_SERVER=...
STATIC_WEB_APP_URL=...
```

Use these values to configure your backend and frontend.

## 🧪 Testing

### Local Testing (Before Deployment)

```bash
# Backend
cd ../wap-backend-azure
cp ../azure-migration/azure-config.env .env
uvicorn app.main:app --reload

# Test
curl http://localhost:8000/healthz
```

### Production Testing (After Deployment)

```bash
cd azure-migration/testing
./test-backend.sh https://your-backend-url
```

## 💰 Cost Estimate

### Monthly Costs (Serverless/Low Traffic)
- **Cosmos DB** (Serverless): ~$10-20
- **Blob Storage**: ~$1-5
- **Redis Cache** (Basic 250MB): ~$16
- **Container Apps**: ~$0-20 (scale to zero)
- **Static Web Apps**: **Free**
- **Azure AD B2C**: **Free** (<50k users)

**Total: ~$30-60/month** (vs Firebase ~$25-50)

### Cost Optimization Tips
1. Use Cosmos DB serverless mode for low traffic
2. Enable Container Apps scale-to-zero
3. Use Basic tier Redis (upgrade if needed)
4. Enable Blob Storage cool/archive tiers for old data

## 🔄 Rollback Plan

If something goes wrong:

1. **Keep Firebase running** during migration (don't delete)
2. **DNS switch** - only change DNS when Azure is stable
3. **Quick revert** - change DNS back to Fly.io/Netlify

To rollback:
```bash
# Just change DNS back
# Or redeploy to Fly.io
cd ../wap-backend
fly deploy
```

## 📊 Monitoring

### View Logs

```bash
# Backend logs
az containerapp logs show \
    --name swap-backend \
    --resource-group swap-rg \
    --tail 100 \
    --follow

# Frontend logs (in Azure Portal)
# Go to: Static Web Apps → Your App → Logs
```

### Application Insights

Azure automatically creates Application Insights for monitoring:
- Request rates
- Response times
- Error rates
- Custom metrics

Access in Azure Portal: Resource Group → Application Insights

## 🆘 Troubleshooting

### Backend won't start

```bash
# Check logs
az containerapp logs show --name swap-backend --resource-group swap-rg --tail 100

# Common issues:
# 1. Missing environment variables → Check deployment script
# 2. Cosmos DB connection → Verify COSMOS_ENDPOINT and COSMOS_KEY
# 3. Redis connection → Set REDIS_ENABLED=false to disable
```

### Frontend not loading

```bash
# Check Static Web App status
az staticwebapp show --name swap-frontend --resource-group swap-rg

# Redeploy
cd deployment && ./deploy-frontend.sh
```

### Cosmos DB connection timeout

```bash
# Check firewall rules
az cosmosdb firewall-rules list \
    --account-name your-cosmos \
    --resource-group swap-rg

# Add your IP
az cosmosdb firewall-rules create \
    --account-name your-cosmos \
    --resource-group swap-rg \
    --name AllowMyIP \
    --start-ip-address YOUR_IP \
    --end-ip-address YOUR_IP
```

## 🔗 Useful Commands

```bash
# View all resources
az resource list --resource-group swap-rg --output table

# Get backend URL
az containerapp show --name swap-backend --resource-group swap-rg \
    --query properties.configuration.ingress.fqdn -o tsv

# Get frontend URL
az staticwebapp show --name swap-frontend --resource-group swap-rg \
    --query defaultHostname -o tsv

# Delete everything (careful!)
az group delete --name swap-rg --yes
```

## 📚 Additional Resources

- [Azure Cosmos DB Docs](https://docs.microsoft.com/azure/cosmos-db/)
- [Azure Container Apps Docs](https://docs.microsoft.com/azure/container-apps/)
- [Azure Static Web Apps Docs](https://docs.microsoft.com/azure/static-web-apps/)
- [Azure CLI Reference](https://docs.microsoft.com/cli/azure/)

## 📝 Notes

- **Vector Database**: You can keep Qdrant Cloud or migrate to Azure AI Search
- **Authentication**: Azure AD B2C setup requires manual portal configuration
- **Custom Domains**: Configure after initial deployment
- **SSL Certificates**: Automatic with Azure (Let's Encrypt)

---

## ✅ Checklist

### Day 1: Infrastructure
- [ ] Run `provision-azure-resources.sh`
- [ ] Verify `azure-config.env` created
- [ ] Export Firebase data
- [ ] Import to Cosmos DB
- [ ] Migrate storage files

### Day 2: Backend
- [ ] Update backend code (see `wap-backend-azure/`)
- [ ] Test locally
- [ ] Deploy to Azure Container Apps
- [ ] Run backend tests
- [ ] Verify all endpoints work

### Day 3: Frontend
- [ ] Update Flutter app (Azure AD B2C)
- [ ] Build for web
- [ ] Deploy to Static Web Apps
- [ ] Test end-to-end
- [ ] Configure custom domain (optional)

### Post-Migration
- [ ] Monitor for 1 week
- [ ] Verify costs in Azure portal
- [ ] Delete Firebase project (after stable)
- [ ] Cancel Fly.io/Netlify
- [ ] Update documentation

---

**Questions?** Check [AZURE_MIGRATION_GUIDE.md](../AZURE_MIGRATION_GUIDE.md) or open an issue.
