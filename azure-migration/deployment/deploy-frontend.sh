#!/bin/bash

# Deploy Frontend to Azure Static Web Apps

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Deploying Frontend to Azure Static Web Apps${NC}"
echo ""

# Load configuration
CONFIG_FILE="../azure-config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Run provision-azure-resources.sh first"
    exit 1
fi

source $CONFIG_FILE

echo -e "${YELLOW}[1/3] Building Flutter web app...${NC}"
cd ../../swap_frontend
flutter build web --release --web-renderer canvaskit
echo -e "${GREEN}✓ Flutter build complete${NC}"
echo ""

echo -e "${YELLOW}[2/3] Deploying to Azure Static Web Apps...${NC}"

# Install SWA CLI if not present
if ! command -v swa &> /dev/null; then
    echo "Installing Azure Static Web Apps CLI..."
    npm install -g @azure/static-web-apps-cli
fi

# Deploy using SWA CLI
swa deploy \
    --app-location ./build/web \
    --deployment-token $STATIC_WEB_APP_TOKEN \
    --env production

echo -e "${GREEN}✓ Frontend deployed${NC}"
echo ""

echo -e "${YELLOW}[3/3] Retrieving app URL...${NC}"
FRONTEND_URL=$(az staticwebapp show \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --query defaultHostname \
    -o tsv)

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Deployment Complete! ✓            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Frontend URL:${NC} https://$FRONTEND_URL"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Open https://$FRONTEND_URL in browser"
echo "2. Test user registration and login"
echo "3. Create a profile and test search"
echo "4. Configure custom domain (optional):"
echo "   az staticwebapp hostname set \\"
echo "     --name $STATIC_WEB_APP_NAME \\"
echo "     --resource-group $AZURE_RESOURCE_GROUP \\"
echo "     --hostname your-domain.com"
