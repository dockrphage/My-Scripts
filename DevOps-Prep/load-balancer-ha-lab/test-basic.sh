#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     HAProxy Cluster - Basic Verification                ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"

# Test Keepalived
echo -e "\n${YELLOW}[1] Keepalived Status${NC}"
for node in haproxy1 haproxy2; do
    status=$(vagrant ssh $node -c "sudo systemctl is-active keepalived" 2>/dev/null | tr -d '\r')
    echo -e "  ${GREEN}✓${NC} $node: $status"
done

# Test VIP ownership
echo -e "\n${YELLOW}[2] VIP Owner${NC}"
if vagrant ssh haproxy1 -c "ip addr show enp0s8 | grep -q 192.168.56.20" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} haproxy1 owns the VIP (MASTER)"
elif vagrant ssh haproxy2 -c "ip addr show enp0s8 | grep -q 192.168.56.20" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} haproxy2 owns the VIP (MASTER)"
fi

# Test health endpoints
echo -e "\n${YELLOW}[3] Health Checks${NC}"
for ip in 192.168.56.10 192.168.56.11 192.168.56.20; do
    if curl -s http://$ip/health 2>/dev/null | grep -q "OK"; then
        echo -e "  ${GREEN}✓${NC} $ip - healthy"
    else
        echo -e "  ${RED}✗${NC} $ip - unhealthy"
    fi
done

# Test load balancing
echo -e "\n${YELLOW}[4] Load Balancing Test (10 requests)${NC}"
w1=0; w2=0
for i in {1..10}; do
    response=$(curl -s http://192.168.56.20/ 2>/dev/null | grep -o "Web Server: web[12]")
    if [[ "$response" == *"web1"* ]]; then ((w1++)); fi
    if [[ "$response" == *"web2"* ]]; then ((w2++)); fi
    sleep 0.3
done
echo -e "  Distribution: web1=$w1, web2=$w2"
[ $w1 -gt 0 ] && [ $w2 -gt 0 ] && echo -e "  ${GREEN}✓ Round-robin working${NC}"

echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"