#!/bin/bash

# Azure Infrastructure Provisioning Script for $wap Platform
# This script creates all necessary Azure resources for the migration

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Azure Infrastructure Provisioning    ║${NC}"
echo -e "${GREEN}║  $wap Platform Migration               ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo ""

# Configuration Variables
RESOURCE_GROUP="swap-rg"
LOCATION="eastus"
COSMOS_ACCOUNT="swap-cosmos-$(openssl rand -hex 4)"
STORAGE_ACCOUNT="swapstorage$(openssl rand -hex 4)"
REDIS_NAME="swap-redis-$(openssl rand -hex 4)"
CONTAINER_REGISTRY="swapregistry$(openssl rand -hex 4)"
CONTAINER_ENV="swap-env"
STATIC_WEB_APP="swap-frontend"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
echo -e "${YELLOW}Checking Azure login status...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in. Please login to Azure:${NC}"
    az login
fi

# Display current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Using subscription: ${SUBSCRIPTION_NAME}${NC}"
echo -e "${GREEN}✓ Subscription ID: ${SUBSCRIPTION_ID}${NC}"
echo ""

read -p "Is this the correct subscription? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please set the correct subscription:"
    echo "  az account list --output table"
    echo "  az account set --subscription YOUR_SUBSCRIPTION_ID"
    exit 1
fi

echo -e "${YELLOW}Creating resources in location: ${LOCATION}${NC}"
echo ""

# Step 1: Create Resource Group
echo -e "${YELLOW}[1/9] Creating Resource Group...${NC}"
if az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo -e "${GREEN}✓ Resource group already exists${NC}"
else
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --tags Environment=Production Project=SwapPlatform
    echo -e "${GREEN}✓ Resource group created${NC}"
fi
echo ""

# Step 2: Create Azure Cosmos DB
echo -e "${YELLOW}[2/9] Creating Azure Cosmos DB (NoSQL)...${NC}"
echo "This may take 3-5 minutes..."
az cosmosdb create \
    --name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --locations regionName=$LOCATION failoverPriority=0 isZoneRedundant=False \
    --capabilities EnableServerless \
    --default-consistency-level Session \
    --enable-free-tier false \
    --tags Environment=Production

echo -e "${GREEN}✓ Cosmos DB created${NC}"

# Create database and container
echo "Creating database and container..."
az cosmosdb sql database create \
    --account-name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name swap_db

az cosmosdb sql container create \
    --account-name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --database-name swap_db \
    --name profiles \
    --partition-key-path "/uid" \
    --throughput 400

echo -e "${GREEN}✓ Database and container created${NC}"
echo ""

# Step 3: Create Azure Blob Storage
echo -e "${YELLOW}[3/9] Creating Azure Blob Storage...${NC}"
az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access true \
    --tags Environment=Production

echo -e "${GREEN}✓ Storage account created${NC}"

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --account-name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query "[0].value" -o tsv)

# Create blob containers
az storage container create \
    --name profile-images \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY \
    --public-access blob

az storage container create \
    --name assets \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY \
    --public-access blob

echo -e "${GREEN}✓ Blob containers created${NC}"
echo ""

# Step 4: Create Azure Cache for Redis
echo -e "${YELLOW}[4/9] Creating Azure Cache for Redis...${NC}"
echo "This may take 5-10 minutes..."
az redis create \
    --name $REDIS_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Basic \
    --vm-size c0 \
    --enable-non-ssl-port false \
    --tags Environment=Production

echo -e "${GREEN}✓ Redis cache created${NC}"
echo ""

# Step 5: Create Azure Container Registry
echo -e "${YELLOW}[5/9] Creating Azure Container Registry...${NC}"
az acr create \
    --name $CONTAINER_REGISTRY \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Basic \
    --admin-enabled true \
    --tags Environment=Production

echo -e "${GREEN}✓ Container registry created${NC}"
echo ""

# Step 6: Create Container Apps Environment
echo -e "${YELLOW}[6/9] Creating Container Apps Environment...${NC}"
# Register provider if needed
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

# Create Log Analytics workspace
LOG_WORKSPACE="swap-logs-$(openssl rand -hex 4)"
az monitor log-analytics workspace create \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_WORKSPACE \
    --location $LOCATION

LOG_WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_WORKSPACE \
    --query customerId -o tsv)

LOG_WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_WORKSPACE \
    --query primarySharedKey -o tsv)

# Create Container Apps environment
az containerapp env create \
    --name $CONTAINER_ENV \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --logs-workspace-id $LOG_WORKSPACE_ID \
    --logs-workspace-key $LOG_WORKSPACE_KEY

echo -e "${GREEN}✓ Container Apps environment created${NC}"
echo ""

# Step 7: Create Azure Static Web App
echo -e "${YELLOW}[7/9] Creating Azure Static Web App...${NC}"
az staticwebapp create \
    --name $STATIC_WEB_APP \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Free \
    --tags Environment=Production

echo -e "${GREEN}✓ Static Web App created${NC}"
echo ""

# Step 8: Get connection strings and credentials
echo -e "${YELLOW}[8/9] Retrieving connection strings...${NC}"

