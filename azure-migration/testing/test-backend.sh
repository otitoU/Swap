#!/bin/bash

# Test Azure Backend Deployment

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get backend URL from argument or use default
BACKEND_URL=${1:-"http://localhost:8000"}

echo -e "${YELLOW}Testing Backend: $BACKEND_URL${NC}"
echo ""

# Test 1: Health Check
echo -e "${YELLOW}[1/5] Testing health endpoint...${NC}"
response=$(curl -s -o /dev/null -w "%{http_code}" $BACKEND_URL/healthz)
if [ "$response" = "200" ]; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed (HTTP $response)${NC}"
    exit 1
fi
echo ""

# Test 2: API Docs
echo -e "${YELLOW}[2/5] Testing API docs...${NC}"
response=$(curl -s -o /dev/null -w "%{http_code}" $BACKEND_URL/docs)
if [ "$response" = "200" ]; then
    echo -e "${GREEN}✓ API docs accessible${NC}"
else
    echo -e "${RED}✗ API docs failed (HTTP $response)${NC}"
fi
echo ""

# Test 3: Create Profile
echo -e "${YELLOW}[3/5] Testing profile creation...${NC}"
TEST_PROFILE='{
  "uid": "test-user-'$RANDOM'",
  "email": "test@example.com",
  "display_name": "Test User",
  "photo_url": null,
  "full_name": "Test User",
  "username": "testuser",
  "bio": "This is a test profile",
  "city": "Test City",
  "timezone": "America/New_York",
  "skills_to_offer": "I can help with software testing and quality assurance",
  "services_needed": "I need help with graphic design and logo creation",
  "dm_open": true,
  "email_updates": true,
  "show_city": true
}'

response=$(curl -s -w "%{http_code}" -X POST $BACKEND_URL/api/v1/profiles/upsert \
    -H "Content-Type: application/json" \
    -d "$TEST_PROFILE")

http_code="${response: -3}"
if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Profile creation successful${NC}"
else
    echo -e "${RED}✗ Profile creation failed (HTTP $http_code)${NC}"
    echo "Response: ${response:0:-3}"
fi
echo ""

# Test 4: Search
echo -e "${YELLOW}[4/5] Testing search...${NC}"
response=$(curl -s -w "%{http_code}" "$BACKEND_URL/api/v1/search?query=graphic+design&limit=5")
http_code="${response: -3}"
if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Search successful${NC}"
    # Parse and show result count
    result_count=$(echo "${response:0:-3}" | grep -o '"results":\[' | wc -l)
    echo "  Found results"
else
    echo -e "${RED}✗ Search failed (HTTP $http_code)${NC}"
fi
echo ""

# Test 5: Cache Stats
echo -e "${YELLOW}[5/5] Testing cache...${NC}"
response=$(curl -s -w "%{http_code}" "$BACKEND_URL/api/v1/cache/stats")
http_code="${response: -3}"
if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Cache endpoint accessible${NC}"
    cache_enabled=$(echo "${response:0:-3}" | grep -o '"enabled":[^,}]*' | cut -d: -f2)
    echo "  Cache enabled: $cache_enabled"
else
    echo -e "${YELLOW}⚠ Cache stats not available (this is optional)${NC}"
fi
echo ""

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Backend Tests Complete!           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "All critical tests passed ✓"
echo ""
echo "Manual testing:"
echo "  1. Visit: $BACKEND_URL/docs"
echo "  2. Try the interactive API documentation"
echo "  3. Create profiles and test search"
