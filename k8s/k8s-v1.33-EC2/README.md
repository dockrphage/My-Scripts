# 🚀 Enhanced Kubernetes Upgrade Plan: v1.33 → v1.35.3
## DevOps Interview-Focused Implementation with EKS Best Practices

---

## 📋 Executive Summary for Interview

> **Key Differentiators:** This plan incorporates **production-grade practices** including canary deployments, add-on-first upgrades, validation gates, and zero-downtime strategies. Unlike basic upgrades, this approach treats Kubernetes clusters as **critical infrastructure** requiring staged, verifiable changes.

---

## 🎯 Phase 0: Pre-Upgrade Assessment (The "Why" - Interview Q&A)

### Why This Phase Matters in Production

```bash
# Interview Talking Points:
# - "We never upgrade without a baseline"
# - "Documentation is your rollback blueprint"  
# - "Upgrade insights prevent surprises"

cat << 'EOF' > pre-upgrade-assessment.sh
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p upgrade-artifacts/${TIMESTAMP}
cd upgrade-artifacts/${TIMESTAMP}

echo "📸 Capturing Cluster State - ${TIMESTAMP}"

# 1. Business Impact Assessment
kubectl top nodes > node-resources.txt
kubectl top pods --all-namespaces > pod-resources.txt

# 2. Critical Workload Inventory
kubectl get deployments --all-namespaces -o wide > deployments.txt
kubectl get statefulsets --all-namespaces > statefulsets.txt
kubectl get daemonsets --all-namespaces > daemonsets.txt

# 3. Configuration Backup (Rollback Ready)
kubectl get all --all-namespaces -o yaml > full-cluster-state.yaml
kubectl get pv,pvc --all-namespaces -o yaml > storage-state.yaml
kubectl get ingress --all-namespaces -o yaml > ingress-state.yaml

# 4. Add-on Version Audit (Critical for EKS-style upgrade)
echo "Add-on Versions:" > addon-versions.txt
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}' >> addon-versions.txt
kubectl get daemonset kube-proxy -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}' >> addon-versions.txt

# 5. etcd Backup (Absolute Last Resort)
sudo ETCDCTL_API=3 etcdctl snapshot save etcd-snapshot-${TIMESTAMP}.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key 2>/dev/null || echo "etcd backup skipped"

echo "✅ Assessment complete. Artifacts saved to upgrade-artifacts/${TIMESTAMP}"
EOF

chmod +x pre-upgrade-assessment.sh
./pre-upgrade-assessment.sh
```

### Interview Question: "How do you know if the cluster is ready for upgrade?"

**Answer:** Run this health scoring script:

```bash
cat << 'EOF' > cluster-readiness-score.sh
#!/bin/bash
# Returns 0-100 readiness score

SCORE=100

# Check 1: All nodes Ready (-20 per unhealthy node)
UNHEALTHY_NODES=$(kubectl get nodes | grep -v Ready | grep -v NAME | wc -l)
SCORE=$((SCORE - (UNHEALTHY_NODES * 20)))

# Check 2: No crashlooping pods (-10 each)
CRASHING=$(kubectl get pods --all-namespaces | grep -E "CrashLoopBackOff|Error" | wc -l)
SCORE=$((SCORE - (CRASHING * 10)))

# Check 3: API server responsive (-50 if not)
kubectl cluster-info > /dev/null 2>&1 || SCORE=$((SCORE - 50))

# Check 4: Sufficient resources for upgrade
NODE_COUNT=$(kubectl get nodes | grep -v NAME | wc -l)
if [ $NODE_COUNT -lt 2 ]; then
  SCORE=$((SCORE - 30))
  echo "⚠️  Single node cluster - upgrade will cause downtime"
fi

echo "Readiness Score: $SCORE/100"
if [ $SCORE -lt 70 ]; then
  echo "❌ Cluster NOT ready for upgrade"
  exit 1
else
  echo "✅ Cluster ready for upgrade"
  exit 0
fi
EOF

chmod +x cluster-readiness-score.sh
./cluster-readiness-score.sh
```

