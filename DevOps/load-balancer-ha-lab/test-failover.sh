#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     High Availability Failover Test                     ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"

get_master() {
    if vagrant ssh haproxy1 -c "ip addr show enp0s8 | grep -q 192.168.56.20" 2>/dev/null; then
        echo "haproxy1"
    elif vagrant ssh haproxy2 -c "ip addr show enp0s8 | grep -q 192.168.56.20" 2>/dev/null; then
        echo "haproxy2"
    else
        echo "none"
    fi
}

# Initial state
INITIAL=$(get_master)
echo -e "\n${YELLOW}[1] Initial State:${NC} $INITIAL is MASTER"

# Simulate failure
echo -e "\n${YELLOW}[2] Simulating MASTER Failure...${NC}"
echo "  Stopping $INITIAL..."
vagrant halt $INITIAL > /dev/null 2>&1

echo "  Waiting for VRRP failover (5 seconds)..."
sleep 5

NEW=$(get_master)
if [ "$NEW" != "none" ] && [ "$NEW" != "$INITIAL" ]; then
    echo -e "  ${GREEN}✓ Failover successful!${NC} $NEW is now MASTER"
else
    echo -e "  ${RED}✗ Failover failed!${NC}"
fi

# Test VIP after failover
echo -e "\n${YELLOW}[3] VIP Availability After Failover${NC}"
if curl -s http://192.168.56.20/health 2>/dev/null | grep -q "OK"; then
    echo -e "  ${GREEN}✓ VIP still reachable${NC}"
else
    echo -e "  ${RED}✗ VIP not reachable${NC}"
fi

# Restore
echo -e "\n${YELLOW}[4] Restoring Original MASTER...${NC}"
vagrant up $INITIAL > /dev/null 2>&1

echo "  Waiting for preemption (15 seconds)..."
sleep 15

FINAL=$(get_master)
if [ "$FINAL" == "$INITIAL" ]; then
    echo -e "  ${GREEN}✓ Preemption successful!${NC} $INITIAL reclaimed VIP"
else
    echo -e "  ${RED}✗ Preemption failed${NC}"
fi

echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"