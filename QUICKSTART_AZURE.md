# Azure Migration - Quick Start Guide

**Goal**: Migrate $wap from Firebase/Fly.io to Azure in 2-3 days

---

## 🎯 Overview

You'll migrate:
- **Firebase Firestore** → **Azure Cosmos DB**
- **Firebase Storage** → **Azure Blob Storage**
- **Fly.io** → **Azure Container Apps**
- **Netlify** → **Azure Static Web Apps**
- **Redis (local)** → **Azure Cache for Redis**

Keep: Qdrant Cloud (or optionally migrate to Azure AI Search)

---

## ⚡ Super Quick Start (Command List)

If you just want the commands:

```bash
# Day 1: Provision Azure
cd azure-migration
./provision-azure-resources.sh

# Export Firebase data
cd data-migration
./export-firebase-data.sh
python import-to-cosmos.py --input firebase-export/profiles.json --verify
python migrate-storage-to-blob.py --input firebase-export/storage/ --verify

# Day 2: Deploy Backend
cd ../deployment
./deploy-backend.sh
cd ../testing
./test-backend.sh https://your-backend-url

# Day 3: Deploy Frontend
cd ../deployment
./deploy-frontend.sh

# Done! 🎉
```

---

## 📅 Day-by-Day Plan

### Day 1: Infrastructure & Data (4-6 hours)

#### Morning: Provision Azure Resources

```bash
# Login to Azure
az login

# Run provisioning script
cd azure-migration
chmod +x provision-azure-resources.sh
./provision-azure-resources.sh

# ✓ This creates all Azure resources
# ✓ Saves configuration to azure-config.env
```

**What you get:**
- Cosmos DB for profiles
- Blob Storage for images
- Redis for caching
- Container Registry for Docker images
- Container Apps environment
- Static Web App for frontend

**Cost**: ~$30-60/month

#### Afternoon: Migrate Data

```bash
# Export from Firebase
cd data-migration
chmod +x export-firebase-data.sh
./export-firebase-data.sh

# Import to Cosmos DB
chmod +x import-to-cosmos.py migrate-storage-to-blob.py
python import-to-cosmos.py --input firebase-export/profiles.json --verify --sample

# Migrate files to Blob Storage
python migrate-storage-to-blob.py --input firebase-export/storage/ --verify
```

**What happens:**
- All Firestore profiles → Cosmos DB
- All storage files → Azure Blob Storage
- Verification checks ensure data integrity

---

### Day 2: Backend Deployment (4-6 hours)

#### Review Code Changes

```bash
# See what changed
cd ../wap-backend-azure
cat CHANGES.md

# Key changes:
# - Firebase → Cosmos DB
# - Local Redis → Azure Cache for Redis
# - New: Azure Blob Storage service
```

#### Test Locally (Optional but Recommended)

```bash
# Copy Azure config
cp ../azure-migration/azure-config.env .env

# Install dependencies
pip install -r requirements.txt

# Run locally
uvicorn app.main:app --reload --port 8000

# Test in another terminal
curl http://localhost:8000/healthz
curl http://localhost:8000/docs
```

#### Deploy to Azure

```bash
cd ../azure-migration/deployment
chmod +x deploy-backend.sh deploy-frontend.sh
./deploy-backend.sh

# ✓ Builds Docker image
# ✓ Pushes to Azure Container Registry
# ✓ Deploys to Container Apps
# ✓ Returns backend URL
```

#### Test Production Backend

```bash
cd ../testing
chmod +x test-backend.sh
./test-backend.sh https://your-backend-url-here

# ✓ Tests health endpoint
# ✓ Tests profile creation
# ✓ Tests search
# ✓ Tests cache
```

---

### Day 3: Frontend & Testing (4-6 hours)

#### Update Frontend (Manual - Azure AD B2C)

**Note**: For MVP, you can skip Azure AD B2C and keep Firebase Auth initially.

Full Azure AD B2C setup:
1. Go to https://portal.azure.com
2. Create Azure AD B2C tenant
3. Configure user flows
4. Update Flutter app (see guide)

**Quick option**: Keep Firebase Auth for now, migrate later.

#### Deploy Frontend

```bash
cd ../azure-migration/deployment
./deploy-frontend.sh

# ✓ Builds Flutter web
# ✓ Deploys to Static Web Apps
# ✓ Returns frontend URL
```