---

## 🎯 Phase 1: Canary Deployment (Zero-Downtine Testing)

### Interview Question: "How do you validate no downtime during upgrade?"

**Answer:** Deploy a canary workload with continuous monitoring BEFORE starting any upgrade.

```bash
cat << 'EOF' > deploy-canary.sh
#!/bin/bash
echo "🦜 Deploying Canary Workload for Downtime Detection"

# Deploy the canary application
cat << 'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: upgrade-canary
  namespace: default
spec:
  replicas: 3  # 3 replicas ensures high availability during node drains
  selector:
    matchLabels:
      app: upgrade-canary
  template:
    metadata:
      labels:
        app: upgrade-canary
    spec:
      affinity:
        podAntiAffinity:  # Spread across different nodes
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - upgrade-canary
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: upgrade-canary
spec:
  selector:
    app: upgrade-canary
  ports:
  - port: 80
    targetPort: 80
YAML

# Wait for canary to be ready
echo "Waiting for canary deployment..."
kubectl wait --for=condition=available deployment/upgrade-canary --timeout=60s

echo "✅ Canary deployed - 3 replicas spread across nodes"
kubectl get pods -l app=upgrade-canary -o wide
EOF

chmod +x deploy-canary.sh
./deploy-canary.sh
```

### Continuous Monitoring Script (Run in separate terminal)

```bash
cat << 'EOF' > continuous-monitor.sh
#!/bin/bash
# Production-grade monitoring during upgrade

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "📊 Starting Continuous Cluster Monitor"
echo "========================================="

# Function to check canary health
check_canary() {
    local ready=$(kubectl get pods -l app=upgrade-canary \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [[ "$ready" == *"True"* ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get node status
get_node_status() {
    kubectl get nodes --no-headers | awk '{print $2}' | grep -v Ready | wc -l
}

# Main monitoring loop
FAILURE_COUNT=0
while true; do
    TIMESTAMP=$(date '+%H:%M:%S')
    
    # Check canary
    if check_canary; then
        echo -e "[$TIMESTAMP] ${GREEN}✅ Canary HEALTHY${NC}"
        FAILURE_COUNT=0
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo -e "[$TIMESTAMP] ${RED}❌ Canary UNHEALTHY (Failures: $FAILURE_COUNT)${NC}"
        
        if [ $FAILURE_COUNT -ge 3 ]; then
            echo -e "${RED}🚨 ALERT: Continuous failure detected! Possible downtime!${NC}"
        fi
    fi
    
    # Show node status
    NODE_READY=$(kubectl get nodes --no-headers | grep -c Ready)
    NODE_TOTAL=$(kubectl get nodes --no-headers | wc -l)
    echo "   Nodes Ready: $NODE_READY/$NODE_TOTAL"
    
    sleep 5
done
EOF

chmod +x continuous-monitor.sh
```

---

## 🎯 Phase 2: Add-on Upgrade (The Most Missed Step)

### Interview Question: "Why upgrade add-ons before the control plane?"

**Answer:** Because add-ons like CoreDNS and kube-proxy must be compatible with the NEW version but run on the OLD nodes during the upgrade window.

