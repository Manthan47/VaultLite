#!/bin/bash

# VaultLite Rate Limiting Test Script
# Usage: ./test_rate_limiting.sh
# Make sure VaultLite is running on localhost:4000

BASE_URL="http://localhost:4000"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 VaultLite Rate Limiting Test Suite${NC}"
echo "===================================="
echo ""

# Check if server is running
echo "Checking if VaultLite is running..."
if curl -s -f "$BASE_URL/api/bootstrap/status" > /dev/null; then
    echo -e "${GREEN}✅ Server is running${NC}"
else
    echo -e "${RED}❌ Server not responding${NC}"
    echo "Please start VaultLite with: mix phx.server"
    exit 1
fi

echo ""

# Test 1: Basic API Rate Limiting
echo -e "${BLUE}📊 Test 1: Basic API Rate Limiting${NC}"
echo "Making 15 rapid requests to /api/bootstrap/status..."
echo -n "Status codes: "

for i in {1..15}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/bootstrap/status")
    if [ "$status" = "429" ]; then
        echo -n -e "${RED}$status${NC} "
    else
        echo -n -e "${GREEN}$status${NC} "
    fi
done

echo ""
echo ""
sleep 2

# Test 2: Login Rate Limiting
echo -e "${BLUE}🔐 Test 2: Login Rate Limiting${NC}"
echo "Testing failed login attempts..."
echo -n "Status codes: "

for i in {1..8}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"identifier":"nonexistent_user","password":"wrong_password"}' \
        "$BASE_URL/api/auth/login")
    
    if [ "$status" = "429" ]; then
        echo -n -e "${RED}$status${NC} "
    elif [ "$status" = "401" ] || [ "$status" = "422" ]; then
        echo -n -e "${YELLOW}$status${NC} "
    else
        echo -n -e "${GREEN}$status${NC} "
    fi
done

echo ""
echo ""
sleep 2

# Test 3: Registration Rate Limiting
echo -e "${BLUE}📝 Test 3: Registration Rate Limiting${NC}"
echo "Testing registration attempts..."
echo -n "Status codes: "

for i in {1..6}; do
    username="testuser${i}_$(date +%s%N)"
    email="test${i}_$(date +%s%N)@example.com"
    
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"user\":{\"username\":\"$username\",\"email\":\"$email\",\"password\":\"StrongPassword123!\"}}" \
        "$BASE_URL/api/auth/register")
    
    if [ "$status" = "429" ]; then
        echo -n -e "${RED}$status${NC} "
    elif [ "$status" = "200" ] || [ "$status" = "201" ]; then
        echo -n -e "${GREEN}$status${NC} "
    else
        echo -n -e "${YELLOW}$status${NC} "
    fi
done

echo ""
echo ""
sleep 2

# Test 4: IP-based Rate Limiting
echo -e "${BLUE}🌐 Test 4: IP-based Rate Limiting${NC}"
echo "Testing with different X-Forwarded-For IPs..."

echo -n "IP 192.168.1.10: "
for i in {1..8}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "X-Forwarded-For: 192.168.1.10" \
        "$BASE_URL/api/bootstrap/status")
    
    if [ "$status" = "429" ]; then
        echo -n -e "${RED}$status${NC} "
    else
        echo -n -e "${GREEN}$status${NC} "
    fi
done
echo ""

echo -n "IP 192.168.1.20: "
for i in {1..8}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "X-Forwarded-For: 192.168.1.20" \
        "$BASE_URL/api/bootstrap/status")
    
    if [ "$status" = "429" ]; then
        echo -n -e "${RED}$status${NC} "
    else
        echo -n -e "${GREEN}$status${NC} "
    fi
done

echo ""
echo ""
sleep 2

# Test 5: Security Pattern Detection
echo -e "${BLUE}🛡️  Test 5: Security Pattern Detection${NC}"
echo "Testing with suspicious User-Agent and patterns..."
echo -n "Status codes: "

# Test with suspicious user agent
status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "User-Agent: sqlmap/1.0" \
    -H "X-Forwarded-For: 10.0.0.100" \
    "$BASE_URL/api/bootstrap/status")

if [ "$status" = "429" ] || [ "$status" = "403" ]; then
    echo -n -e "${RED}$status${NC} "
else
    echo -n -e "${GREEN}$status${NC} "
fi

# Test with injection-like query
status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "User-Agent: sqlmap/1.0" \
    -H "X-Forwarded-For: 10.0.0.100" \
    "$BASE_URL/api/bootstrap/status?id=1%27%20OR%20%271%27=%271")

if [ "$status" = "429" ] || [ "$status" = "403" ]; then
    echo -n -e "${RED}$status${NC} "
else
    echo -n -e "${GREEN}$status${NC} "
fi

# Make normal request from same IP to see if it's now blocked
status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Forwarded-For: 10.0.0.100" \
    "$BASE_URL/api/bootstrap/status")

if [ "$status" = "429" ] || [ "$status" = "403" ]; then
    echo -n -e "${RED}$status${NC} "
else
    echo -n -e "${GREEN}$status${NC} "
fi

echo ""
echo ""

# Summary
echo -e "${BLUE}📋 Summary${NC}"
echo "============"
echo "Rate limiting test completed!"
echo ""
echo "Legend:"
echo -e "${GREEN}200${NC} - Success"
echo -e "${YELLOW}401/422${NC} - Authentication/Validation error"
echo -e "${RED}429${NC} - Rate limited"
echo -e "${RED}403${NC} - Blocked"
echo ""
echo "Check your VaultLite logs for:"
echo "• Rate limit violations"
echo "• Security events"
echo "• IP blocking notifications"
echo ""
echo "To run individual tests:"
echo "• Basic API: for i in {1..10}; do curl -s -o /dev/null -w \"%{http_code} \" $BASE_URL/api/bootstrap/status; done"
echo "• Login: for i in {1..5}; do curl -s -o /dev/null -w \"%{http_code} \" -X POST -H \"Content-Type: application/json\" -d '{\"identifier\":\"test\",\"password\":\"wrong\"}' $BASE_URL/api/auth/login; done"
echo "• With auth: curl -H \"Authorization: Bearer <token>\" $BASE_URL/api/secrets" 