#### End-to-End Testing

Open frontend URL in browser:
1. Register new account
2. Create profile
3. Search for skills
4. Test reciprocal matching
5. Upload profile image
6. Edit profile

---

## 🎯 Success Criteria

### Backend (Day 2)
- ✅ `/healthz` returns 200
- ✅ `/docs` loads Swagger UI
- ✅ Can create profiles
- ✅ Search returns results
- ✅ Cache is working (optional)

### Frontend (Day 3)
- ✅ App loads without errors
- ✅ Can register/login
- ✅ Can create profile
- ✅ Search works
- ✅ Images upload

### Performance
- ✅ Health check < 100ms
- ✅ Profile create < 300ms
- ✅ Search < 150ms
- ✅ Similar to Fly.io performance

---

## 🔥 Troubleshooting

### "Cosmos DB connection failed"
```bash
# Check endpoint and key in azure-config.env
cat azure-migration/azure-config.env | grep COSMOS

# Test connection
python -c "
from azure.cosmos import CosmosClient
client = CosmosClient('YOUR_ENDPOINT', 'YOUR_KEY')
print('✓ Connected')
"
```

### "Docker push failed"
```bash
# Re-login to ACR
az acr login --name your-registry-name

# Or use password
source azure-migration/azure-config.env
echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME --password-stdin
```

### "Container App won't start"
```bash
# Check logs
az containerapp logs show \
    --name swap-backend \
    --resource-group swap-rg \
    --tail 100

# Common fixes:
# 1. Check environment variables
# 2. Disable Redis: REDIS_ENABLED=false
# 3. Check Docker image built correctly
```

### "Frontend 404 errors"
```bash
# Check API URL in frontend config
# Update backend URL in Flutter app
# Rebuild and redeploy
```

---

## 💡 Pro Tips

### Parallel Work
- Export Firebase data while Azure provisions (saves time)
- Test locally while data imports
- Build frontend while backend deploys

### Cost Savings
- **Scale to zero**: Container Apps auto-scale to 0 when idle
- **Serverless Cosmos**: Pay only for what you use
- **Free tier**: Static Web Apps free tier is generous
- **Redis**: Can disable if not needed initially

### Monitoring
```bash
# Watch logs in real-time
az containerapp logs show --name swap-backend --resource-group swap-rg --follow

# Check costs
az consumption usage list --start-date 2025-12-01 --end-date 2025-12-31
```

---

## 📞 Need Help?

### Check These First
1. **AZURE_MIGRATION_GUIDE.md** - Detailed instructions
2. **azure-migration/README.md** - Package documentation
3. **wap-backend-azure/CHANGES.md** - Code changes explained

### Common Resources
- [Azure Portal](https://portal.azure.com)
- [Azure CLI Docs](https://docs.microsoft.com/cli/azure/)
- [Cosmos DB Docs](https://docs.microsoft.com/azure/cosmos-db/)

### Debug Checklist
- [ ] Azure CLI installed and logged in
- [ ] `azure-config.env` file exists
- [ ] All environment variables set correctly
- [ ] Firewall rules allow your IP (Cosmos DB)
- [ ] Docker daemon running
- [ ] Enough quota in Azure subscription

---

## 🎉 What's Next?

After migration:
1. **Monitor for 1 week** - Watch logs, check errors
2. **Verify costs** - Azure Portal → Cost Management
3. **Configure custom domain** - For production
4. **Set up Azure AD B2C** - If not done yet
5. **Delete Firebase** - After 30 days of stability
6. **Cancel old services** - Fly.io, Netlify

---

## ⏱️ Time Estimates

| Task | Time | Can Run Parallel? |
|------|------|-------------------|
| Provision Azure | 30 min | - |
| Export Firebase | 30 min | ✅ With imports |
| Import Cosmos | 30 min | ✅ With storage |
| Migrate Storage | 30 min | ✅ With Cosmos |
| Deploy Backend | 30 min | - |
| Test Backend | 15 min | - |
| Deploy Frontend | 30 min | - |
| End-to-End Test | 30 min | - |

**Total sequential**: ~4 hours
**With parallelization**: ~2.5 hours

---

Ready? Let's go! 🚀

```bash
cd azure-migration
./provision-azure-resources.sh
```