```bash
cat << 'EOF' > upgrade-addons-first.sh
#!/bin/bash
set -e

echo "🔧 Phase 2: Add-on Pre-Upgrade (EKS Best Practice)"

# Backup current add-ons
kubectl get deployment coredns -n kube-system -o yaml > coredns-backup.yaml
kubectl get daemonset kube-proxy -n kube-system -o yaml > kube-proxy-backup.yaml

# Check current compatibility
echo "Current add-on versions:"
kubectl get deployment coredns -n kube-system -o jsonpath='CoreDNS: {.spec.template.spec.containers[0].image}\n'
kubectl get daemonset kube-proxy -n kube-system -o jsonpath='kube-proxy: {.spec.template.spec.containers[0].image}\n'

# Critical: CoreDNS upgrade (must be compatible with both old and new k8s)
echo "Upgrading CoreDNS to 1.11.3 (v1.35 compatible)..."
kubectl set image deployment/coredns -n kube-system \
  coredns=registry.k8s.io/coredns/coredns:v1.11.3

# Wait for CoreDNS rollout
kubectl rollout status deployment/coredns -n kube-system --timeout=120s

# kube-proxy upgrade (must match target version)
echo "Upgrading kube-proxy to v1.35.3..."
kubectl set image daemonset/kube-proxy -n kube-system \
  kube-proxy=registry.k8s.io/kube-proxy:v1.35.3

# Wait for kube-proxy rollout
kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=120s

# Verify add-ons are healthy
echo "Add-on health check:"
kubectl get pods -n kube-system | grep -E 'coredns|kube-proxy'

echo "✅ Add-ons upgraded and verified compatible"
EOF

chmod +x upgrade-addons-first.sh
./upgrade-addons-first.sh
```

---

## 🎯 Phase 3: Control Plane Upgrade (With Validation Gates)

### Interview Question: "What are your validation gates before upgrading control plane?"

**Answer:** Pre-flight checks that MUST pass before proceeding.

```bash
cat << 'EOF' > upgrade-control-plane-gated.sh
#!/bin/bash
set -e

echo "🎯 Phase 3: Control Plane Upgrade with Validation Gates"

# GATE 1: Canary Health Check
echo "Gate 1/5: Verifying canary workload..."
CANARY_PODS=$(kubectl get pods -l app=upgrade-canary -o jsonpath='{.items[*].status.phase}')
if [[ ! "$CANARY_PODS" == *"Running"* ]]; then
    echo "❌ Gate 1 FAILED: Canary not healthy"
    exit 1
fi
echo "✅ Gate 1 passed: Canary healthy"

# GATE 2: Add-on Compatibility Check
echo "Gate 2/5: Verifying add-on versions..."
COREDNS_VER=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ ! "$COREDNS_VER" == *"v1.11"* ]]; then
    echo "⚠️  Warning: CoreDNS version may not be compatible"
fi
echo "✅ Gate 2 passed: Add-ons verified"

# GATE 3: Resource Availability
echo "Gate 3/5: Checking resource availability..."
FREE_MEM=$(free -m | awk 'NR==2{print $7}')
if [ $FREE_MEM -lt 1024 ]; then
    echo "⚠️  Low memory available: ${FREE_MEM}MB"
fi
echo "✅ Gate 3 passed: Resources adequate"

# GATE 4: kubeadm Upgrade Plan
echo "Gate 4/5: Validating upgrade plan..."
sudo kubeadm upgrade plan

# GATE 5: Manual Confirmation for Production
echo "Gate 5/5: Manual approval required"
read -p "Proceed with control plane upgrade to v1.35.3? (yes/no): " APPROVAL
if [ "$APPROVAL" != "yes" ]; then
    echo "Upgrade cancelled by operator"
    exit 0
fi

echo "✅ All gates passed - Proceeding with upgrade"

# Unhold packages
sudo apt-mark unhold kubeadm kubelet kubectl

# Add v1.34 repository (intermediate)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1.34-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1.34-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes-1.34.list

# Add v1.35 repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1.35-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1.35-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes-1.35.list

sudo apt-get update

# Upgrade step-by-step (can't skip minors)
echo "📦 Upgrading to v1.34.3 (intermediate)..."
sudo apt-get install -y kubeadm=1.34.3-1.1
sudo kubeadm upgrade apply v1.34.3 -y
sudo apt-get install -y kubelet=1.34.3-1.1 kubectl=1.34.3-1.1
sudo systemctl restart kubelet

# Verify canary still healthy after intermediate
sleep 10
CANARY_HEALTH=$(kubectl get pods -l app=upgrade-canary -o jsonpath='{.items[0].status.phase}')
if [ "$CANARY_HEALTH" != "Running" ]; then
    echo "⚠️  Canary degraded after 1.34 upgrade!"
    read -p "Continue to 1.35? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Rolling back..."
        exit 1
    fi
fi

echo "📦 Upgrading to v1.35.3 (target)..."
sudo apt-get install -y kubeadm=1.35.3-1.1
sudo kubeadm upgrade apply v1.35.3 -y
sudo apt-get install -y kubelet=1.35.3-1.1 kubectl=1.35.3-1.1
sudo systemctl restart kubelet

# Re-hold packages
sudo apt-mark hold kubeadm kubelet kubectl

echo "🎉 Control plane upgrade complete!"
kubectl get nodes
EOF

chmod +x upgrade-control-plane-gated.sh
```

