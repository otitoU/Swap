#!/bin/bash

# Deploy Backend to Azure Container Apps

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Deploying Backend to Azure Container Apps${NC}"
echo ""

# Load configuration
CONFIG_FILE="../azure-config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Run provision-azure-resources.sh first"
    exit 1
fi

source $CONFIG_FILE

# Configuration
APP_NAME="swap-backend"
IMAGE_NAME="swap-backend:latest"

echo -e "${YELLOW}[1/5] Building Docker image...${NC}"
cd ../../wap-backend-azure
docker build -t $IMAGE_NAME .
echo -e "${GREEN}✓ Docker image built${NC}"
echo ""

echo -e "${YELLOW}[2/5] Tagging image for Azure Container Registry...${NC}"
docker tag $IMAGE_NAME ${ACR_LOGIN_SERVER}/${IMAGE_NAME}
echo -e "${GREEN}✓ Image tagged${NC}"
echo ""

echo -e "${YELLOW}[3/5] Logging in to Azure Container Registry...${NC}"
echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER \
    --username $ACR_USERNAME \
    --password-stdin
echo -e "${GREEN}✓ Logged in to ACR${NC}"
echo ""

echo -e "${YELLOW}[4/5] Pushing image to ACR...${NC}"
docker push ${ACR_LOGIN_SERVER}/${IMAGE_NAME}
echo -e "${GREEN}✓ Image pushed${NC}"
echo ""

echo -e "${YELLOW}[5/5] Deploying to Azure Container Apps...${NC}"

# Create or update container app
az containerapp create \
    --name $APP_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --environment $CONTAINER_ENV \
    --image ${ACR_LOGIN_SERVER}/${IMAGE_NAME} \
    --target-port 8000 \
    --ingress external \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --cpu 1.0 \
    --memory 2.0Gi \
    --min-replicas 0 \
    --max-replicas 10 \
    --env-vars \
        COSMOS_ENDPOINT=$COSMOS_ENDPOINT \
        COSMOS_KEY=$COSMOS_KEY \
        COSMOS_DATABASE=$COSMOS_DATABASE \
        COSMOS_CONTAINER=$COSMOS_CONTAINER \
        STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING \
        REDIS_CONNECTION_STRING=$REDIS_CONNECTION_STRING \
        REDIS_ENABLED=true \
        QDRANT_URL=$QDRANT_URL \
        QDRANT_API_KEY=$QDRANT_API_KEY \
    --query properties.configuration.ingress.fqdn \
    -o tsv \
    2>&1 || \
az containerapp update \
    --name $APP_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --image ${ACR_LOGIN_SERVER}/${IMAGE_NAME} \
    --set-env-vars \
        COSMOS_ENDPOINT=$COSMOS_ENDPOINT \
        COSMOS_KEY=$COSMOS_KEY \
        COSMOS_DATABASE=$COSMOS_DATABASE \
        COSMOS_CONTAINER=$COSMOS_CONTAINER \
        STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING \
        REDIS_CONNECTION_STRING=$REDIS_CONNECTION_STRING \
        REDIS_ENABLED=true \
        QDRANT_URL=$QDRANT_URL \
        QDRANT_API_KEY=$QDRANT_API_KEY

echo -e "${GREEN}✓ Container app deployed${NC}"
echo ""

# Get app URL
BACKEND_URL=$(az containerapp show \
    --name $APP_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --query properties.configuration.ingress.fqdn \
    -o tsv)

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Deployment Complete! ✓            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Backend URL:${NC} https://$BACKEND_URL"
echo ""
echo -e "${YELLOW}Test endpoints:${NC}"
echo "  Health: https://$BACKEND_URL/healthz"
echo "  API Docs: https://$BACKEND_URL/docs"
echo ""
echo -e "${YELLOW}Test it:${NC}"
echo "  curl https://$BACKEND_URL/healthz"
echo ""
echo "Next step: Deploy frontend"
echo "  cd ../deployment && ./deploy-frontend.sh"
