#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Load Balancer Performance Test                     ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"

# Install Apache Bench if not present
if ! command -v ab &> /dev/null; then
  echo -e "${YELLOW}Installing Apache Bench...${NC}"
  sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils
fi

# Test 1: 1000 requests, 10 concurrent
echo -e "\n${YELLOW}[TEST 1] 1000 requests, 10 concurrent${NC}"
ab -n 1000 -c 10 http://192.168.56.20/ 2>/dev/null | grep -E "(Requests per second|Time per request|Failed requests)"

# Test 2: 5000 requests, 50 concurrent
echo -e "\n${YELLOW}[TEST 2] 5000 requests, 50 concurrent${NC}"
ab -n 5000 -c 50 http://192.168.56.20/ 2>/dev/null | grep -E "(Requests per second|Time per request|Failed requests)"

# Test 3: Different HTTP methods
echo -e "\n${YELLOW}[TEST 3] Health Check Performance${NC}"
ab -n 10000 -c 100 http://192.168.56.20/health 2>/dev/null | grep "Requests per second"

echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"