#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Complete HA Cluster Test Suite                      ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"

# Function to get current master
get_master() {
    if vagrant ssh haproxy1 -c "ip addr show enp0s8 2>/dev/null | grep -q 192.168.56.20" 2>/dev/null; then
        echo "haproxy1"
    elif vagrant ssh haproxy2 -c "ip addr show enp0s8 2>/dev/null | grep -q 192.168.56.20" 2>/dev/null; then
        echo "haproxy2"
    else
        echo "none"
    fi
}

# Test 1: Basic functionality
echo -e "\n${YELLOW}[TEST 1] Basic Functionality${NC}"
web1_count=0
web2_count=0
for i in {1..10}; do
    response=$(curl -s http://192.168.56.20/ 2>/dev/null | grep -o "Web Server: web[12]")
    [[ "$response" == *"web1"* ]] && ((web1_count++))
    [[ "$response" == *"web2"* ]] && ((web2_count++))
done
echo -e "  Load Distribution: web1=$web1_count, web2=$web2_count"
if [ $web1_count -gt 0 ] && [ $web2_count -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Round-robin working"
else
    echo -e "  ${RED}✗${NC} Round-robin failed"
fi

# Test 2: Failover
echo -e "\n${YELLOW}[TEST 2] Failover Test${NC}"
INITIAL=$(get_master)
echo -e "  Initial MASTER: $INITIAL"

echo -e "  Stopping $INITIAL..."
vagrant halt $INITIAL > /dev/null 2>&1

echo -e "  Waiting 5 seconds for VRRP..."
sleep 5

NEW=$(get_master)
if [ "$NEW" != "none" ] && [ "$NEW" != "$INITIAL" ]; then
    echo -e "  ${GREEN}✓${NC} Failover successful! New MASTER: $NEW"
else
    echo -e "  ${RED}✗${NC} Failover failed!"
fi

# Test 3: VIP after failover
echo -e "\n${YELLOW}[TEST 3] VIP Availability After Failover${NC}"
if curl -s -o /dev/null -w "%{http_code}" http://192.168.56.20/health 2>/dev/null | grep -q "200"; then
    echo -e "  ${GREEN}✓${NC} VIP still reachable"
else
    echo -e "  ${RED}✗${NC} VIP not reachable"
fi

# Test 4: Restore and preemption
echo -e "\n${YELLOW}[TEST 4] Preemption Test${NC}"
echo -e "  Restoring $INITIAL..."
vagrant up $INITIAL > /dev/null 2>&1

echo -e "  Waiting 15 seconds for preemption..."
sleep 15

FINAL=$(get_master)
if [ "$FINAL" == "$INITIAL" ]; then
    echo -e "  ${GREEN}✓${NC} Preemption successful! $INITIAL reclaimed VIP"
else
    echo -e "  ${RED}✗${NC} Preemption failed. Current MASTER: $FINAL"
    echo -e "  ${YELLOW}  Note: This is common with default Keepalived configs${NC}"
    echo -e "  ${YELLOW}  Solution: Add 'preempt' or use manual VIP reassignment${NC}"
fi

# Test 5: Final health check
echo -e "\n${YELLOW}[TEST 5] Final Cluster Health${NC}"
HEALTHY=0
for ip in 192.168.56.10 192.168.56.11 192.168.56.20; do
    if curl -s -o /dev/null -w "%{http_code}" http://$ip/health 2>/dev/null | grep -q "200"; then
        echo -e "  ${GREEN}✓${NC} $ip - OK"
        ((HEALTHY++))
    else
        echo -e "  ${RED}✗${NC} $ip - FAILED"
    fi
done

echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"
if [ $HEALTHY -eq 3 ] && [ $web1_count -gt 0 ] && [ $web2_count -gt 0 ]; then
    echo -e "${GREEN}✅ CLUSTER IS FULLY OPERATIONAL!${NC}"
else
    echo -e "${YELLOW}⚠️  Cluster has some issues - review output above${NC}"
fi
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"