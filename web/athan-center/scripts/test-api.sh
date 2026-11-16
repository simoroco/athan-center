#!/bin/bash

# Athan Center API test script
# Usage: ./test-api.sh [BASE_URL]
# Example: ./test-api.sh http://localhost:7777

BASE_URL=${1:-http://localhost:7777}

echo "🕌 Athan Center API Tests"
echo "================================"
echo "Base URL: $BASE_URL"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test function
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local data=$4
    
    echo -n "Testing $method $endpoint - $description... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method -H "Content-Type: application/json" -d "$data" "$BASE_URL$endpoint")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo -e "${GREEN}✓ OK${NC} (HTTP $http_code)"
        if [ ! -z "$body" ]; then
            echo "  Response: ${body:0:100}..."
        fi
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        echo "  Response: $body"
    fi
    echo ""
}

# Check that the server is reachable
echo "Checking server availability..."
if ! curl -s --connect-timeout 5 "$BASE_URL" > /dev/null; then
    echo -e "${RED}✗ Server not reachable${NC}"
    echo "Make sure the application is started with 'docker-compose up -d'"
    exit 1
fi
echo -e "${GREEN}✓ Server reachable${NC}"
echo ""

# Today's date
TODAY=$(date +%Y-%m-%d)

# Endpoint tests
echo "📋 API endpoint tests"
echo ""

test_endpoint "GET" "/" "Home page"
test_endpoint "GET" "/api/prayers/$TODAY" "Get today's prayers"
test_endpoint "GET" "/api/prayers/next/upcoming" "Get the next prayer"
test_endpoint "GET" "/api/settings" "Get settings"
test_endpoint "GET" "/api/prayer-settings" "Get prayer settings"
test_endpoint "GET" "/api/skip-next" "Check skip next status"
test_endpoint "GET" "/api/audio-files" "List audio files"

echo ""
echo "📝 Write tests (warning: modifies data)"
echo ""

# Ask for confirmation
read -p "Do you want to run the write tests? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    test_endpoint "POST" "/api/skip-next" "Enable skip next"
    test_endpoint "POST" "/api/prayer-settings/Fajr" "Disable Fajr" '{"enabled": false}'
    test_endpoint "POST" "/api/prayer-settings/Fajr" "Re-enable Fajr" '{"enabled": true}'
    test_endpoint "POST" "/api/settings" "Update a setting" '{"key": "test_key", "value": "test_value"}'
fi

echo ""
echo "================================"
echo "Tests completed"
echo ""

# Display some statistics
echo "📊 Additional information"
echo ""

echo -n "Number of prayers today: "
curl -s "$BASE_URL/api/prayers/$TODAY" | grep -o "prayer_name" | wc -l

echo -n "Number of audio files: "
curl -s "$BASE_URL/api/audio-files" | grep -o "\.mp3\|\.wav" | wc -l

echo ""
