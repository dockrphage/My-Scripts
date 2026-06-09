# 🚀 COMPLETE HAPROXY HA CLUSTER RUNBOOK
## *Hands-On Learning & Deep Architecture Exploration*

This runbook will help you deeply understand every component through hands-on experiments.

---

# 📚 TABLE OF CONTENTS
1. [Quick Reference](#quick-reference)
2. [Exploration Labs](#exploration-labs)
3. [Troubleshooting Scenarios](#troubleshooting-scenarios)
4. [Advanced Configurations](#advanced-configurations)
5. [Interview Scenarios](#interview-scenarios)

---

# ⚡ QUICK REFERENCE

## Environment Overview
```bash
# Your cluster details
VIP: 192.168.56.20
HAProxy1: 192.168.56.10 (MASTER - Priority 101)
HAProxy2: 192.168.56.11 (BACKUP - Priority 100)
Web1: 192.168.56.30
Web2: 192.168.56.31

# Default credentials
HAProxy Stats: admin / admin
VM SSH: vagrant / vagrant
```

## Essential Commands Cheat Sheet

```bash
# Cluster Management
vagrant status                    # Check all VMs
vagrant up [vm-name]              # Start VM(s)
vagrant halt [vm-name]            # Stop VM(s)
vagrant reload [vm-name]          # Restart VM
vagrant ssh [vm-name]             # SSH into VM
vagrant provision [vm-name]       # Re-run provisioning

# Health Checks
curl -s http://192.168.56.20/health                    # VIP health
curl -s http://192.168.56.20/ | grep "Web Server:"    # Show which backend
curl -s http://admin:admin@192.168.56.10:8080/stats   # HAProxy stats

# VIP Investigation
vagrant ssh haproxy1 -- "ip addr show enp0s8"         # Check VIP ownership
vagrant ssh haproxy1 -- "ip route show"               # Routing table
arp -a | grep 192.168.56                              # ARP cache on host

# Logs & Debugging
vagrant ssh haproxy1 -- "sudo journalctl -u keepalived -n 50"    # Keepalived logs
vagrant ssh haproxy1 -- "sudo journalctl -u haproxy -n 50"       # HAProxy logs
vagrant ssh web1 -- "sudo tail -f /var/log/nginx/access.log"     # Web access logs
```

---

# 🔬 EXPLORATION LABS

## Lab 1: Understanding VRRP Protocol (30 minutes)

### Objective: See VRRP in action and understand how failover works

```bash
# Terminal 1 - Capture VRRP packets on MASTER
vagrant ssh haproxy1 -- "sudo tcpdump -i enp0s8 vrrp -n -v"

# You'll see output like:
# 22:15:30.123456 IP 192.168.56.10 > 224.0.0.18: VRRPv2, Advertisement, vrid 51, prio 101, authtype simple, intvl 1s, VIP=192.168.56.20

# Terminal 2 - Capture on BACKUP
vagrant ssh haproxy2 -- "sudo tcpdump -i enp0s8 vrrp -n -v"

# Terminal 3 - Watch Keepalived state changes
vagrant ssh haproxy1 -- "sudo journalctl -u keepalived -f"
```

### Experiments to Run:

```bash
# Experiment 1.1: Identify VRRP multicast group
# Question: What multicast IP does VRRP use?
# Answer: 224.0.0.18 (VRRP multicast address)

# Experiment 1.2: Change MASTER priority and observe
vagrant ssh haproxy1 -- "sudo sed -i 's/priority 101/priority 150/' /etc/keepalived/keepalived.conf"
vagrant ssh haproxy1 -- "sudo systemctl restart keepalived"
# What happens? The higher priority doesn't cause preemption immediately

# Experiment 1.3: Understand advertisement interval
# Check current settings
vagrant ssh haproxy1 -- "grep advert_int /etc/keepalived/keepalived.conf"
# Change to 2 seconds and see impact
```

### Learning Questions:
- **Q:** Why is the destination IP 224.0.0.18?
- **A:** Multicast address for VRRP - all VRRP routers listen on this

- **Q:** What's the TTL of VRRP packets?
- **A:** TTL=255 (ensures packets don't route beyond local network)

---

## Lab 2: Load Balancing Algorithms Deep Dive (45 minutes)

### Objective: Understand different load balancing strategies

```bash
# Experiment 2.1: Current round-robin behavior
for i in {1..20}; do
    curl -s http://192.168.56.20/ | grep -o "Web Server: web[12]"
    sleep 0.2
done

# Experiment 2.2: Change to least connections
vagrant ssh haproxy1 -- "sudo sed -i 's/balance roundrobin/balance leastconn/' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy2 -- "sudo sed -i 's/balance roundrobin/balance leastconn/' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"
vagrant ssh haproxy2 -- "sudo systemctl reload haproxy"

# Test with concurrent connections
# Terminal 1: Generate load
for i in {1..100}; do
    curl -s http://192.168.56.20/ > /dev/null &
done

# Terminal 2: Watch distribution
watch -n 1 'curl -s http://192.168.56.20/ | grep "Web Server:"'

# Experiment 2.3: Source IP hash (sticky sessions)
vagrant ssh haproxy1 -- "sudo sed -i 's/balance leastconn/balance source/' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy2 -- "sudo sed -i 's/balance leastconn/balance source/' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"
vagrant ssh haproxy2 -- "sudo systemctl reload haproxy"

# Test sticky behavior - all requests from your IP go to same backend
for i in {1..10}; do
    curl -s http://192.168.56.20/ | grep "Web Server:"
done
```

### Algorithm Comparison Table:

| Algorithm | Command | Use Case | Pros | Cons |
|-----------|---------|----------|------|------|
| Round Robin | `balance roundrobin` | Equal load, similar requests | Simple, fair distribution | No consideration of load |
| Least Connections | `balance leastconn` | Varying request sizes | Routes to least busy server | More overhead |
| Source IP | `balance source` | Session persistence | Sticky sessions | Can cause imbalance |
| URI | `balance uri` | Cache-friendly | Same URI → same server | Hash computation overhead |
| Random | `balance random` | Large server pools | Simple, good distribution | Not deterministic |

---

## Lab 3: Health Check Deep Dive (30 minutes)

### Objective: Understand how HAProxy detects and handles failures

```bash
# Experiment 3.1: Watch health checks in real-time
# Terminal 1: Monitor HAProxy logs
vagrant ssh haproxy1 -- "sudo tail -f /var/log/haproxy.log"

# Terminal 2: Watch backend status via stats
watch -n 1 'curl -s http://admin:admin@192.168.56.10:8080/stats | grep -A5 "http_back"'

# Experiment 3.2: Simulate web server failure
vagrant ssh web1 -- "sudo systemctl stop nginx"

# Observe:
# - HAProxy detects failure after 2 checks (4 seconds)
# - Traffic stops going to web1
# - Check stats page shows web1 as DOWN

# Experiment 3.3: Test health check configuration
# Current config: check inter 2s rise 2 fall 3
# Meaning:
# - Check every 2 seconds
# - Need 2 successful checks to mark UP
# - Need 3 failed checks to mark DOWN

# Modify to be more aggressive
vagrant ssh haproxy1 -- "sudo sed -i 's/check inter 2s rise 2 fall 3/check inter 1s rise 1 fall 2/' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy2 -- "sudo sed -i 's/check inter 2s rise 2 fall 3/check inter 1s rise 1 fall 2/' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"

# Test faster detection
vagrant ssh web1 -- "sudo systemctl stop nginx"
# How long until marked down? ~2 seconds vs 4 seconds before

# Experiment 3.4: Custom health check endpoint
vagrant ssh web1 -- "sudo tee /var/www/html/custom-health > /dev/null <<'EOF'
#!/bin/bash
# Check if disk space is OK
if [ $(df / | awk 'NR==2 {print $5}' | sed 's/%//') -lt 90 ]; then
    echo "OK"
    exit 0
else
    echo "DISK FULL"
    exit 1
fi
EOF"

vagrant ssh web1 -- "sudo chmod +x /var/www/html/custom-health"

# Update HAProxy to use custom check
vagrant ssh haproxy1 -- "sudo sed -i 's/option httpchk GET \/health/option httpchk GET \/custom-health/' /etc/haproxy/haproxy.cfg"
```

### Health Check Parameters Explained:

```yaml
Parameters in HAProxy:
  check              # Enable health checking
  inter 2s           # Check every 2 seconds
  rise 2             # Need 2 successes to mark UP
  fall 3             # Need 3 failures to mark DOWN
  weight 1           # Server weight (for weighted balancing)
  maxconn 1000       # Max connections to this server
  observe layer7     # Observe response codes
```

---

## Lab 4: Network Traffic Analysis (45 minutes)

### Objective: See exactly how traffic flows through the cluster

```bash
# Experiment 4.1: Trace HTTP request path
# Setup tcpdump on all nodes
# Terminal 1 - HAProxy1
vagrant ssh haproxy1 -- "sudo tcpdump -i enp0s8 port 80 -A -n"

# Terminal 2 - Web1
vagrant ssh web1 -- "sudo tcpdump -i enp0s8 port 80 -A -n"

# Terminal 3 - Send request
curl http://192.168.56.20/

# You'll see the request flow: Client -> VIP -> HAProxy -> Web

# Experiment 4.2: See X-Forwarded-For header
# HAProxy adds headers to preserve client IP
vagrant ssh haproxy1 -- "sudo sed -i '/backend http_back/a\    option forwardfor' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy2 -- "sudo sed -i '/backend http_back/a\    option forwardfor' /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"

# Check logs on web server to see real client IP
vagrant ssh web1 -- "sudo tail -f /var/log/nginx/access.log"
# Notice the X-Forwarded-For header

# Experiment 4.3: Measure latency
# Install httping for latency testing
sudo apt-get install -y httping

# Test latency to each component
httping -c 10 -g http://192.168.56.30/  # Direct to web1
httping -c 10 -g http://192.168.56.10/  # Via HAProxy1
httping -c 10 -g http://192.168.56.20/  # Via VIP

# Compare results - what adds latency?
```

### Traffic Flow Diagram:

```
Client (Your Laptop)
    │
    │ HTTP Request to VIP (192.168.56.20)
    ▼
┌─────────────────────────────────────┐
│  Virtual IP (VRRP)                  │
│  - MASTER owns the IP               │
│  - ARP response from current MASTER │
└─────────────────────────────────────┘
    │
    │ Packet forwarded to MASTER
    ▼
┌─────────────────────────────────────┐
│  HAProxy MASTER                     │
│  1. Accepts connection              │
│  2. Applies load balancing logic    │
│  3. Adds X-Forwarded-For header     │
│  4. Selects backend server          │
└─────────────────────────────────────┘
    │
    │ Proxy connection to backend
    ▼
┌─────────────────────────────────────┐
│  Web Server (web1 or web2)          │
│  1. Receives request                │
│  2. Processes HTTP request          │
│  3. Returns response                │
└─────────────────────────────────────┘
    │
    │ Response back through HAProxy
    ▼
    Client receives response
```

---

## Lab 5: Failure Scenarios Simulation (60 minutes)

### Objective: Test system behavior under various failure conditions

```bash
# Create a test script for automated failure testing
cat > failure-test.sh <<'EOF'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_vip() {
    if curl -s -o /dev/null -w "%{http_code}" http://192.168.56.20/health | grep -q "200"; then
        echo -e "${GREEN}✓ VIP reachable${NC}"
        return 0
    else
        echo -e "${RED}✗ VIP NOT reachable${NC}"
        return 1
    fi
}

get_master() {
    if vagrant ssh haproxy1 -c "ip addr show enp0s8 | grep -q 192.168.56.20" 2>/dev/null; then
        echo "haproxy1"
    else
        echo "haproxy2"
    fi
}

echo "=== Failure Scenario Testing ==="

# Scenario 1: MASTER HAProxy service crash
echo -e "\n${YELLOW}[Scenario 1] MASTER HAProxy service crashes${NC}"
MASTER=$(get_master)
echo "  Current MASTER: $MASTER"
echo "  Simulating HAProxy crash on $MASTER..."
vagrant ssh $MASTER -- "sudo systemctl stop haproxy"
sleep 3
test_vip
NEW_MASTER=$(get_master)
echo "  New MASTER: $NEW_MASTER"
vagrant ssh $MASTER -- "sudo systemctl start haproxy"

# Scenario 2: Complete MASTER VM failure
echo -e "\n${YELLOW}[Scenario 2] Complete MASTER VM failure${NC}"
MASTER=$(get_master)
echo "  Halting $MASTER..."
vagrant halt $MASTER
sleep 5
test_vip
NEW_MASTER=$(get_master)
echo "  New MASTER: $NEW_MASTER"
vagrant up $MASTER
sleep 10

# Scenario 3: Backend web server failure
echo -e "\n${YELLOW}[Scenario 3] Backend web server failure${NC}"
echo "  Stopping web1..."
vagrant ssh web1 -- "sudo systemctl stop nginx"
sleep 5
echo "  Testing load balancer response:"
for i in {1..5}; do
    SERVER=$(curl -s http://192.168.56.20/ | grep -o "Web Server: web[12]")
    echo "    Request $i: $SERVER"
done
vagrant ssh web1 -- "sudo systemctl start nginx"

# Scenario 4: Network partition (simulated)
echo -e "\n${YELLOW}[Scenario 4] Network isolation${NC}"
echo -e "  ${RED}Note: Requires manual interface disable${NC}"
echo "  To test: vagrant ssh haproxy1 -- 'sudo ip link set enp0s8 down'"
echo "  Then: vagrant ssh haproxy1 -- 'sudo ip link set enp0s8 up'"

echo -e "\n${GREEN}Testing complete!${NC}"
EOF

chmod +x failure-test.sh
./failure-test.sh
```

### Failure Scenario Analysis:

| Scenario | Expected Behavior | Recovery Time |
|----------|------------------|---------------|
| HAProxy crash | Keepalived detects → Backup takes VIP | ~3 seconds |
| VM power off | VRRP advertisements stop → Failover | ~3 seconds |
| Network disconnect | Same as VM failure | ~3 seconds |
| Backend web down | HAProxy marks down → No traffic sent | ~4 seconds |
| Split-brain | VRRP auth prevents | N/A (prevented) |

---

# 🔧 TROUBLESHOOTING SCENARIOS

## Scenario 1: VIP Not Reachable

```bash
# Diagnostic script
cat > diagnose-vip.sh <<'EOF'
#!/bin/bash
echo "=== VIP Connectivity Diagnostics ==="

echo "1. Check Keepalived service:"
for node in haproxy1 haproxy2; do
    vagrant ssh $node -- "sudo systemctl is-active keepalived"
done

echo -e "\n2. Check VIP ownership:"
vagrant ssh haproxy1 -- "ip addr show enp0s8 | grep 192.168.56.20"
vagrant ssh haproxy2 -- "ip addr show enp0s8 | grep 192.168.56.20"

echo -e "\n3. Check Keepalived configuration:"
vagrant ssh haproxy1 -- "sudo cat /etc/keepalived/keepalived.conf | grep -E '(state|priority|virtual_ipaddress)'"

echo -e "\n4. Check for VRRP packets:"
vagrant ssh haproxy1 -- "sudo timeout 3 tcpdump -i enp0s8 vrrp -c 2 -n 2>/dev/null"

echo -e "\n5. Check firewall rules:"
vagrant ssh haproxy1 -- "sudo iptables -L | grep -i vrrp || echo 'No VRRP blocking rules'"

echo -e "\n6. Check ARP table on host:"
arp -a | grep 192.168.56
EOF

chmod +x diagnose-vip.sh
./diagnose-vip.sh
```

## Scenario 2: HAProxy Not Balancing

```bash
# Debug load balancing issues
cat > debug-lb.sh <<'EOF'
#!/bin/bash
echo "=== Load Balancing Debug ==="

echo "1. Check HAProxy configuration:"
vagrant ssh haproxy1 -- "grep -A10 'backend http_back' /etc/haproxy/haproxy.cfg"

echo -e "\n2. Check backend health status:"
curl -s http://admin:admin@192.168.56.10:8080/stats | grep -E "web[12]" | cut -d',' -f2,18,19

echo -e "\n3. Test direct backend access:"
for backend in 192.168.56.30 192.168.56.31; do
    response=$(curl -s -o /dev/null -w "%{http_code}" http://$backend/health)
    echo "  $backend: HTTP $response"
done

echo -e "\n4. Check HAProxy logs for errors:"
vagrant ssh haproxy1 -- "sudo tail -20 /var/log/haproxy.log | grep -i error"

echo -e "\n5. Verify round-robin manually:"
for i in {1..10}; do
    curl -s http://192.168.56.20/ | grep -o "Web Server: web[12]"
    sleep 0.2
done | sort | uniq -c
EOF

chmod +x debug-lb.sh
./debug-lb.sh
```

---

# 🚀 ADVANCED CONFIGURATIONS

## Configuration 1: URL-Based Routing

```bash
# Configure path-based routing
cat > setup-url-routing.sh <<'EOF'
#!/bin/bash
# Add routing rules to HAProxy

vagrant ssh haproxy1 -- "sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null <<'EOF'

# New frontend rules for path-based routing
use_backend api_servers if { path_beg /api/ }
use_backend static_servers if { path_beg /static/ }
use_backend images_servers if { path_beg /images/ }

backend api_servers
    balance roundrobin
    server web1 192.168.56.30:80 check
    server web2 192.168.56.31:80 check

backend static_servers
    balance roundrobin
    server web1 192.168.56.30:80 check

backend images_servers
    balance roundrobin
    server web2 192.168.56.31:80 check
EOF"

vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"
echo "URL-based routing configured!"
EOF
```

## Configuration 2: Rate Limiting

```bash
# Implement rate limiting per client IP
cat > setup-rate-limit.sh <<'EOF'
#!/bin/bash
# Add rate limiting to HAProxy

vagrant ssh haproxy1 -- "sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null <<'EOF'

# Rate limiting configuration
frontend http_front
    # Track client IP
    stick-table type ip size 1m expire 30s store http_req_rate(10s)
    http-request track-sc0 src
    
    # Limit to 100 requests per 10 seconds
    acl too_fast sc_http_req_rate(0) gt 100
    http-request deny deny_status 429 if too_fast
    
    # Return rate limit header
    http-response set-header X-RateLimit-Limit 100
    http-response set-header X-RateLimit-Interval 10
EOF"

vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"
echo "Rate limiting enabled (100 requests/10 seconds per IP)"
EOF
```

## Configuration 3: SSL Termination

```bash
# Generate self-signed certificate and enable HTTPS
cat > setup-ssl.sh <<'EOF'
#!/bin/bash
# Generate SSL certificate
vagrant ssh haproxy1 -- "sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/haproxy.key \
    -out /etc/ssl/certs/haproxy.crt \
    -subj '/C=US/ST=State/L=City/O=Company/CN=localhost'"

# Combine cert and key for HAProxy
vagrant ssh haproxy1 -- "sudo cat /etc/ssl/certs/haproxy.crt /etc/ssl/private/haproxy.key | sudo tee /etc/ssl/private/haproxy.pem"

# Update HAProxy configuration
vagrant ssh haproxy1 -- "sudo sed -i 's/bind \*:80/bind \*:80\n    bind \*:443 ssl crt \/etc\/ssl\/private\/haproxy.pem/' /etc/haproxy/haproxy.cfg"

# Add redirect HTTP to HTTPS
vagrant ssh haproxy1 -- "sudo sed -i '/frontend http_front/a\    redirect scheme https code 301 if !{ ssl_fc }' /etc/haproxy/haproxy.cfg"

vagrant ssh haproxy1 -- "sudo systemctl reload haproxy"
echo "SSL configured! Test with: curl -k https://192.168.56.20/"
EOF
```

---

# 🎯 INTERVIEW SCENARIO PRACTICE

## Scenario A: "Design a HA solution for a critical e-commerce site"

**Your response framework:**
```yaml
Requirements:
  - 99.99% uptime (less than 1 hour downtime/year)
  - Handle 10,000 concurrent users
  - Geographic distribution (US, EU, Asia)

Proposed Solution:
  Layer 1 - Global:
    - Route53 with health checks for geographic routing
    - 3 regions active-active
  
  Layer 2 - Regional:
    - 2 HAProxy pairs per region
    - Keepalived VRRP for VIP failover
    - Cross-AZ deployment
  
  Layer 3 - Application:
    - Auto-scaling groups for web servers
    - RDS Multi-AZ for database
    - ElastiCache for session storage
  
  Monitoring:
    - CloudWatch alarms on VIP health
    - Dashboards for latency/error rates
    - On-call rotation with PagerDuty
```

## Scenario B: "Troubleshoot: Users report 503 errors"

**Systematic approach:**
```bash
# Step 1: Check if VIP is reachable
curl -I http://192.168.56.20/health

# Step 2: Check HAProxy stats for backend status
curl -s http://admin:admin@192.168.56.10:8080/stats | grep "503"

# Step 3: Check backend health directly
for backend in 192.168.56.30 192.168.56.31; do
    curl -I http://$backend/health
done

# Step 4: Check HAProxy logs
vagrant ssh haproxy1 -- "sudo tail -50 /var/log/haproxy.log | grep -i '503\|error'"

# Step 5: Check web server logs
vagrant ssh web1 -- "sudo tail -50 /var/log/nginx/error.log"

# Step 6: Check system resources
vagrant ssh web1 -- "top -bn1 | head -10"
```

## Scenario C: "How would you monitor this in production?"

**Complete monitoring solution:**
```yaml
Metrics Collection:
  - Prometheus + HAProxy Exporter
  - Node Exporter for system metrics
  - Blackbox Exporter for external probes

Dashboards:
  - Grafana with:
    - Request rate per backend
    - Error rate (5xx vs 2xx)
    - Latency percentiles (p50, p95, p99)
    - Active connections per HAProxy
    - Backend health status

Alerting Rules:
  - Critical (PagerDuty):
    - VIP down for 30 seconds
    - All backends unhealthy
    - HAProxy service down
  - Warning (Slack):
    - High error rate (>1%)
    - High latency (>500ms p95)
    - Single backend down
    - High memory/CPU usage

Logging:
  - ELK Stack (Elasticsearch, Logstash, Kibana)
  - Parse HAProxy logs for request patterns
  - Alert on unusual error spikes
```

---

# 📊 PERFORMANCE BENCHMARKING

## Create Performance Test Suite

```bash
cat > performance-benchmark.sh <<'EOF'
#!/bin/bash
echo "=== Performance Benchmark Suite ==="

# Test 1: Throughput
echo -e "\n[Test 1] Throughput (requests/second)"
for CONCURRENT in 1 10 50 100; do
    echo -n "  Concurrency $CONCURRENT: "
    ab -n 1000 -c $CONCURRENT http://192.168.56.20/ 2>/dev/null | grep "Requests per second" | awk '{print $4}'
done

# Test 2: Latency distribution
echo -e "\n[Test 2] Latency (ms)"
ab -n 1000 -c 10 http://192.168.56.20/ 2>/dev/null | grep -E "(50%|90%|99%)"

# Test 3: Health check overhead
echo -e "\n[Test 3] Health check endpoint performance"
ab -n 10000 -c 100 http://192.168.56.20/health 2>/dev/null | grep "Requests per second"

# Test 4: Failover impact
echo -e "\n[Test 4] Failover impact on latency"
echo "  Starting background load..."
ab -n 10000 -c 10 http://192.168.56.20/ > /dev/null 2>&1 &
AB_PID=$!
sleep 2
echo "  Triggering failover..."
vagrant halt haproxy1
sleep 2
echo "  Checking if VIP failed over..."
curl -s http://192.168.56.20/health > /dev/null && echo "  VIP reachable"
sleep 5
vagrant up haproxy1
kill $AB_PID 2>/dev/null
echo "  Failover test complete"
EOF

chmod +x performance-benchmark.sh
./performance-benchmark.sh
```

---

# 🎓 FINAL LEARNING CHECKLIST

## You Should Now Understand:

### Core Concepts ✅
- [ ] How VRRP elects MASTER and handles failover
- [ ] The difference between L4 and L7 load balancing
- [ ] How health checks work and their parameters
- [ ] The purpose of preemption delay
- [ ] How HAProxy forwards client IP via X-Forwarded-For

### Hands-On Skills ✅
- [ ] Start/stop individual VMs and observe impact
- [ ] Modify HAProxy configuration and reload without downtime
- [ ] Capture and analyze VRRP packets
- [ ] Read HAProxy statistics page
- [ ] Simulate various failure scenarios

### Troubleshooting ✅
- [ ] Diagnose VIP not reachable
- [ ] Debug uneven load distribution
- [ ] Identify why a backend is marked down
- [ ] Check logs for errors
- [ ] Test connectivity between components

### Production Readiness ✅
- [ ] Configure monitoring and alerting
- [ ] Implement rate limiting
- [ ] Set up SSL termination
- [ ] Plan for scaling
- [ ] Document disaster recovery procedures

---

## 🚀 Quick Practice Commands for Tomorrow

```bash
# Morning warm-up (5 minutes)
vagrant status                                    # Check cluster health
./test-1-basic.sh                                # Basic functionality
curl -s http://192.168.56.20/ | grep "Web Server" # See which backend

# Mid-day deep dive (15 minutes)
./test-2-failover.sh                             # Test HA failover
vagrant ssh haproxy1 -- "sudo tcpdump -i enp0s8 vrrp -n" # Watch VRRP

# Evening review (10 minutes)
./test-3-performance.sh                          # Check performance
vagrant ssh haproxy1 -- "sudo journalctl -u keepalived -n 20" # Review logs
```

## 📚 Resources for Further Learning

- **HAProxy Documentation**: https://www.haproxy.com/documentation/
- **Keepalived Docs**: https://www.keepalived.org/documentation.html
- **VRRP RFC 3768**: https://tools.ietf.org/html/rfc3768
- **Load Balancing Algorithms**: https://www.haproxy.com/blog/introduction-to-haproxy-load-balancing-algorithms/

---

**🎉** This runbook has equipped us to a deep, practical understanding of High Availability load balancing.
- ✅ Demonstrate HA concepts in interviews
- ✅ Troubleshoot real-world issues
- ✅ Extend the architecture for production needs
- ✅ Speak confidently about VRRP, HAProxy, and monitoring

Remember: The best interview answer comes from **hands-on experience** - and now you have it! 🔥