# Cosmos DB
COSMOS_ENDPOINT=$(az cosmosdb show \
    --name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query documentEndpoint -o tsv)

COSMOS_KEY=$(az cosmosdb keys list \
    --name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query primaryMasterKey -o tsv)

# Storage
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query connectionString -o tsv)

# Redis
REDIS_HOSTNAME=$(az redis show \
    --name $REDIS_NAME \
    --resource-group $RESOURCE_GROUP \
    --query hostName -o tsv)

REDIS_KEY=$(az redis list-keys \
    --name $REDIS_NAME \
    --resource-group $RESOURCE_GROUP \
    --query primaryKey -o tsv)

REDIS_CONNECTION_STRING="rediss://:${REDIS_KEY}@${REDIS_HOSTNAME}:6380"

# Container Registry
ACR_LOGIN_SERVER=$(az acr show \
    --name $CONTAINER_REGISTRY \
    --resource-group $RESOURCE_GROUP \
    --query loginServer -o tsv)

ACR_USERNAME=$(az acr credential show \
    --name $CONTAINER_REGISTRY \
    --resource-group $RESOURCE_GROUP \
    --query username -o tsv)

ACR_PASSWORD=$(az acr credential show \
    --name $CONTAINER_REGISTRY \
    --resource-group $RESOURCE_GROUP \
    --query "passwords[0].value" -o tsv)

# Static Web App
STATIC_WEB_APP_URL=$(az staticwebapp show \
    --name $STATIC_WEB_APP \
    --resource-group $RESOURCE_GROUP \
    --query defaultHostname -o tsv)

STATIC_WEB_APP_TOKEN=$(az staticwebapp secrets list \
    --name $STATIC_WEB_APP \
    --resource-group $RESOURCE_GROUP \
    --query properties.apiKey -o tsv)

echo -e "${GREEN}✓ Connection strings retrieved${NC}"
echo ""

# Step 9: Save configuration to file
echo -e "${YELLOW}[9/9] Saving configuration...${NC}"

CONFIG_FILE="azure-config.env"
cat > $CONFIG_FILE << EOF
# Azure Resource Configuration
# Generated: $(date)

# Resource Group
AZURE_RESOURCE_GROUP=$RESOURCE_GROUP
AZURE_LOCATION=$LOCATION

# Cosmos DB
COSMOS_ENDPOINT=$COSMOS_ENDPOINT
COSMOS_KEY=$COSMOS_KEY
COSMOS_DATABASE=swap_db
COSMOS_CONTAINER=profiles

# Azure Blob Storage
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT
STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING

# Azure Cache for Redis
REDIS_HOSTNAME=$REDIS_HOSTNAME
REDIS_PORT=6380
REDIS_PASSWORD=$REDIS_KEY
REDIS_CONNECTION_STRING=$REDIS_CONNECTION_STRING
REDIS_USE_SSL=true

# Azure Container Registry
ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER
ACR_USERNAME=$ACR_USERNAME
ACR_PASSWORD=$ACR_PASSWORD

# Container Apps Environment
CONTAINER_ENV=$CONTAINER_ENV

# Static Web App
STATIC_WEB_APP_NAME=$STATIC_WEB_APP
STATIC_WEB_APP_URL=https://$STATIC_WEB_APP_URL
STATIC_WEB_APP_TOKEN=$STATIC_WEB_APP_TOKEN

# Notes:
# - Keep this file secure (added to .gitignore)
# - Use these values to configure your backend and frontend
# - Azure AD B2C must be configured manually in the portal
EOF

echo -e "${GREEN}✓ Configuration saved to: ${CONFIG_FILE}${NC}"
echo ""

# Summary
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Provisioning Complete! ✓           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Resources Created:${NC}"
echo "  ✓ Resource Group: $RESOURCE_GROUP"
echo "  ✓ Cosmos DB: $COSMOS_ACCOUNT"
echo "  ✓ Blob Storage: $STORAGE_ACCOUNT"
echo "  ✓ Redis Cache: $REDIS_NAME"
echo "  ✓ Container Registry: $CONTAINER_REGISTRY"
echo "  ✓ Container Apps Env: $CONTAINER_ENV"
echo "  ✓ Static Web App: $STATIC_WEB_APP"
echo ""
echo -e "${YELLOW}Configuration File:${NC} $CONFIG_FILE"
echo ""
echo -e "${YELLOW}Important Next Steps:${NC}"
echo "1. Review the configuration file: cat $CONFIG_FILE"
echo "2. Set up Azure AD B2C (requires manual portal configuration)"
echo "3. Export Firebase data: cd data-migration && ./export-firebase-data.sh"
echo "4. Import data to Cosmos DB: python import-to-cosmos.py"
echo ""
echo -e "${YELLOW}Manual Configuration Required:${NC}"
echo "Azure AD B2C Tenant:"
echo "  1. Go to: https://portal.azure.com"
echo "  2. Search for 'Azure AD B2C'"
echo "  3. Create tenant and note down:"
echo "     - Tenant name"
echo "     - Client ID"
echo "     - Policy names"
echo ""
echo -e "${GREEN}Estimated Monthly Cost: \$30-60${NC}"
echo ""
echo "For detailed instructions, see: AZURE_MIGRATION_GUIDE.md"