---

## 🎯 Phase 4: Worker Node Upgrade (Rolling Update Strategy)

### Interview Question: "How do you upgrade worker nodes without downtime?"

**Answer:** Rolling update with drain, upgrade, uncordon pattern - one node at a time.

```bash
cat << 'EOF' > rolling-worker-upgrade.sh
#!/bin/bash
# Production rolling update strategy

set -e

# Get all worker nodes (exclude control plane)
WORKER_NODES=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane!=' -o name | cut -d'/' -f2)

if [ -z "$WORKER_NODES" ]; then
    echo "No worker nodes found"
    exit 1
fi

echo "🔄 Starting Rolling Worker Node Upgrade"
echo "Workers to upgrade: $WORKER_NODES"

for WORKER in $WORKER_NODES; do
    echo ""
    echo "========================================="
    echo "Upgrading worker: $WORKER"
    echo "========================================="
    
    # Step 1: Drain the node (graceful pod eviction)
    echo "1/4 Draining node $WORKER..."
    kubectl drain $WORKER --ignore-daemonsets --delete-emptydir-data --timeout=120s
    
    # Step 2: Verify canary pods redistributed
    echo "2/4 Verifying canary health on remaining nodes..."
    CANARY_PODS=$(kubectl get pods -l app=upgrade-canary -o wide | grep -v NAME | wc -l)
    echo "   Canary pods still running: $CANARY_PODS"
    
    # Step 3: Upgrade the worker (SSH or local)
    echo "3/4 Upgrading node $WORKER..."
    ssh $WORKER "sudo bash -s" << 'ENDSSH'
        apt-mark unhold kubeadm kubelet kubectl
        apt-get update
        apt-get install -y kubeadm=1.34.3-1.1
        kubeadm upgrade node
        apt-get install -y kubelet=1.34.3-1.1 kubectl=1.34.3-1.1
        systemctl restart kubelet
        apt-get install -y kubeadm=1.35.3-1.1
        kubeadm upgrade node
        apt-get install -y kubelet=1.35.3-1.1 kubectl=1.35.3-1.1
        systemctl restart kubelet
        apt-mark hold kubeadm kubelet kubectl
ENDSSH
    
    # Step 4: Uncordon and verify
    echo "4/4 Uncordoning $WORKER..."
    kubectl uncordon $WORKER
    
    # Wait for node to be ready
    sleep 30
    kubectl wait --for=condition=Ready node/$WORKER --timeout=60s
    
    # Final canary check for this node
    kubectl get pods -l app=upgrade-canary -o wide
    
    echo "✅ Worker $WORKER upgraded successfully"
    
    # Pause between upgrades for stability
    if [ "$WORKER" != "${WORKER_NODES##* }" ]; then
        echo "Waiting 30 seconds before next worker..."
        sleep 30
    fi
done

echo ""
echo "🎉 All worker nodes upgraded successfully!"
kubectl get nodes -o wide
EOF

chmod +x rolling-worker-upgrade.sh
```

---

## 🎯 Phase 5: Post-Upgrade Validation (The "Prove It" Phase)

### Interview Question: "How do you prove the upgrade was successful?"

**Answer:** Automated validation with business metrics.

```bash
cat << 'EOF' > post-upgrade-validation.sh
#!/bin/bash

echo "📊 Phase 5: Post-Upgrade Validation"
echo "====================================="

VALIDATION_PASSED=0
VALIDATION_FAILED=0

# Test 1: Node Version Check
echo -n "Test 1: Node versions... "
NODE_VERSIONS=$(kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}')
if [[ "$NODE_VERSIONS" == *"v1.35"* ]]; then
    echo "✅ PASSED"
    ((VALIDATION_PASSED++))
else
    echo "❌ FAILED"
    ((VALIDATION_FAILED++))
fi

# Test 2: Canary Workload Health
echo -n "Test 2: Canary workload... "
CANARY_READY=$(kubectl get pods -l app=upgrade-canary -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
if [[ "$CANARY_READY" == *"True"* ]]; then
    echo "✅ PASSED"
    ((VALIDATION_PASSED++))
else
    echo "❌ FAILED"
    ((VALIDATION_FAILED++))
fi

# Test 3: API Server Responsiveness
echo -n "Test 3: API server... "
if kubectl cluster-info > /dev/null 2>&1; then
    echo "✅ PASSED"
    ((VALIDATION_PASSED++))
else
    echo "❌ FAILED"
    ((VALIDATION_FAILED++))
fi

# Test 4: DNS Resolution
echo -n "Test 4: DNS resolution... "
if kubectl run dns-test --rm -it --image=busybox:1.28 --restart=Never -- nslookup kubernetes.default > /dev/null 2>&1; then
    echo "✅ PASSED"
    ((VALIDATION_PASSED++))
else
    echo "❌ FAILED"
    ((VALIDATION_FAILED++))
fi

# Test 5: New Deployment Creation
echo -n "Test 5: New deployment creation... "
kubectl create deployment validation-test --image=nginx --replicas=1 > /dev/null 2>&1
if kubectl wait --for=condition=available deployment/validation-test --timeout=30s > /dev/null 2>&1; then
    echo "✅ PASSED"
    ((VALIDATION_PASSED++))
    kubectl delete deployment validation-test > /dev/null 2>&1
else
    echo "❌ FAILED"
    ((VALIDATION_FAILED++))
fi

# Test 6: Service Connectivity
echo -n "Test 6: Service connectivity... "
kubectl expose deployment upgrade-canary --port=80 --target-port=80 --name=canary-test > /dev/null 2>&1
if kubectl run connectivity-test --rm -it --image=busybox:1.28 --restart=Never -- wget -qO- http://canary-test > /dev/null 2>&1; then
    echo "✅ PASSED"
    ((VALIDATION_PASSED++))
    kubectl delete service canary-test > /dev/null 2>&1
else
    echo "❌ FAILED"
    ((VALIDATION_FAILED++))
fi

# Summary
echo ""
echo "====================================="
echo "VALIDATION SUMMARY"
echo "Passed: $VALIDATION_PASSED"
echo "Failed: $VALIDATION_FAILED"
echo "====================================="

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "🎉 CLUSTER UPGRADE SUCCESSFUL!"
    echo "✅ All validation tests passed"
    exit 0
else
    echo "⚠️  UPGRADE NEEDS INVESTIGATION"
    echo "$VALIDATION_FAILED tests failed"
    exit 1
fi
EOF

chmod +x post-upgrade-validation.sh
```

---

## 🎯 Phase 6: Rollback Procedure (The "Oh No" Plan)

### Interview Question: "What's your rollback strategy if upgrade fails?"

**Answer:** Multi-level rollback with documented procedures and tested restore.

```bash
cat << 'EOF' > rollback-procedure.sh
#!/bin/bash
# Emergency rollback procedure

echo "🚨 INITIATING ROLLBACK PROCEDURE"
echo "================================="
echo "This will rollback cluster to v1.33.0"

read -p "Confirm rollback? (type 'ROLLBACK' to confirm): " CONFIRM
if [ "$CONFIRM" != "ROLLBACK" ]; then
    echo "Rollback cancelled"
    exit 0
fi

# Level 1: Application Rollback
echo "Level 1: Restoring application state..."
kubectl delete deployment upgrade-canary 2>/dev/null
kubectl apply -f upgrade-artifacts/*/full-cluster-state.yaml 2>/dev/null || echo "App restore skipped"

# Level 2: Control Plane Rollback
echo "Level 2: Rolling back control plane..."
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get install -y kubeadm=1.33.0-1.1
sudo kubeadm upgrade apply v1.33.0 --force
sudo apt-get install -y kubelet=1.33.0-1.1 kubectl=1.33.0-1.1
sudo systemctl restart kubelet
sudo apt-mark hold kubeadm kubelet kubectl

# Level 3: etcd Restore (Last Resort)
echo "Level 3: etcd restore (if available)..."
LATEST_ETCD_BACKUP=$(ls -t upgrade-artifacts/*/etcd-snapshot-*.db 2>/dev/null | head -1)
if [ -f "$LATEST_ETCD_BACKUP" ]; then
    echo "Found etcd backup: $LATEST_ETCD_BACKUP"
    echo "To restore: ETCDCTL_API=3 etcdctl snapshot restore $LATEST_ETCD_BACKUP"
else
    echo "No etcd backup found"
fi

# Verify rollback
kubectl get nodes
echo "✅ Rollback complete - Verify cluster state"
EOF

chmod +x rollback-procedure.sh
```

---

## 📊 DevOps Interview Quick Reference Card

| Interview Question | Key Points from This Plan |
|------------------|--------------------------|
| **How do you plan an upgrade?** | 6 phases: Assess → Canary → Add-ons → Control Plane → Workers → Validate |
| **How do you ensure zero downtime?** | 3-replica canary, podAntiAffinity, rolling worker upgrades, continuous monitoring |
| **What's your validation strategy?** | 6 automated tests + business metric verification |
| **How do you handle failures?** | 3-level rollback: Apps → Control Plane → etcd |
| **Why upgrade add-ons first?** | Compatibility window: new add-ons must work with old nodes during upgrade |
| **What are upgrade gates?** | Canary health → Add-on version → Resources → kubeadm plan → Manual approval |
| **How do you prove success?** | Automated validation script + canary uptime metrics |

---

## 🚀 Executive Script: One-Command Orchestration

```bash
cat << 'EOF' > orchestrate-upgrade.sh
#!/bin/bash
# Master orchestration script

echo "🚀 Kubernetes Upgrade Orchestrator v1.33 → v1.35.3"
echo "=================================================="

# Phase 0: Assessment
./pre-upgrade-assessment.sh
./cluster-readiness-score.sh || exit 1

# Phase 1: Deploy Canary
./deploy-canary.sh

# Start monitoring in background
./continuous-monitor.sh &
MONITOR_PID=$!

# Phase 2: Upgrade Add-ons
./upgrade-addons-first.sh

# Phase 3: Upgrade Control Plane
./upgrade-control-plane-gated.sh

# Phase 4: Upgrade Workers
./rolling-worker-upgrade.sh

# Stop monitoring
kill $MONITOR_PID

# Phase 5: Validate
./post-upgrade-validation.sh

echo "🎉 Upgrade orchestration complete!"
EOF

chmod +x orchestrate-upgrade.sh
```

---

## 🎯 Key Takeaways for Your Interview

1. **Always start with canary deployment** - Prove the cluster works BEFORE touching anything
2. **Add-ons are critical** - Most failures come from incompatible CoreDNS/kube-proxy
3. **Validation gates prevent disasters** - Never proceed if a gate fails
4. **Document everything** - Screenshots, logs, and scripts are your evidence
5. **Practice rollback** - Knowing how to revert is as important as upgrade
6. **Monitor continuously** - Real-time alerts catch issues immediately
7. **Automate where possible** - Scripts reduce human error

This plan demonstrates **production-grade thinking** that will impress any DevOps interviewer! 🚀
